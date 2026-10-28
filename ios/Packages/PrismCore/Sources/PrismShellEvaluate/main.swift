import Foundation
import PrismShell
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct Reference: Codable {
    struct Context: Codable {
        var calendar: [CalendarItem]?; var agents: [AgentException]?; var calendarUnavailable: Bool?
        var note: String?; var searchQuery: String?; var recentAnswer: String?
    }
    var id: String; var prompt: String; var referencePlan: ExperiencePlan
    var expectedReadTools: [ToolName]; var rubric: String; var context: Context
}
actor CaptureHTTP: ShellHTTPTransport {
    var requests: [Data] = []
    var replay: [Data]?
    init(reference: Reference?) throws {
        if let reference {
            var responses: [Data] = []
            if !reference.expectedReadTools.isEmpty {
                let calls: [[String: Any]] = try reference.expectedReadTools.enumerated().map { index, name in
                    let arguments: [String: String] = name == .retrieveNotes ? ["query": reference.context.searchQuery ?? "naming"] : [:]
                    return ["type":"function_call", "name":name.rawValue, "call_id":"read-\(index)",
                            "arguments":String(decoding:try JSONSerialization.data(withJSONObject:arguments),as:UTF8.self)]
                }
                responses.append(try JSONSerialization.data(withJSONObject:["status":"completed","output":calls]))
            }
            let text = String(decoding:try ShellJSON.encoder().encode(reference.referencePlan),as:UTF8.self)
            responses.append(try JSONSerialization.data(withJSONObject:["status":"completed","output":[["type":"message","content":[["type":"output_text","text":text]]]]]))
            replay = responses
        }
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request.httpBody ?? Data()) // No Authorization header or credential is retained.
        if replay != nil {
            guard !replay!.isEmpty else { throw ShellError.invalid("Replay exhausted") }
            return (replay!.removeFirst(),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        return try await URLSession.shared.data(for:request)
    }
    func captured() -> [Data] { requests }
}
@MainActor final class EvaluationOS: NativeToolBoundary {
    let snapshot: ContextSnapshot
    init(_ snapshot: ContextSnapshot) { self.snapshot = snapshot }
    func context(privacy: PrivacySettings, now: Date) async -> ContextSnapshot { snapshot }
    func createReminder(arguments: ToolArguments, idempotencyKey: String) async throws -> String { throw ShellError.denied("Evaluation never executes effects") }
    func findReminder(idempotencyKey: String) async throws -> String? { throw ShellError.denied("Evaluation has no accounts") }
    func undoReminder(externalID: String, idempotencyKey: String) async throws { throw ShellError.denied("Evaluation never executes effects") }
}
@MainActor final class EvaluationLink: ShellDeviceLink {
    var projections: [Data] = []
    func beginInteraction() throws {}
    func project(_ payload: Data) throws { projections.append(payload) }
    func blank() {}
    func captureAudio(requestID: UUID) throws { throw ShellError.unavailable("No microphone in evaluation") }
    func cancelCapture() {}
}
@MainActor final class EvaluationVoice: ShellVoiceOutput { func speak(_ text: String) {}; func stop() {} }

@main struct Evaluate {
    @MainActor static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        func value(_ flag: String) -> String? { guard let i = args.firstIndex(of:flag), i+1 < args.count else { return nil }; return args[i+1] }
        guard let referencesPath = value("--references"), let outputPath = value("--output") else {
            print("PrismShellEvaluate --references semantic-evaluations.json --output NEW_DIRECTORY [--live MODEL --allow-provider-cost]")
            return
        }
        let liveModel = value("--live")
        let key = ProcessInfo.processInfo.environment["PRISM_EVAL_API_KEY"] ?? ""
        if liveModel != nil && (!args.contains("--allow-provider-cost") || key.isEmpty) {
            throw ShellError.denied("Live capture requires explicit --allow-provider-cost and PRISM_EVAL_API_KEY; no request sent")
        }
        let output = URL(fileURLWithPath:outputPath,isDirectory:true)
        guard !FileManager.default.fileExists(atPath:output.path) else { throw ShellError.invalid("Use a new output directory to preserve prior evidence") }
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let references = try ShellJSON.decoder().decode([Reference].self,from:Data(contentsOf:URL(fileURLWithPath:referencesPath)))
        let time = Date(timeIntervalSince1970:1800000000) // Same fictional clock as reference tests.
        var rows: [[String:Any]] = []
        for (index,reference) in references.enumerated() {
            guard !reference.id.isEmpty, reference.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw ShellError.invalid("Invalid scenario identifier") }
            let directory = output.appendingPathComponent(String(format:"%02d",index) + "-" + reference.id)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            var archive = ShellArchive(); archive.session.startedAt = time; archive.privacy.cloudProcessing = true
            archive.privacy.calendarEnabled = true; archive.privacy.agentEnabled = true
            if let note = reference.context.note { archive.artifacts.append(.init(sessionID:archive.session.id,kind:.note,title:"Naming test",body:note,provenance:.init(source:"fictional evaluation",createdAt:time))) }
            if let prior = reference.context.recentAnswer { archive.conversations.append(.init(id:UUID(),sessionID:archive.session.id,userText:"What are the risks?",turn:.init(canonicalAnswer:prior),provenance:.init(source:"fictional evaluation",createdAt:time),status:"completed")) }
            let repository = FileShellRepository(url:directory.appendingPathComponent("library.json")); try repository.save(archive)
            var snapshot = ContextSnapshot(observedAt:time); snapshot.calendar = reference.context.calendar ?? []; snapshot.agentExceptions = reference.context.agents ?? []
            if reference.context.calendarUnavailable == true { snapshot.unavailableSources = ["calendar"] }
            let transport = try CaptureHTTP(reference:liveModel == nil ? reference : nil)
            let model = ResponsesExperienceModel(model:liveModel ?? "reference-replay",apiKey:{ liveModel == nil ? "fixture" : key },transport:transport)
            let engine = try AssistantOrchestrator(repository:repository,model:model,native:EvaluationOS(snapshot),link:EvaluationLink(),voice:EvaluationVoice(),now:{time})
            engine.submit(reference.prompt); await engine.waitForCurrentTurn()
            try ShellJSON.encoder().encode(reference).write(to:directory.appendingPathComponent("reference.json"))
            if let turn = engine.currentRecord?.turn { try ShellJSON.encoder().encode(ExperiencePlan(turn:turn)).write(to:directory.appendingPathComponent("actual-plan.json")) }
            for (i,body) in await transport.captured().enumerated() { try body.write(to:directory.appendingPathComponent("request-\(i).json")) }
            let dimensions = ["grounding","context interpretation","complete answer","independent speech","glanceable complement","tool arguments and clarification","confirmation policy","expiry and quiet behavior"]
            rows.append(["id":reference.id,"structuralAccepted":engine.currentRecord?.turn != nil,"error":engine.lastError as Any? ?? NSNull(),"semanticScores":Dictionary(uniqueKeysWithValues:dimensions.map { ($0,NSNull()) }),"reviewer":"","reasoning":""])
        }
        try JSONSerialization.data(withJSONObject:["evidenceClass":liveModel == nil ? "offline-reference-replay" : "live-model-capture-unscored","model":liveModel ?? "reference-replay","cases":rows],options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("review.json"))
        print("Captured \(rows.count) complete cases. Semantic scores remain unassigned; review by meaning, never token matching. No actions were executed.")
    }
}
