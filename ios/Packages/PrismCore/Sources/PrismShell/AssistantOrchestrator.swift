import Foundation
import PrismAI
import PrismDraw

@MainActor public final class AssistantOrchestrator {
    public private(set) var archive: ShellArchive
    public private(set) var scene: LensScene = .blank
    public private(set) var phase = "Ready"
    public private(set) var lastError: String?
    public private(set) var connected = false
    public private(set) var pageIndex = 0
    public private(set) var expiresAt: Date?
    public private(set) var activeCandidate: ProactiveCandidate?
    public private(set) var sources = ContextSnapshot()
    public private(set) var activeRequestID: UUID?
    public private(set) var currentTurnID: UUID?
    public private(set) var pinned = false
    public var onChange: (() -> Void)?
    public var now: () -> Date
    public let model: any ExperienceModel
    private let repository: any ShellRepository
    private let native: any NativeToolBoundary
    private let link: any ShellDeviceLink
    private let voice: any ShellVoiceOutput
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var mutationInFlight = false
    private var lastProjection: Data?
    private var candidateEvaluation = false
    private var selectedActionIndex = 0
    private var reviewedActionID: String?
    private var lastPrunedAt = Date.distantPast
    public init(repository: any ShellRepository, model: any ExperienceModel, native: any NativeToolBoundary,
                link: any ShellDeviceLink, voice: any ShellVoiceOutput, now: @escaping () -> Date = Date.init) throws {
        self.repository = repository; self.model = model; self.native = native; self.link = link; self.voice = voice; self.now = now
        archive = try repository.load()
        archive.prune(now: now())
        for i in archive.receipts.indices where archive.receipts[i].status == .executing {
            archive.receipts[i].status = .uncertain; archive.receipts[i].summary = "Interrupted action; reconcile before retrying"
        }
        for i in archive.conversations.indices where archive.conversations[i].status == "pending" { archive.conversations[i].status = "interrupted" }
        try repository.save(archive)
    }
    public var isExecutingAction: Bool { mutationInFlight }
    public func waitForCurrentTurn() async { await task?.value }
    public var currentRecord: ConversationRecord? { archive.conversations.last { $0.id == currentTurnID } }
    public var actions: [ProposedAction] {
        guard let record = currentRecord else { return [] }
        return (record.turn?.proposedActions ?? []).filter { action in
            !archive.receipts.contains { $0.id == record.id.uuidString + ":" + action.id }
        }
    }
    public var selectedAction: ProposedAction? { actions.isEmpty ? nil : actions[min(selectedActionIndex, actions.count - 1)] }
    public func nextChoice() {
        guard !actions.isEmpty, let turn = currentRecord?.turn else { return }
        selectedActionIndex = (selectedActionIndex + 1) % actions.count
        reviewedActionID = nil; scene = turn.lensScene; pageIndex = 0; expiresAt = now().addingTimeInterval(120); changed()
    }
    public var lastReceipt: ActionReceipt? { archive.receipts.last }
    public var viewport: DrawViewport {
        var projectedScene = scene
        if projectedScene.kind == .choice, let selectedAction {
            for i in projectedScene.items.indices where projectedScene.items[i].actionID == selectedAction.id {
                projectedScene.items[i].label = "> " + projectedScene.items[i].label
            }
        }
        let pages = PrismSceneRenderer.pages(archive.privacy.privateMode ? .blank : projectedScene, now: now(), stale: !connected)
        var viewport = pages[min(pageIndex, pages.count - 1)]
        if reviewedActionID != nil && !archive.privacy.privateMode {
            viewport.primitives.removeAll { if case let .text(_,_,y,_,_) = $0 { return y == 344 }; return false }
            viewport.primitives.append(.text(pageIndex >= pages.count - 1 ? "R CONFIRM  L CANCEL" : "R REVIEW NEXT", x: 32, y: 344, color: 0x00AAAAAA, anchor: .topLeft))
        } else if !actions.isEmpty && !archive.privacy.privateMode {
            viewport.primitives.removeAll { if case let .text(_,_,y,_,_) = $0 { return y == 344 }; return false }
            viewport.primitives.append(.text(actions.count > 1 ? "R REVIEW  L NEXT" : "R REVIEW ACTION", x:32,y:344,color:0x00AAAAAA,anchor:.topLeft))
        }
        return viewport
    }
    public var watchSnapshot: ShellWatchSnapshot {
        .init(version: archive.revision, updatedAt: now(), sessionID: archive.session.id, phase: phase, connected: connected,
              privateMode: archive.privacy.privateMode, scene: scene, actions: actions, receipt: lastReceipt?.summary,
              canUndo: lastReceipt?.status == .succeeded && lastReceipt?.undoToken != nil, expiresAt: expiresAt)
    }
    public func setConnection(_ value: Bool) {
        guard connected != value else { return }
        connected = value; lastProjection = nil
        if !value { cancel(); currentTurnID = nil; activeCandidate = nil; phase = "Monocle disconnected" }
        else { scene = .blank; phase = "Ready"; currentTurnID = nil; activeCandidate = nil; expiresAt = nil }
        changed()
    }
    public func updatePrivacy(_ settings: PrivacySettings) throws {
        guard (1...365).contains(settings.retentionDays) else { throw ShellError.invalid("Retention must be 1 to 365 days") }
        guard !mutationInFlight else { throw ShellError.unavailable("Wait for the active action receipt") }
        cancel(); link.blank()
        try transaction { $0.privacy = settings; $0.prune(now: now()) }
        scene = .blank; currentTurnID = nil; activeCandidate = nil; phase = "Ready"; expiresAt = nil; pinned = false; changed()
    }
    public func newSession(project: String? = nil, kind: SessionKind = .conversation) throws {
        guard !mutationInFlight else { throw ShellError.unavailable("Wait for the active action receipt") }
        clear()
        try transaction {
            $0.sessions.append($0.session)
            $0.session = AssistantSession(); $0.session.startedAt = now(); $0.session.project = project; $0.session.kind = kind
        }
        changed()
    }
    public func refreshContext() async {
        let privacy = archive.privacy
        let refreshed = await native.context(privacy: privacy, now: now())
        guard privacy == archive.privacy else { return }
        sources = refreshed
        let candidates = CalendarProactiveSource().candidates(snapshot: sources, now: now())
        if let activeCandidate, !candidates.contains(where: { $0.id == activeCandidate.id }) { clear() }
        changed()
    }
    public func submit(_ input: String) {
        guard !mutationInFlight else { showError(ShellError.unavailable("Wait for the active action receipt")); return }
        cancel()
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 262_144 else { showError(ShellError.invalid("Enter a non-empty request within 256 KB")); return }
        currentTurnID = nil; reviewedActionID = nil
        let token = generation; let id = UUID(); activeRequestID = id
        task = Task { await self.run(text: text, id: id, token: token, source: "typed") }
    }
    public func beginListening() {
        guard !mutationInFlight else { return }
        cancel(); currentTurnID = nil; activeCandidate = nil; pinned = false
        guard connected else { showError(ShellError.unavailable("Connect your Monocle to use its microphone")); return }
        guard archive.privacy.cloudProcessing else { showError(ShellError.denied("Enable cloud processing before voice transcription")); return }
        let id = UUID(); activeRequestID = id
        do { try link.beginInteraction() } catch { showError(error); return }
        scene = .activity("LISTENING"); phase = "Listening"; expiresAt = now().addingTimeInterval(20); changed()
        do { try link.captureAudio(requestID: id) } catch { cancel(); showError(error) }
    }
    public func receiveAudio(_ signed8Bit: Data, requestID: UUID, speech: any SpeechClient) {
        guard activeRequestID == requestID, phase == "Listening", !signed8Bit.isEmpty, signed8Bit.count <= 64_000 else { return }
        let token = generation
        scene = .activity("TRANSCRIBING"); phase = "Transcribing"; expiresAt = now().addingTimeInterval(65); changed()
        task = Task {
            do {
                let pcm = MonocleAudioConverter().signed8BitPCMTo16BitLittleEndian(signed8Bit)
                let transcript = try await speech.transcribe(.init(requestID: .init(rawValue: requestID), pcm16MonoLittleEndian: pcm, sampleRate: 8000))
                try self.check(token)
                guard transcript.requestID.rawValue == requestID else { throw ShellError.stale }
                guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ShellError.invalid("No speech recognized") }
                let artifact = LibraryArtifact(sessionID: self.archive.session.id, kind: .transcript, title: "Voice capture", body: transcript.text,
                                               project: self.archive.session.project, provenance: .init(source: "monocle microphone", provider: "transcription", requestID: requestID, createdAt: self.now()),
                                               expiresAt: self.retentionEnd, rawMedia: self.archive.privacy.retainRawAudio ? signed8Bit : nil)
                try self.transaction { $0.artifacts.append(artifact) }
                await self.run(text: transcript.text, id: requestID, token: token, source: "monocle audio")
            } catch { self.fail(error, token: token) }
        }
    }
    private var retentionEnd: Date { now().addingTimeInterval(Double(archive.privacy.retentionDays) * 86400) }
    private func run(text: String, id: UUID, token: UUID, source: String) async {
        do {
            try check(token)
            guard archive.privacy.cloudProcessing else { throw ShellError.denied("Enable cloud processing in Settings to use the assistant") }
            if connected { try link.beginInteraction() }
            currentTurnID = nil; activeCandidate = nil; pinned = false; lastError = nil
            try transaction { $0.conversations.append(.init(id: id, sessionID: $0.session.id, userText: text,
                provenance: .init(source: source, provider: model.providerID, requestID: id, createdAt: now()))) }
            scene = .activity("THINKING"); phase = "Thinking"; expiresAt = now().addingTimeInterval(180); changed()
            await refreshContext(); try check(token)
            let context = ContextBundle.assemble(archive: archive, sources: sources, connected: connected, now: now())
            let plan = try await compose(.init(id: id, input: text, context: context), token: token)
            try check(token); try plan.validate(now: now())
            guard plan.turn.proactiveDecision == nil else { throw ShellError.invalid("Unexpected proactive response") }
            try accept(plan, id: id, userText: text, source: source)
        } catch { fail(error, token: token) }
    }
    private func compose(_ request: ModelRequest, token: UUID) async throws -> ExperiencePlan {
        var request = request
        for _ in 0..<5 {
            try check(token)
            switch try await model.generate(request) {
            case .plan(let plan): try check(token); return plan
            case .reads(let calls):
                guard !calls.isEmpty, calls.count <= 4, request.candidates.isEmpty else { throw ShellError.invalid("Invalid read tools") }
                for call in calls {
                    try check(token)
                    guard !call.name.mutates else { throw ShellError.denied("Mutation requires an action preview") }
                    let result = try read(call)
                    request.toolResults.append(.init(callID: call.id, tool: call.name, content: result))
                }
            }
        }
        throw ShellError.unavailable("The assistant reached the tool limit. Please narrow the request.")
    }
    private func read(_ call: ReadToolCall) throws -> String {
        switch call.name {
        case .retrieveNotes:
            guard let query = call.arguments.query, !query.isEmpty else { throw ShellError.invalid("Search needs a query") }
            var found = archive.search(query, project: call.arguments.project)
            for i in found.indices { found[i].rawMedia = nil }
            var admitted: [LibraryArtifact] = []; var size = 0
            for a in found {
                let n = try ShellJSON.encoder().encode(a).count
                if n + size > 262_144 { continue }; admitted.append(a); size += n
            }
            return String(decoding: try ShellJSON.encoder().encode(admitted), as: UTF8.self) + "\nOmitted records: \(found.count - admitted.count)"
        case .readCalendar:
            guard archive.privacy.calendarEnabled, !sources.unavailableSources.contains("calendar") else { return "Calendar unavailable or permission not granted" }
            return String(decoding: try ShellJSON.encoder().encode(sources.calendar), as: UTF8.self)
        case .agentStatus:
            guard archive.privacy.agentEnabled, !sources.unavailableSources.contains("agents") else { return "Agent integration unconfigured or unavailable" }
            return String(decoding: try ShellJSON.encoder().encode(sources.agentExceptions), as: UTF8.self)
        default: throw ShellError.denied("Not a read tool")
        }
    }
    private func accept(_ plan: ExperiencePlan, id: UUID, userText: String, source: String) throws {
        let turn = plan.turn
        try transaction { a in
            if let i = a.conversations.firstIndex(where: { $0.id == id }) { a.conversations[i].turn = turn; a.conversations[i].status = "completed" }
            else { a.conversations.append(.init(id: id, sessionID: a.session.id, userText: userText, turn: turn,
                                               provenance: .init(source: source, provider: model.providerID, requestID: id, createdAt: now()), status: "completed")) }
            if let project = turn.project { a.session.project = project }
            a.artifacts.append(.init(sessionID: a.session.id, kind: .answer, title: String(userText.prefix(160)), body: turn.canonicalAnswer,
                                     project: a.session.project, provenance: .init(source: source, provider: model.providerID, requestID: id, createdAt: now()), expiresAt: retentionEnd))
            for m in turn.artifacts {
                a.artifacts.append(.init(sessionID: a.session.id, kind: m.kind, title: m.title, body: m.body, project: m.project ?? a.session.project,
                                         topic: m.topic, provenance: .init(source: "assistant derived", provider: model.providerID, requestID: id, createdAt: now()), expiresAt: retentionEnd))
            }
        }
        currentTurnID = id; activeRequestID = nil; scene = turn.lensScene; phase = turn.clarification == nil ? "Ready" : "Clarification"
        pageIndex = 0; expiresAt = now().addingTimeInterval(Double(scene.expiresInSeconds)); changed()
        if archive.privacy.spokenOutput, let speech = turn.spokenResponse { voice.speak(speech) }
    }
    public func confirm(actionID: String, revision: Int) async throws {
        guard !mutationInFlight, activeRequestID == nil, revision == archive.revision, let record = currentRecord,
              let action = actions.first(where: { $0.id == actionID }), expiresAt.map({ $0 > now() }) == true else { throw ShellError.stale }
        try action.validate(now: now())
        let key = record.id.uuidString + ":" + action.id
        if let receipt = archive.receipts.first(where: { $0.id == key }) {
            if receipt.status == .uncertain || receipt.status == .executing { throw ShellError.uncertain }
            return // Never execute a duplicate, including an undone action.
        }
        guard action.tool.mutates else { throw ShellError.invalid("Read tools are performed by the assistant") }
        mutationInFlight = true; defer { mutationInFlight = false }
        let actionGeneration = generation
        var receipt = ActionReceipt(id: key, requestID: record.id, action: action, status: .succeeded, summary: action.summary, createdAt: now())
        if action.tool == .createReminder {
            receipt.status = .executing; receipt.summary = "Creating reminder"
            try transaction { $0.receipts.append(receipt) }; changed()
            do {
                let external = try await native.createReminder(arguments: action.arguments, idempotencyKey: key)
                receipt.externalID = external; receipt.undoToken = key; receipt.status = .succeeded
                receipt.summary = "Reminder created: \(action.arguments.title ?? "")"
            } catch let error as ShellError {
                if case .denied = error { receipt.status = .failed; receipt.summary = error.localizedDescription }
                else if case .unavailable = error { receipt.status = .failed; receipt.summary = error.localizedDescription }
                else { receipt.status = .uncertain; receipt.summary = "Reminder outcome unconfirmed; reconcile before retrying" }
            } catch {
                receipt.status = .uncertain; receipt.summary = "Reminder outcome unconfirmed; reconcile before retrying"
            }
            try transaction { a in if let i = a.receipts.firstIndex(where: { $0.id == key }) { a.receipts[i] = receipt }; appendReceiptArtifact(receipt, to: &a) }
        } else {
            try transaction { a in
                switch action.tool {
                case .saveNote:
                    let id = UUID(); receipt.externalID = id.uuidString; receipt.undoToken = key
                    a.artifacts.append(.init(id: id, sessionID: a.session.id, kind: .note, title: action.arguments.title!, body: action.arguments.body!,
                                             project: action.arguments.project ?? a.session.project, topic: action.arguments.topic,
                                             provenance: .init(source: "confirmed note", requestID: record.id, createdAt: now()), expiresAt: retentionEnd))
                    receipt.summary = "Note saved: \(action.arguments.title!)"
                case .startTimer:
                    receipt.previousTimer = a.timer
                    a.timer = .init(id: key, title: action.arguments.title!, end: now().addingTimeInterval(Double(action.arguments.seconds!)))
                    receipt.undoToken = key; receipt.summary = "Timer started: \(action.arguments.title!)"
                case .stopTimer: receipt.previousTimer = a.timer; a.timer = nil; receipt.undoToken = key; receipt.summary = "Timer stopped"
                case .setSession:
                    receipt.previousSession = a.session; a.session.kind = action.arguments.sessionKind!; a.session.project = action.arguments.project ?? a.session.project
                    receipt.undoToken = key; receipt.summary = "Session updated"
                default: throw ShellError.invalid("Unsupported mutation")
                }
                a.receipts.append(receipt); appendReceiptArtifact(receipt, to: &a)
            }
        }
        // If the user blanked while a native effect was committing, retain the receipt but respect blank.
        if generation == actionGeneration { showReceipt(receipt) } else { changed() }
    }
    private func appendReceiptArtifact(_ receipt: ActionReceipt, to archive: inout ShellArchive) {
        archive.artifacts.append(.init(sessionID: archive.session.id, kind: .receipt, title: receipt.summary,
                                      body: String(decoding: (try? ShellJSON.encoder().encode(receipt)) ?? Data(), as: UTF8.self),
                                      project: archive.session.project, provenance: .init(source: "host action executor", requestID: receipt.requestID, createdAt: now()), expiresAt: retentionEnd))
    }
    public func reconcile(receiptID: String) async throws {
        guard !mutationInFlight, let i = archive.receipts.firstIndex(where: { $0.id == receiptID }),
              archive.receipts[i].status == .uncertain, archive.receipts[i].action.tool == .createReminder else { throw ShellError.stale }
        mutationInFlight = true; defer { mutationInFlight = false }
        let found = try await native.findReminder(idempotencyKey: receiptID)
        try transaction { a in
            a.receipts[i].status = found == nil ? .failed : .succeeded
            a.receipts[i].externalID = found; a.receipts[i].undoToken = found == nil ? nil : receiptID
            a.receipts[i].summary = found == nil ? "No matching reminder found. Ask again to propose a new action." : "Reminder creation reconciled"
        }
        showReceipt(archive.receipts[i])
    }
    public func undo(receiptID: String) async throws {
        guard !mutationInFlight, let i = archive.receipts.firstIndex(where: { $0.id == receiptID }),
              archive.receipts[i].status == .succeeded, archive.receipts[i].undoToken != nil else { throw ShellError.stale }
        mutationInFlight = true; defer { mutationInFlight = false }
        let receipt = archive.receipts[i]
        if receipt.action.tool == .createReminder {
            guard let external = receipt.externalID else { throw ShellError.uncertain }
            try await native.undoReminder(externalID: external, idempotencyKey: receipt.id)
        }
        try transaction { a in
            switch receipt.action.tool {
            case .saveNote:
                if let note = a.artifacts.first(where: { $0.id.uuidString == receipt.externalID }), note.provenance.source == "user edited note" { throw ShellError.denied("The note was edited; delete it explicitly in Library") }
                a.artifacts.removeAll { $0.id.uuidString == receipt.externalID }
            case .startTimer:
                guard a.timer?.id == receipt.id || a.timer == nil else { throw ShellError.stale }; a.timer = receipt.previousTimer
            case .stopTimer: guard a.timer == nil else { throw ShellError.stale }; a.timer = receipt.previousTimer
            case .setSession: guard let prior = receipt.previousSession, a.session.id == prior.id else { throw ShellError.stale }; a.session = prior
            default: break
            }
            a.receipts[i].status = .undone; a.receipts[i].undoToken = nil; a.receipts[i].summary = "Undone: \(receipt.action.summary)"
            appendReceiptArtifact(a.receipts[i], to: &a)
        }
        showReceipt(archive.receipts[i])
    }
    private func showReceipt(_ receipt: ActionReceipt) {
        reviewedActionID = nil
        scene = .init(kind: .confirmation, title: receipt.status == .succeeded ? "DONE" : receipt.status.rawValue.uppercased(), body: receipt.summary, expiresInSeconds: 15)
        let pending = !actions.isEmpty
        if !pending { currentTurnID = nil }
        selectedActionIndex = 0
        expiresAt = now().addingTimeInterval(pending ? 120 : 15); pageIndex = 0; phase = "Ready"
        if pending { scene.expiresInSeconds = 120 }
        if receipt.status == .succeeded, receipt.action.tool == .startTimer, let timer = archive.timer {
            scene = .init(kind:.timer,title:"TIMER STARTED",body:timer.title,timerEnd:timer.end,expiresInSeconds:60)
            expiresAt = now().addingTimeInterval(60)
        }
        changed()
        if archive.privacy.spokenOutput { voice.speak(receipt.summary) }
    }
    public func considerProactivity() async {
        guard !candidateEvaluation, !mutationInFlight, activeRequestID == nil, currentTurnID == nil, scene.kind == .blank,
              archive.privacy.cloudProcessing, archive.privacy.proactiveEnabled, archive.privacy.calendarEnabled,
              !archive.privacy.privateMode, now().timeIntervalSince(archive.lastInterruptionAt ?? .distantPast) >= 60 else { return }
        let candidates = CalendarProactiveSource().candidates(snapshot: sources, now: now()).filter { c in
            guard let history = archive.candidateHistory[c.id] else { return true }
            return history.state == .snoozed && (history.snoozedUntil ?? .distantFuture) <= now()
        }
        guard !candidates.isEmpty else { return }
        candidateEvaluation = true; defer { candidateEvaluation = false }
        let token = generation; let id = UUID()
        do {
            try transaction { a in for c in candidates { a.candidateHistory[c.id] = .init(state: .evaluated, expiresAt: c.expiresAt) } }
            let context = ContextBundle.assemble(archive: archive, sources: sources, connected: connected, now: now())
            let plan = try await compose(.init(id: id, input: "Interpret these real event candidates in context; decide whether any merits a temporary surface now.", context: context, candidates: candidates), token: token)
            try check(token); try plan.validate(now: now())
            guard let decision = plan.turn.proactiveDecision, !decision.reason.isEmpty,
                  let candidate = candidates.first(where: { $0.id == decision.candidateID }), candidate.expiresAt > now(),
                  CalendarProactiveSource().candidates(snapshot: sources, now: now()).contains(where: { $0.id == candidate.id }),
                  plan.turn.proposedActions.isEmpty else { throw ShellError.stale }
            try transaction { a in
                a.candidateHistory[candidate.id] = .init(state: decision.disposition == .show ? .shown : .suppressed, expiresAt: candidate.expiresAt, interpretation: decision.reason)
                if decision.disposition == .show { a.lastInterruptionAt = now() }
                a.artifacts.append(.init(sessionID: a.session.id, kind: .event, title: candidate.source, body: plan.turn.canonicalAnswer,
                                         project: a.session.project, provenance: .init(source: candidate.source, provider: model.providerID, requestID: id, createdAt: now()), expiresAt: candidate.expiresAt))
            }
            if decision.disposition == .show {
                scene = plan.turn.lensScene; activeCandidate = candidate; phase = "Now"; pageIndex = 0
                expiresAt = min(candidate.expiresAt, now().addingTimeInterval(Double(scene.expiresInSeconds))); changed()
                // Proactive cards are quiet by default. Audio remains user-invoked.
            } else { changed() }
        } catch { if token == generation { lastError = error.localizedDescription; changed() } }
    }
    public func dismissCandidate(snoozeSeconds: Int? = nil) throws {
        guard let c = activeCandidate else { clear(); return }
        try transaction { a in a.candidateHistory[c.id] = .init(state: snoozeSeconds == nil ? .dismissed : .snoozed, expiresAt: c.expiresAt,
                                                                snoozedUntil: snoozeSeconds.map { min(c.expiresAt, now().addingTimeInterval(Double(max(60,$0)))) }) }
        clear()
    }
    public func reviewOrConfirm(actionID: String) async throws {
        guard let action = actions.first(where: { $0.id == actionID }), activeRequestID == nil else { throw ShellError.stale }
        if reviewedActionID != actionID {
            reviewedActionID = actionID
            let a = action.arguments
            var details = [action.summary, a.title, a.body, a.project.map { "Project: " + $0 }, a.topic.map { "Topic: " + $0 }].compactMap { $0 }
            if let due = a.dueAt { details.append(due.formatted(date: .complete, time: .shortened)) }
            if let seconds = a.seconds { details.append("Duration: \(seconds) seconds") }
            if let kind = a.sessionKind { details.append("Session: " + kind.rawValue) }
            scene = .init(kind: .confirmation, title: "REVIEW ACTION", body: details.joined(separator: "\n"), expiresInSeconds: 120)
            pageIndex = 0; expiresAt = now().addingTimeInterval(120); changed(); return
        }
        let count = PrismSceneRenderer.pages(scene, now: now()).count
        if pageIndex < count - 1 { nextPage(); return }
        try await confirm(actionID: actionID, revision: archive.revision)
    }
    public func tick() {
        if now().timeIntervalSince(lastPrunedAt) >= 3600 {
            do { try transaction { $0.prune(now: now()) }; lastPrunedAt = now() } catch { showError(error) }
        }
        if let expiresAt, expiresAt <= now(), !pinned || activeRequestID != nil { clear() }
        if let c = activeCandidate, c.expiresAt <= now() { clear() }
        if var timer = archive.timer, timer.end <= now(), !timer.completed {
            timer.completed = true
            do { try transaction { $0.timer = timer }; changed() } catch { showError(error) }
        }
        if scene.kind == .timer { changed(incrementRevision: false) }
    }
    public func nextPage() { pageIndex += 1; let count = PrismSceneRenderer.pages(scene, now: now()).count; if pageIndex >= count { pageIndex = 0 }; changed() }
    public func togglePin() { guard activeRequestID == nil && activeCandidate == nil && scene.kind != .blank else { return }; pinned.toggle(); changed() }
    public func clear() { cancel(); link.blank(); scene = .blank; currentTurnID = nil; activeCandidate = nil; pinned = false; expiresAt = nil; pageIndex = 0; phase = "Ready"; changed() }
    public func cancel() {
        selectedActionIndex = 0; reviewedActionID = nil; generation = UUID(); task?.cancel(); task = nil; activeRequestID = nil; voice.stop(); link.cancelCapture()
        if let i = archive.conversations.lastIndex(where: { $0.status == "pending" }) {
            do { try transaction { $0.conversations[i].status = "cancelled" } } catch { lastError = error.localizedDescription }
        }
    }
    public func editNote(_ id: UUID, title: String, body: String) throws {
        guard !title.isEmpty, body.utf8.count <= 262_144, let index = archive.artifacts.firstIndex(where: { $0.id == id && $0.kind == .note }) else { throw ShellError.invalid("Select a valid note") }
        try transaction { a in a.artifacts[index].title = title; a.artifacts[index].body = body; a.artifacts[index].provenance.source = "user edited note" }
        changed()
    }
    public func deleteArtifact(_ id: UUID) throws { try transaction { $0.artifacts.removeAll { $0.id == id } }; changed() }
    public func deleteAllContent() throws {
        guard !mutationInFlight else { throw ShellError.unavailable("Wait for active action") }
        clear()
        try transaction { a in
            a.artifacts = []; a.conversations = []; a.sessions = []; a.session = AssistantSession()
            a.timer = nil; a.candidateHistory = [:]
            // Preserve minimal external-effect ledger to prevent duplicate effects and retain undo.
            a.receipts = a.receipts.filter { $0.action.tool == .createReminder && [.uncertain,.executing,.succeeded].contains($0.status) }
            for i in a.receipts.indices {
                a.receipts[i].action.arguments = .init()
                a.receipts[i].action.summary = "Reminder action"; a.receipts[i].summary = "Reminder receipt retained for undo and reconciliation"
            }
        }; changed()
    }
    public func processWatch(_ command: ShellWatchCommand) async throws {
        if archive.watchCommands.contains(command.id) { return }
        guard command.sessionID == archive.session.id, command.snapshotVersion == archive.revision,
              abs(now().timeIntervalSince(command.createdAt)) <= 30 else { throw ShellError.stale }
        try transaction { a in a.watchCommands.append(command.id); a.watchCommands = Array(a.watchCommands.suffix(128)) }
        switch command.kind {
        case .ask: beginListening()
        case .clear: clear()
        case .next: nextPage()
        case .confirm: guard let id = command.actionID else { throw ShellError.invalid("Action required") }; try await confirm(actionID: id, revision: archive.revision)
        case .undo: guard let receipt = lastReceipt else { throw ShellError.stale }; try await undo(receiptID: receipt.id)
        case .dismiss: try dismissCandidate()
        case .snooze: try dismissCandidate(snoozeSeconds: 300)
        case .refresh: changed()
        }
    }
    private func check(_ token: UUID) throws { try Task.checkCancellation(); guard token == generation else { throw ShellError.cancelled } }
    private func fail(_ error: Error, token: UUID) {
        guard token == generation else { return }
        activeRequestID = nil
        if let i = archive.conversations.lastIndex(where: { $0.status == "pending" }) { try? transaction { $0.conversations[i].status = "failed" } }
        showError(error)
    }
    public func showError(_ error: Error) {
        cancel(); currentTurnID = nil; activeCandidate = nil; pinned = false
        lastError = error.localizedDescription; phase = "Needs attention"; scene = .init(kind: .alert, title: "PRISM", body: error.localizedDescription)
        pageIndex = 0; expiresAt = now().addingTimeInterval(30); changed()
    }
    private func transaction(_ mutation: (inout ShellArchive) throws -> Void) throws {
        var next = archive; try mutation(&next); next.revision += 1
        try repository.save(next); archive = next
    }
    private func changed(incrementRevision: Bool = true) {
        if incrementRevision { archive.revision += 1 }
        do {
            let data = try PrismDrawPacker.pack(viewport)
            if connected && data != lastProjection { try link.project(data); lastProjection = data }
        } catch { lastError = error.localizedDescription }
        onChange?()
    }
}
