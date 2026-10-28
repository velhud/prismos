#if DEBUG
import Foundation
import PrismShell

/// Explicit XCUITest fixture ingress. Available only in a Debug simulator build, never Release/device.
/// Only external model/OS/voice boundaries are doubled; the app, orchestrator, file store and projections are real.
@MainActor
struct ShellAcceptanceConfiguration {
    let id: UUID
    let plans: [ExperiencePlan]
    var preferences: UserDefaults { UserDefaults(suiteName: "com.prismos.acceptance." + id.uuidString)! }
    static func fromEnvironment() -> Self? {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard let rawID = environment["PRISMOS_ACCEPTANCE_SESSION"], let id = UUID(uuidString: rawID),
              let json = environment["PRISMOS_ACCEPTANCE_PLANS"], json.utf8.count <= 262_144,
              let plans = try? ShellJSON.decoder().decode([ExperiencePlan].self, from: Data(json.utf8)) else { return nil }
        return .init(id: id, plans: plans)
        #else
        return nil
        #endif
    }
}
actor ShellAcceptanceHTTP: ShellHTTPTransport {
    private var plans: [ExperiencePlan]
    init(plans: [ExperiencePlan]) { self.plans = plans }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard request.url?.absoluteString == "https://api.openai.com/v1/responses", !plans.isEmpty else {
            throw ShellError.unavailable("Acceptance fixture exhausted; no network request was sent")
        }
        let text = String(decoding: try ShellJSON.encoder().encode(plans.removeFirst()), as: UTF8.self)
        let body = try JSONSerialization.data(withJSONObject: ["status":"completed", "output":[["type":"message", "content":[["type":"output_text", "text":text]]]]])
        return (body, HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
    }
}
@MainActor
final class ShellAcceptanceOS: NativeToolBoundary {
    private var reminderIDs: [String:String] = [:]
    func context(privacy: PrivacySettings, now: Date) async -> ContextSnapshot {
        var result = ContextSnapshot(observedAt:now); result.unavailableSources = ["calendar","agents"]; return result
    }
    func createReminder(arguments: ToolArguments, idempotencyKey: String) async throws -> String {
        if let id = reminderIDs[idempotencyKey] { return id }
        let id = UUID().uuidString; reminderIDs[idempotencyKey] = id; return id
    }
    func findReminder(idempotencyKey: String) async throws -> String? { reminderIDs[idempotencyKey] }
    func undoReminder(externalID: String, idempotencyKey: String) async throws { reminderIDs.removeValue(forKey:idempotencyKey) }
}
@MainActor final class ShellAcceptanceVoice: ShellVoiceOutput {
    func speak(_ text: String) {}
    func stop() {}
}
#endif
