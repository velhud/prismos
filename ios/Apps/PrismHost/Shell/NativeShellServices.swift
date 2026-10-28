import Foundation
import EventKit
import AVFoundation
import UserNotifications
import PrismShell
import PrismAI

@MainActor
final class EventKitShellTools: NativeToolBoundary {
    let store = EKEventStore()
    let secrets: any SecretStore
    var agentEndpoint: URL?
    init(secrets: any SecretStore = KeychainSecretStore()) {
        self.secrets = secrets
        agentEndpoint = UserDefaults.standard.string(forKey: "prism.agent.endpoint").flatMap(URL.init(string:))
    }
    func requestCalendarAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
    func context(privacy: PrivacySettings, now: Date) async -> ContextSnapshot {
        var result = ContextSnapshot(observedAt: now)
        if privacy.calendarEnabled && EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(7 * 86400), calendars: nil)
            result.calendar = store.events(matching: predicate).prefix(128).map {
                .init(id: $0.eventIdentifier ?? $0.calendarItemIdentifier, title: $0.title ?? "Calendar event", start: $0.startDate,
                      end: $0.endDate, location: $0.location, modifiedAt: $0.lastModifiedDate)
            }
        } else { result.unavailableSources.append("calendar") }
        if privacy.agentEnabled {
            do {
                guard let url = agentEndpoint, url.scheme == "https", url.user == nil, url.password == nil else { throw ShellError.unavailable("Agent gateway unconfigured") }
                let token = try secrets.read("prism.agent.token")
                guard !token.isEmpty else { throw ShellError.unavailable("Agent authentication missing") }
                var request = URLRequest(url: url); request.timeoutInterval = 10
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (bytes, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, bytes.count <= 1_048_576 else { throw ShellError.unavailable("Agent gateway unavailable") }
                let payload = try ShellJSON.decoder().decode(AgentSnapshot.self, from: bytes)
                guard abs(now.timeIntervalSince(payload.generatedAt)) <= 120, payload.exceptions.count <= 128 else { throw ShellError.stale }
                result.agentExceptions = payload.exceptions.filter { $0.observedAt <= now.addingTimeInterval(5) && $0.expiresAt > now }
            } catch { result.unavailableSources.append("agents") }
        } else { result.unavailableSources.append("agents") }
        return result
    }
    private struct AgentSnapshot: Decodable { var generatedAt: Date; var exceptions: [AgentException] }
    private func ensureRemindersAccess() async throws {
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            guard try await store.requestFullAccessToReminders() else { throw ShellError.denied("Reminder access was declined") }
        }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw ShellError.denied("Allow Reminders access in iPhone Settings") }
    }
    private func marker(_ key: String) -> String { "PrismOS action: " + key }
    func findReminder(idempotencyKey: String) async throws -> String? {
        try await ensureRemindersAccess()
        let predicate = store.predicateForReminders(in: nil)
        let items: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        let matches = items.filter { ($0.notes ?? "").components(separatedBy: .newlines).contains(marker(idempotencyKey)) }
        guard matches.count <= 1 else { throw ShellError.uncertain }
        return matches.first?.calendarItemIdentifier
    }
    func createReminder(arguments: ToolArguments, idempotencyKey: String) async throws -> String {
        try await ensureRemindersAccess()
        if let existing = try await findReminder(idempotencyKey: idempotencyKey) { return existing }
        guard let calendar = store.defaultCalendarForNewReminders(), let title = arguments.title, let due = arguments.dueAt else {
            throw ShellError.unavailable("Configure a writable default Reminders list")
        }
        let reminder = EKReminder(eventStore: store); reminder.calendar = calendar; reminder.title = title
        reminder.notes = [arguments.body, marker(idempotencyKey)].compactMap { $0 }.joined(separator: "\n")
        var components = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: due)
        components.timeZone = TimeZone.current; reminder.dueDateComponents = components
        reminder.addAlarm(EKAlarm(absoluteDate: due))
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }
    func undoReminder(externalID: String, idempotencyKey: String) async throws {
        try await ensureRemindersAccess()
        guard let reminder = store.calendarItem(withIdentifier: externalID) as? EKReminder else { return } // already removed
        guard (reminder.notes ?? "").components(separatedBy: .newlines).contains(marker(idempotencyKey)) else {
            throw ShellError.denied("This reminder no longer matches Prism's receipt")
        }
        try store.remove(reminder, commit: true)
    }
}

/// Native synthesized speech, through the phone's current output route. This is not subscription voice.
@MainActor
final class NativeShellVoice: NSObject, ShellVoiceOutput, AVSpeechSynthesizerDelegate {
    private var synthesizer = AVSpeechSynthesizer()
    private(set) var state = "Silent"
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    var onInterrupted: (() -> Void)?
    override init() {
        super.init(); synthesizer.delegate = self
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    guard let self else { return }
                    if note.name == AVAudioSession.routeChangeNotification {
                        // A category-change notification from our own setup is not a device-route change.
                        let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
                        let before = previous?.outputs.map(\.uid)
                        let after = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.uid)
                        if let before, before != after { self.stop(); self.state = "Speech interrupted"; self.onInterrupted?(); self.onChange?() }
                    } else if note.name == AVAudioSession.interruptionNotification {
                        let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                        if type == AVAudioSession.InterruptionType.began.rawValue { self.stop(); self.state = "Speech interrupted"; self.onInterrupted?(); self.onChange?() }
                    } else {
                        self.stop(); self.synthesizer = AVSpeechSynthesizer(); self.synthesizer.delegate = self; self.onInterrupted?()
                    }
                }
            })
        }
    }
    func speak(_ text: String) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            state = "Speaking"; onChange?(); synthesizer.speak(utterance)
        } catch { state = "Speech unavailable"; onInterrupted?(); onChange?() }
    }
    func stop() {
        synthesizer.stopSpeaking(at: .immediate); state = "Silent"; onChange?()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in guard !self.synthesizer.isSpeaking else { return }; self.state = "Silent"; self.onChange?(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}

@MainActor protocol TimerNotificationBoundary {
    func requestAccess() async throws -> Bool
    func authorized() async -> Bool
    func cancel()
    func schedule(_ timer: FocusTimer) async throws
}
@MainActor final class SystemTimerNotificationBoundary: TimerNotificationBoundary {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "prismos.focus.current"
    func requestAccess() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func authorized() async -> Bool {
        let settings = await center.notificationSettings()
        return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }
    func cancel() { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
    func schedule(_ timer: FocusTimer) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Focus timer finished"; content.body = "Your PrismOS focus interval has ended."; content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.end.timeIntervalSinceNow), repeats: false)
        try await center.add(.init(identifier: identifier, content: content, trigger: trigger))
    }
}
/// Optional OS delivery of the canonical focus timer; authorization is explicitly user-requested.
/// Replacing a timer uses one stable notification slot, so undo/restart cannot duplicate alerts.
@MainActor final class NativeTimerNotifications {
    private let boundary: any TimerNotificationBoundary
    private var desired: FocusTimer?
    private var applied: FocusTimer?
    private var updating = false
    private var initialized = false
    var enabled = true
    private(set) var status = "Timer alerts require notification permission"
    init(boundary: (any TimerNotificationBoundary)? = nil) { self.boundary = boundary ?? SystemTimerNotificationBoundary() }
    func requestAccess() async throws -> Bool {
        let granted = try await boundary.requestAccess()
        status = granted ? "Timer alerts enabled" : "Timer alerts declined; timers still run in PrismOS"
        initialized = false; await synchronize(desired)
        return granted
    }
    func synchronize(_ timer: FocusTimer?) async {
        guard enabled else { return }
        desired = timer
        guard !updating else { return }
        updating = true; defer { updating = false }
        repeat {
            let target = desired
            if initialized && target == applied { return }
            initialized = true; boundary.cancel()
            if let target, !target.completed, target.end > Date() {
                if await boundary.authorized() {
                    do { try await boundary.schedule(target); status = "Timer alert scheduled" }
                    catch { status = "Timer is active; its notification could not be scheduled" }
                } else { status = "Timer active; allow notifications for background alerts" }
            }
            applied = target
        } while desired != applied
    }
}
