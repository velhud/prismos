import XCTest
@testable import PrismShell
import PrismAI
import PrismDraw
import PrismProtocol
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor ReplayHTTP: ShellHTTPTransport {
    var responses: [Data]
    var requests: [Data] = []
    var delay: UInt64
    init(_ plans: [ExperiencePlan], delay: UInt64 = 0) throws {
        self.responses = try plans.map { plan in
            let text = String(decoding: try ShellJSON.encoder().encode(plan), as: UTF8.self)
            return try JSONSerialization.data(withJSONObject: ["status":"completed","output":[["type":"message","content":[["type":"output_text","text":text]]]]])
        }; self.delay = delay
    }
    init(raw: [Data]) { responses = raw; delay = 0 }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request.httpBody ?? Data())
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) } // deliberately late external transport
        guard !responses.isEmpty else { throw ShellError.unavailable("Replay exhausted") }
        return (responses.removeFirst(),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
    }
    func inputs() throws -> [ModelRequest] {
        try requests.map { data in
            let body = try JSONSerialization.jsonObject(with:data) as! [String:Any]
            let input = body["input"] as! [[String:String]]
            return try ShellJSON.decoder().decode(ModelRequest.self,from:Data(input[0]["content"]!.utf8))
        }
    }
    func prepend(_ data: Data) { responses.insert(data,at:0) }
    func count() -> Int { requests.count }
    func bodies() -> [Data] { requests }
}
@MainActor final class NativeBoundaryDouble: NativeToolBoundary {
    var snapshot: ContextSnapshot
    var effects: [String:String] = [:]
    var creates = 0
    var deletes = 0
    var failAfterCreate = false
    var failAfterUndo = false
    var beforeUndoReturn: (() -> Void)?
    var beforeFindReturn: (() -> Void)?
    init(time: Date) { snapshot = ContextSnapshot(observedAt: time) }
    func context(privacy: PrivacySettings, now: Date) async -> ContextSnapshot { snapshot }
    func createReminder(arguments: ToolArguments, idempotencyKey: String) async throws -> String {
        if let id = effects[idempotencyKey] { return id }
        creates += 1; let id = UUID().uuidString; effects[idempotencyKey] = id
        if failAfterCreate { throw ShellError.uncertain }; return id
    }
    func findReminder(idempotencyKey: String) async throws -> String? { beforeFindReturn?(); return effects[idempotencyKey] }
    func undoReminder(externalID: String, idempotencyKey: String) async throws { deletes += 1; effects.removeValue(forKey:idempotencyKey); beforeUndoReturn?(); if failAfterUndo { throw ShellError.uncertain } }
}
@MainActor final class FrameLinkDouble: ShellDeviceLink {
    var payloads: [Data] = []
    var requestID: UUID?
    var cancels = 0
    func blank() { payloads.append(Data([1,0,5,0]) + Data("prism".utf8)) }
    func beginInteraction() throws {}
    func project(_ payload: Data) throws {
        var queue = DeviceWriteQueue(); try queue.enqueue(kind:.draw,payload:payload,maxWriteLength:20)
        let receiver = PrismFrameReassembler(); var complete: PrismCompleteMessage?
        while let frame = queue.take(canSend:true,withResponse:false) { if let message = try receiver.ingest(frame,now:0) { complete = message } }
        guard let complete else { throw ShellError.invalid("Incomplete link") }
        payloads.append(complete.payload)
    }
    func captureAudio(requestID: UUID) throws { self.requestID = requestID }
    func cancelCapture() { cancels += 1; requestID = nil }
}
@MainActor final class VoiceBoundaryDouble: ShellVoiceOutput {
    var spoken: [String] = []
    var stopped = 0
    func speak(_ text: String) { spoken.append(text) }
    func stop() { stopped += 1 }
}
struct TranscriptionBoundaryDouble: SpeechClient {
    var text: String
    func transcribe(_ audio: TranscriptionInput) async throws -> TranscriptionResult {
        XCTAssertEqual(audio.sampleRate,8000); XCTAssertEqual(audio.pcm16MonoLittleEndian.count, 8)
        return .init(requestID:audio.requestID,text:text)
    }
}

final class JourneyTests: XCTestCase {
    let time = Date(timeIntervalSince1970:1800000000)
    @MainActor func make(_ transport: ReplayHTTP, initial: ShellArchive? = nil) throws -> (AssistantOrchestrator, FileShellRepository, NativeBoundaryDouble, FrameLinkDouble, VoiceBoundaryDouble) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:folder) }
        let repo = FileShellRepository(url:folder.appendingPathComponent("library.json"))
        if let initial { try repo.save(initial) }
        let native = NativeBoundaryDouble(time:time); let link = FrameLinkDouble(); let voice = VoiceBoundaryDouble()
        let engine = try AssistantOrchestrator(repository:repo,model:ResponsesExperienceModel(model:"fixture-model",apiKey:{"fixture-key"},transport:transport),native:native,link:link,voice:voice,now:{self.time})
        var privacy = engine.archive.privacy; privacy.cloudProcessing = true; try engine.updatePrivacy(privacy)
        engine.setConnection(true)
        return (engine,repo,native,link,voice)
    }
    func plan(_ answer: String, actions: [ProposedAction] = [], project: String? = nil) -> ExperiencePlan {
        .init(turn:.init(canonicalAnswer:answer,spokenResponse:"A separate complete spoken explanation.",lensScene:.init(kind:.fact,title:"KEY FACT",body:"42"),proposedActions:actions,project:project))
    }
    @MainActor func testConversationalChoiceContinuesRealContextWithoutAnExternalEffect() async throws {
        let choice = ProposedAction(id:"detail", tool:.continueConversation, summary:"Explain the tradeoff", arguments:.init(query:"Explain the battery tradeoff in detail."))
        let http = try ReplayHTTP([plan("Choose a direction",actions:[choice]),plan("The complete tradeoff explanation")])
        let (engine,repo,native,_,_) = try make(http)
        engine.submit("Help me choose"); await engine.waitForCurrentTurn()
        try await engine.confirm(actionID:"detail",revision:engine.archive.revision)
        await engine.waitForCurrentTurn()
        XCTAssertEqual(engine.currentRecord?.turn?.canonicalAnswer,"The complete tradeoff explanation")
        let requests = try await http.inputs()
        XCTAssertEqual(requests.last?.input,choice.arguments.query)
        XCTAssertTrue(requests.last?.context.recentTurns.contains { $0.userText == "Help me choose" } == true)
        XCTAssertEqual(try repo.load().receipts.last?.action.tool,.continueConversation)
        XCTAssertNil(engine.lastReceipt?.undoToken); XCTAssertEqual(native.creates,0)
    }
    @MainActor func testBlankDuringNativeUndoAndReconciliationNeverResurrectsSurface() async throws {
        let action = ProposedAction(id:"r",tool:.createReminder,summary:"Reminder",arguments:.init(title:"Review",dueAt:time.addingTimeInterval(300)))
        let (engine,_,native,_,_) = try make(try ReplayHTTP([plan("Confirm",actions:[action])]))
        engine.submit("Remind me"); await engine.waitForCurrentTurn()
        try await engine.confirm(actionID:"r",revision:engine.archive.revision)
        let key = try XCTUnwrap(engine.lastReceipt?.id)
        native.failAfterUndo = true; native.beforeUndoReturn = { engine.clear() }
        try await engine.undo(receiptID:key)
        XCTAssertEqual(engine.scene.kind,.blank); XCTAssertEqual(engine.lastReceipt?.status,.undoUncertain)
        native.beforeFindReturn = { engine.clear() }
        try await engine.reconcile(receiptID:key)
        XCTAssertEqual(engine.scene.kind,.blank); XCTAssertEqual(engine.lastReceipt?.status,.undone)
        XCTAssertEqual(native.deletes,1)
    }
    @MainActor func testProactiveFailedEvaluationRetriesAfterCooldownThenStaysQuiet() async throws {
        let candidate = "calendar:event:1800000300:1800000300"
        let decision = ExperiencePlan(turn:.init(canonicalAnswer:"The event is unrelated to the current focus.",proactiveDecision:.init(candidateID:candidate,disposition:.suppress,reason:"No useful contextual interruption")))
        let http = try ReplayHTTP([plan("Missing proactive decision"),decision])
        let (engine,_,native,_,_) = try make(http)
        var clock = time; engine.now = { clock }
        var privacy = engine.archive.privacy; privacy.calendarEnabled = true; privacy.proactiveEnabled = true; try engine.updatePrivacy(privacy)
        native.snapshot.calendar = [.init(id:"event",title:"A real event",start:time.addingTimeInterval(300),end:time.addingTimeInterval(600))]
        await engine.refreshContext(); await engine.considerProactivity()
        XCTAssertEqual(engine.archive.candidateHistory[candidate]?.state,.evaluated)
        await engine.considerProactivity(); let firstCount = await http.count(); XCTAssertEqual(firstCount,1)
        clock = time.addingTimeInterval(61); await engine.considerProactivity()
        XCTAssertEqual(engine.archive.candidateHistory[candidate]?.state,.suppressed)
        await engine.considerProactivity(); let finalCount = await http.count(); XCTAssertEqual(finalCount,2)
        XCTAssertEqual(engine.scene.kind,.blank)
    }
    @MainActor func testFiveTurnsPreserveLongTruthAcrossActualModelAdapterRendererLinkAndRestart() async throws {
        let full = String(repeating:"The detailed analysis includes context and all conclusions. ",count:1000) + "END OF COMPLETE ANSWER"
        let http = try ReplayHTTP((0..<5).map { plan("Turn \($0). " + full,project:"Unknown project Ω") })
        let (engine,repo,_,link,voice) = try make(http)
        for i in 0..<5 { engine.submit("Question \(i)"); await engine.waitForCurrentTurn() }
        XCTAssertNil(engine.lastError); XCTAssertEqual(engine.archive.conversations.count,5)
        XCTAssertTrue(engine.archive.conversations.allSatisfy { $0.turn?.canonicalAnswer.hasSuffix("END OF COMPLETE ANSWER") == true })
        XCTAssertEqual(voice.spoken.count,5); XCTAssertFalse(voice.spoken[0].contains("Turn 0"))
        XCTAssertFalse(link.payloads.isEmpty)
        let requests = try await http.inputs()
        XCTAssertEqual(requests.count,5)
        XCTAssertTrue(requests[1].context.recentTurns.contains { $0.turn?.canonicalAnswer == "Turn 0. " + full })
        XCTAssertEqual(requests[4].context.session.project,"Unknown project Ω")
        let restored = try repo.load()
        XCTAssertEqual(restored.conversations,engine.archive.conversations)
        XCTAssertEqual(restored.search("END OF COMPLETE ANSWER").count,5)
        // The actual request uses strict semantic output and read-only functions, never generated coordinates.
        let body = try JSONSerialization.jsonObject(with:await http.bodies()[0]) as! [String:Any]
        XCTAssertEqual(body["store"] as? Bool,false)
        XCTAssertEqual(((body["text"] as! [String:Any])["format"] as! [String:Any])["type"] as? String,"json_schema")
    }
    @MainActor func testNoteReceiptDuplicateConfirmationUndoAndProjectAssociation() async throws {
        let complete = String(repeating:"A precise naming decision. ",count:200)
        let action = ProposedAction(id:"save",tool:.saveNote,summary:"Save naming decision",arguments:.init(title:"Naming decision",body:complete,project:"Project without a dictionary",topic:"Brand"))
        let (engine,repo,_,_,_) = try make(try ReplayHTTP([plan("I can save this note.",actions:[action])]))
        engine.submit("Remember this"); await engine.waitForCurrentTurn()
        XCTAssertEqual(engine.archive.artifacts.filter { $0.provenance.source == "confirmed note" }.count,0)
        let revision = engine.archive.revision
        try await engine.confirm(actionID:"save",revision:revision)
        XCTAssertEqual(engine.archive.receipts.count,1)
        let note = try XCTUnwrap(engine.archive.search("precise").first)
        XCTAssertEqual(note.body,complete); XCTAssertEqual(note.project,"Project without a dictionary")
        do { try await engine.confirm(actionID:"save",revision:revision); XCTFail("Stale confirmation") } catch {}
        XCTAssertEqual(engine.archive.receipts.count,1)
        let receipt = try XCTUnwrap(engine.lastReceipt)
        try await engine.undo(receiptID:receipt.id)
        XCTAssertFalse(try repo.load().artifacts.contains { $0.id == note.id })
        XCTAssertEqual(engine.lastReceipt?.status,.undone)
    }
    @MainActor func testReminderUncertainCommitReconcilesAndUndoesWithoutDuplicateEffect() async throws {
        let action = ProposedAction(id:"remind",tool:.createReminder,summary:"Tomorrow appointment",arguments:.init(title:"Call the clinic",dueAt:time.addingTimeInterval(86400)))
        let (engine,repo,native,_,_) = try make(try ReplayHTTP([plan("Confirm reminder",actions:[action])]))
        native.failAfterCreate = true
        engine.submit("Remind me tomorrow at ten"); await engine.waitForCurrentTurn()
        try await engine.confirm(actionID:"remind",revision:engine.archive.revision)
        XCTAssertEqual(native.creates,1); XCTAssertEqual(engine.lastReceipt?.status,.uncertain)
        let key = try XCTUnwrap(engine.lastReceipt?.id)
        XCTAssertEqual(try repo.load().receipts.last?.id,key)
        try await engine.reconcile(receiptID:key)
        XCTAssertEqual(engine.lastReceipt?.status,.succeeded); XCTAssertEqual(native.creates,1)
        try await engine.undo(receiptID:key)
        XCTAssertEqual(native.deletes,1); XCTAssertEqual(engine.lastReceipt?.status,.undone)
    }
    @MainActor func testMonocleAudioTranscriptFollowUpAndCancelledReplay() async throws {
        let transcript = String(repeating:"A complete thought to retain. ",count:100)
        let (engine,_,_,link,voice) = try make(try ReplayHTTP([plan("Full thought understood")]))
        engine.beginListening(); let id = try XCTUnwrap(link.requestID)
        XCTAssertEqual(engine.phase,"Listening")
        engine.receiveAudio(Data([0,127,128,255]),requestID:id,speech:TranscriptionBoundaryDouble(text:transcript))
        await engine.waitForCurrentTurn()
        XCTAssertEqual(engine.archive.conversations.first?.userText,transcript)
        XCTAssertEqual(engine.archive.artifacts.first { $0.kind == .transcript }?.body,transcript)
        XCTAssertNil(engine.archive.artifacts.first { $0.kind == .transcript }?.rawMedia)
        XCTAssertEqual(voice.spoken.count,1)
        engine.beginListening(); let stale = try XCTUnwrap(link.requestID); engine.clear()
        engine.receiveAudio(Data([0,127,128,255]),requestID:stale,speech:TranscriptionBoundaryDouble(text:"late"))
        XCTAssertEqual(engine.scene,.blank); XCTAssertEqual(engine.archive.conversations.count,1)
    }
    @MainActor func testLateModelResultCannotResurrectCancelledScene() async throws {
        let http = try ReplayHTTP([plan("Late answer")],delay:50_000_000)
        let (engine,_,_,_,voice) = try make(http)
        engine.submit("Explain")
        let wait = Task { await engine.waitForCurrentTurn() }
        while await http.count() == 0 { await Task.yield() }
        engine.clear(); await wait.value
        XCTAssertEqual(engine.scene,.blank); XCTAssertNil(engine.currentTurnID); XCTAssertTrue(voice.spoken.isEmpty)
        XCTAssertTrue(engine.archive.conversations.allSatisfy { $0.turn == nil })
    }
    @MainActor func testCalendarAIInterpretsThenDismissSnoozeExpireAndSourceDisappears() async throws {
        var snapshot = ContextSnapshot(observedAt:time)
        snapshot.calendar = [.init(id:"event",title:"Technical review",start:time.addingTimeInterval(900),end:time.addingTimeInterval(1800))]
        let c = CalendarProactiveSource().candidates(snapshot:snapshot,now:time)[0]
        let turn = AssistantTurn(canonicalAnswer:"Your review is soon; the active build has an unresolved decision.",lensScene:.init(kind:.alert,title:"BUILD REVIEW",body:"Bring the unresolved decision",expiresInSeconds:60),proactiveDecision:.init(candidateID:c.id,disposition:.show,reason:"The upcoming review concerns the current build decision"))
        let http = try ReplayHTTP([.init(turn:turn),.init(turn:turn)])
        let (engine,repo,native,_,voice) = try make(http)
        native.snapshot = snapshot
        var p = engine.archive.privacy; p.calendarEnabled = true; p.proactiveEnabled = true; try engine.updatePrivacy(p)
        await engine.refreshContext(); await engine.considerProactivity()
        XCTAssertEqual(engine.activeCandidate?.id,c.id); XCTAssertTrue(voice.spoken.isEmpty)
        try engine.dismissCandidate(snoozeSeconds:300)
        await engine.considerProactivity(); let countBefore = await http.count(); XCTAssertEqual(countBefore,1)
        let later = time.addingTimeInterval(301); engine.now = { later }; native.snapshot.observedAt = later
        await engine.refreshContext(); await engine.considerProactivity()
        XCTAssertEqual(engine.activeCandidate?.id,c.id)
        native.snapshot.calendar = []; await engine.refreshContext()
        XCTAssertNil(engine.activeCandidate); XCTAssertEqual(engine.scene,.blank)
        XCTAssertEqual(try repo.load().candidateHistory[c.id]?.state,.shown)
        await engine.considerProactivity(); let countAfter = await http.count(); XCTAssertEqual(countAfter,2)
    }
    @MainActor func testPrivacyAndStaleWatchCommandsNeverCauseEffects() async throws {
        let http = try ReplayHTTP([plan("Private")])
        let (engine,_,native,_,_) = try make(http)
        let command = ShellWatchCommand(snapshotVersion:engine.archive.revision - 1,sessionID:engine.archive.session.id,createdAt:time,kind:.ask)
        do { try await engine.processWatch(command); XCTFail("stale watch") } catch {}
        XCTAssertEqual(native.creates,0)
        var p = engine.archive.privacy; p.cloudProcessing = false; p.privateMode = true; try engine.updatePrivacy(p)
        engine.submit("Do not send"); await engine.waitForCurrentTurn()
        let count = await http.count(); XCTAssertEqual(count,0)
        XCTAssertEqual(engine.watchSnapshot.scene,.blank); XCTAssertTrue(engine.watchSnapshot.actionIDs.isEmpty)
    }
    @MainActor func testReadFunctionsUseRealLibraryOwnerAndReturnFullToolResults() async throws {
        let note = String(repeating:"Full scientific finding. ",count:200)
        let raw = try JSONSerialization.data(withJSONObject:["status":"completed","output":[["type":"function_call","name":"retrieve_notes","call_id":"read1","arguments":"{\"query\":\"scientific\"}"]]])
        let response = try ReplayHTTP([plan("The complete prior finding is available")])
        let final = await response.responses[0]
        let http = ReplayHTTP(raw:[raw,final])
        let (engine,repo,_,_,_) = try make(http)
        var data = engine.archive
        data.artifacts.append(.init(sessionID:data.session.id,kind:.note,title:"Finding",body:note,provenance:.init(source:"fixture import",createdAt:time)))
        try repo.save(data)
        // Restart the actual owner from its durable file; do not replace its retrieval internals.
        let native = NativeBoundaryDouble(time:time)
        let restarted = try AssistantOrchestrator(repository:repo,model:ResponsesExperienceModel(model:"fixture-model",apiKey:{"fixture"},transport:http),native:native,link:FrameLinkDouble(),voice:VoiceBoundaryDouble(),now:{self.time})
        restarted.submit("What did I conclude?"); await restarted.waitForCurrentTurn()
        let inputs = try await http.inputs()
        XCTAssertEqual(inputs.count,2); XCTAssertTrue(inputs[1].toolResults[0].content.contains(note))
        XCTAssertEqual(restarted.currentRecord?.turn?.canonicalAnswer,"The complete prior finding is available")
    }
}

extension JourneyTests {
    @MainActor func testTwentySemanticReferencesThroughActualSchemaAndOrchestration() async throws {
        struct Reference: Decodable {
            struct Context: Decodable {
                var calendar: [CalendarItem]?; var agents: [AgentException]?; var calendarUnavailable: Bool?
                var note: String?; var searchQuery: String?; var recentAnswer: String?
            }
            var id: String; var prompt: String; var referencePlan: ExperiencePlan; var expectedReadTools: [ToolName]; var rubric: String; var context: Context
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"semantic-evaluations",withExtension:"json",subdirectory:"Fixtures"))
        let references = try ShellJSON.decoder().decode([Reference].self,from:Data(contentsOf:url))
        XCTAssertEqual(references.count,20)
        for reference in references {
            try reference.referencePlan.validate(now:time)
            let http = try ReplayHTTP([reference.referencePlan])
            var initial = ShellArchive(); initial.privacy.calendarEnabled = true; initial.privacy.agentEnabled = true
            if let note = reference.context.note {
                initial.artifacts.append(.init(sessionID: initial.session.id,kind:.note,title:"Naming test",body:note,provenance:.init(source:"fixture source",createdAt:time)))
            }
            if let prior = reference.context.recentAnswer {
                initial.conversations.append(.init(id:UUID(),sessionID:initial.session.id,userText:"What are the risks?",turn:.init(canonicalAnswer:prior),provenance:.init(source:"fixture source",createdAt:time),status:"completed"))
            }
            if !reference.expectedReadTools.isEmpty {
                let calls: [[String:Any]] = reference.expectedReadTools.enumerated().map { index, name in
                    let args = name == .retrieveNotes ? "{\"query\":\"\(reference.context.searchQuery ?? "naming")\"}" : "{}"
                    return ["type":"function_call","name":name.rawValue,"call_id":"read-\(index)","arguments":args]
                }
                await http.prepend(try JSONSerialization.data(withJSONObject:["status":"completed","output":calls]))
            }
            let (engine,repo,native,_,voice) = try make(http,initial:initial)
            native.snapshot.calendar = reference.context.calendar ?? []; native.snapshot.agentExceptions = reference.context.agents ?? []
            if reference.context.calendarUnavailable == true { native.snapshot.unavailableSources = ["calendar"] }
            engine.submit(reference.prompt); await engine.waitForCurrentTurn()
            let requests = try await http.inputs()
            XCTAssertEqual(requests.last?.toolResults.map(\.tool),reference.expectedReadTools,reference.id)
            if let prior = reference.context.recentAnswer { XCTAssertEqual(requests.first?.context.recentTurns.first?.turn?.canonicalAnswer,prior) }
            XCTAssertNil(engine.lastError,reference.id)
            XCTAssertEqual(engine.currentRecord?.turn,reference.referencePlan.turn,reference.id)
            XCTAssertEqual(try repo.load().conversations.last?.turn?.canonicalAnswer,reference.referencePlan.turn.canonicalAnswer,reference.id)
            XCTAssertEqual(voice.spoken,reference.referencePlan.turn.spokenResponse.map { [$0] } ?? [],reference.id)
            XCTAssertTrue(engine.archive.receipts.isEmpty,"Reference effects must await confirmation: " + reference.id)
            for page in PrismSceneRenderer.pages(reference.referencePlan.turn.lensScene,now:time) { XCTAssertNoThrow(try PrismDrawPacker.pack(page),reference.id) }
        }
        // This is reference replay and contract evidence, not a live model semantic score.
    }
}

extension JourneyTests {
    @MainActor func testFocusTimerConfirmationExpiryAndUndoAreHostOwned() async throws {
        let action = ProposedAction(id:"focus",tool:.startTimer,summary:"Start focus",arguments:.init(title:"Editing",seconds:60))
        let (engine,repo,_,_,_) = try make(try ReplayHTTP([plan("Confirm focus",actions:[action])]))
        engine.submit("Start editing timer"); await engine.waitForCurrentTurn()
        try await engine.reviewOrConfirm(actionID:"focus")
        XCTAssertNil(engine.archive.timer)
        XCTAssertTrue(engine.viewport.primitives.contains { if case .text("R CONFIRM  L CANCEL",_,_,_,_) = $0 { return true }; return false })
        try await engine.reviewOrConfirm(actionID:"focus")
        XCTAssertEqual(engine.archive.timer?.title,"Editing")
        let later = time.addingTimeInterval(61); engine.now = { later }; engine.tick()
        XCTAssertEqual(try repo.load().timer?.completed,true)
        try await engine.undo(receiptID:try XCTUnwrap(engine.lastReceipt?.id))
        XCTAssertNil(engine.archive.timer)
    }
    @MainActor func testProactiveDismissalSurvivesRestartAndExpiryIsNotPinned() async throws {
        var snapshot = ContextSnapshot(observedAt:time)
        snapshot.calendar = [.init(id:"review",title:"Review",start:time.addingTimeInterval(900),end:time.addingTimeInterval(1800))]
        let candidate = CalendarProactiveSource().candidates(snapshot:snapshot,now:time)[0]
        let reference = ExperiencePlan(turn:.init(canonicalAnswer:"Review in fifteen minutes",lensScene:.init(kind:.alert,title:"REVIEW",body:"Upcoming review",expiresInSeconds:10),proactiveDecision:.init(candidateID:candidate.id,disposition:.show,reason:"Relevant to active session")))
        let http = try ReplayHTTP([reference])
        let (engine,repo,native,_,_) = try make(http); native.snapshot = snapshot
        var p = engine.archive.privacy; p.calendarEnabled = true; p.proactiveEnabled = true; try engine.updatePrivacy(p)
        await engine.refreshContext(); await engine.considerProactivity(); engine.togglePin()
        XCTAssertFalse(engine.pinned)
        let later = time.addingTimeInterval(11); engine.now = { later }; engine.tick()
        XCTAssertEqual(engine.scene,.blank)
        let restored = try AssistantOrchestrator(repository:repo,model:ResponsesExperienceModel(model:"fixture-model",apiKey:{"fixture"},transport:http),native:native,link:FrameLinkDouble(),voice:VoiceBoundaryDouble(),now:{self.time})
        await restored.refreshContext(); await restored.considerProactivity()
        let count = await http.count(); XCTAssertEqual(count,1)
        XCTAssertNil(restored.activeCandidate)
    }
    @MainActor func testRetentionScrubsActionPayloadsAndRawAudioWhileKeepingMinimalExternalLedger() async throws {
        let repo = FileShellRepository(url:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json"))
        let cleanup = repo.url.deletingLastPathComponent()
        addTeardownBlock { try? FileManager.default.removeItem(at:cleanup) }
        var archive = ShellArchive(); archive.privacy.retentionDays = 1
        let old = time.addingTimeInterval(-2*86400)
        archive.artifacts = [.init(sessionID:archive.session.id,kind:.transcript,title:"Old",body:"private transcript",provenance:.init(source:"microphone",createdAt:old),rawMedia:Data([1,2]))]
        let action = ProposedAction(id:"r",tool:.createReminder,summary:"private title",arguments:.init(title:"private title",body:"private notes",dueAt:time.addingTimeInterval(100)))
        var receipt = ActionReceipt(id:"key",requestID:UUID(),action:action,status:.succeeded,summary:"private summary",createdAt:old)
        receipt.externalID = "external-id"; receipt.undoToken = "key"; archive.receipts = [receipt]
        archive.prune(now:time); try repo.save(archive)
        let loaded = try repo.load(); XCTAssertTrue(loaded.artifacts.isEmpty)
        XCTAssertNil(loaded.receipts[0].action.arguments.body); XCTAssertNil(loaded.receipts[0].action.arguments.title)
        XCTAssertEqual(loaded.receipts[0].externalID,"external-id")
        XCTAssertEqual(loaded.receipts[0].summary,"Reminder receipt retained for undo and reconciliation")
        XCTAssertEqual(loaded.receipts[0].action.summary,"Reminder action")
    }
    @MainActor func testInterruptedExternalJournalRestoresAsUncertain() throws {
        let (engine,repo,native,link,voice) = try make(try ReplayHTTP([]))
        var archive = engine.archive
        let action = ProposedAction(id:"r",tool:.createReminder,summary:"Call",arguments:.init(title:"Call",dueAt:time.addingTimeInterval(100)))
        archive.receipts.append(.init(id:"key",requestID:UUID(),action:action,status:.executing,summary:"Creating",createdAt:time))
        try repo.save(archive)
        let restarted = try AssistantOrchestrator(repository:repo,model:engine.model,native:native,link:link,voice:voice,now:{self.time})
        XCTAssertEqual(restarted.lastReceipt?.status,.uncertain); XCTAssertEqual(native.creates,0)
    }
    @MainActor func testCorruptStoreIsPreservedAndDoesNotBecomeEmptySuccess() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url = folder.appendingPathComponent("library.json"); let corrupt = Data("{invalid".utf8); try corrupt.write(to:url)
        XCTAssertThrowsError(try FileShellRepository(url:url).load())
        XCTAssertEqual(try Data(contentsOf:url),corrupt)
    }
}

extension JourneyTests {
    @MainActor func testFailedJournalWritePreventsNativeEffect() async throws {
        let action = ProposedAction(id:"r",tool:.createReminder,summary:"Call",arguments:.init(title:"Call",dueAt:time.addingTimeInterval(60)))
        let (engine,repo,native,_,_) = try make(try ReplayHTTP([plan("Confirm",actions:[action])]))
        engine.submit("Remind me"); await engine.waitForCurrentTurn()
        try FileManager.default.removeItem(at:repo.url)
        try FileManager.default.createDirectory(at:repo.url,withIntermediateDirectories:true)
        do { try await engine.confirm(actionID:"r",revision:engine.archive.revision); XCTFail("Must not execute without journal") } catch {}
        XCTAssertEqual(native.creates,0); XCTAssertTrue(engine.archive.receipts.isEmpty)
    }
    @MainActor func testRefusedIncompleteAndMutatingFunctionResponsesCannotEnterState() async throws {
        let responses: [[String:Any]] = [
            ["status":"incomplete","output":[]],
            ["status":"completed","output":[["type":"message","content":[["type":"refusal","refusal":"Declined"]]]]],
            ["status":"completed","output":[["type":"function_call","name":"create_reminder","call_id":"bad","arguments":"{}"]]]
        ]
        for envelope in responses {
            let http = ReplayHTTP(raw:[try JSONSerialization.data(withJSONObject:envelope)])
            let (engine,_,native,_,_) = try make(http)
            engine.submit("Request"); await engine.waitForCurrentTurn()
            XCTAssertNotNil(engine.lastError); XCTAssertEqual(native.creates,0)
            XCTAssertNil(engine.currentRecord?.turn); XCTAssertTrue(engine.archive.receipts.isEmpty)
        }
    }
}

extension JourneyTests {
    @MainActor func testExpiredActionCannotBeRevivedByErrorSurface() async throws {
        let action = ProposedAction(id:"save",tool:.saveNote,summary:"Save",arguments:.init(title:"Note",body:"Complete note"))
        let (engine,_,_,_,_) = try make(try ReplayHTTP([plan("Confirm",actions:[action])]))
        engine.submit("Save"); await engine.waitForCurrentTurn()
        let later = time.addingTimeInterval(31); engine.now = { later }
        do { try await engine.confirm(actionID:"save",revision:engine.archive.revision); XCTFail("Expired") }
        catch { engine.showError(error) }
        XCTAssertTrue(engine.actions.isEmpty)
        do { try await engine.confirm(actionID:"save",revision:engine.archive.revision); XCTFail("Cannot revive") } catch {}
        XCTAssertTrue(engine.archive.receipts.isEmpty)
    }
}

extension JourneyTests {
    @MainActor func testComposedSessionAndTimerRetainEveryPendingActionAcrossReceipts() async throws {
        let session = ProposedAction(id:"session",tool:.setSession,summary:"Focus on Cedar",arguments:.init(project:"Cedar",sessionKind:.focus))
        let timer = ProposedAction(id:"timer",tool:.startTimer,summary:"Start editing timer",arguments:.init(title:"Editing",seconds:1500))
        let turn = AssistantTurn(canonicalAnswer:"Confirm both changes",lensScene:.init(kind:.choice,title:"FOCUS SETUP",items:[.init("Session","Cedar",actionID:"session"),.init("Timer","25 minutes",actionID:"timer")]),proposedActions:[session,timer])
        let (engine,repo,_,_,_) = try make(try ReplayHTTP([.init(turn:turn)]))
        engine.submit("Focus on Cedar for twenty-five minutes"); await engine.waitForCurrentTurn()
        XCTAssertEqual(engine.selectedAction?.id,"session")
        engine.nextChoice(); XCTAssertEqual(engine.selectedAction?.id,"timer")
        engine.nextChoice(); XCTAssertEqual(engine.selectedAction?.id,"session")
        try await engine.confirm(actionID:"session",revision:engine.archive.revision)
        XCTAssertEqual(engine.actions.map(\.id),["timer"])
        XCTAssertEqual(engine.archive.session.kind,.focus); XCTAssertEqual(engine.archive.session.project,"Cedar")
        try await engine.confirm(actionID:"timer",revision:engine.archive.revision)
        XCTAssertTrue(engine.actions.isEmpty); XCTAssertEqual(engine.archive.receipts.count,2)
        XCTAssertEqual(try repo.load().timer?.title,"Editing")
        XCTAssertFalse(engine.viewport.primitives.contains { if case .text("R CONFIRM  L CANCEL",_,_,_,_) = $0 { return true }; return false })
    }
}

extension JourneyTests {
    @MainActor func testLeftCancelsCurrentReviewWithoutUndoingAnEarlierReceipt() async throws {
        let first = ProposedAction(id:"one",tool:.saveNote,summary:"Save first",arguments:.init(title:"One",body:"Original note"))
        let second = ProposedAction(id:"two",tool:.saveNote,summary:"Save second",arguments:.init(title:"Two",body:"Second note"))
        let (engine,_,_,_,_) = try make(try ReplayHTTP([plan("Two separate notes",actions:[first,second])]))
        engine.submit("Save two notes"); await engine.waitForCurrentTurn()
        try await engine.confirm(actionID:"one",revision:engine.archive.revision)
        try await engine.handleGesture(side:"R",gesture:"TAP")
        XCTAssertTrue(engine.isReviewingAction)
        try await engine.handleGesture(side:"L",gesture:"TAP")
        XCTAssertFalse(engine.isReviewingAction)
        XCTAssertEqual(engine.lastReceipt?.status,.succeeded)
        XCTAssertEqual(engine.archive.search("Original note").filter { $0.kind == .note }.count,1)
        XCTAssertEqual(engine.actions.map(\.id),["two"])
    }
    @MainActor func testExpiredReviewAndChoiceDoNotExtendActionAuthority() async throws {
        let action = ProposedAction(id:"note",tool:.saveNote,summary:"Save",arguments:.init(title:"Note",body:"Text"))
        let (engine,_,_,_,_) = try make(try ReplayHTTP([plan("Confirm",actions:[action])]))
        engine.submit("Save"); await engine.waitForCurrentTurn()
        let expiry = engine.expiresAt
        let later = time.addingTimeInterval(31); engine.now = { later }
        engine.nextChoice(); XCTAssertEqual(engine.expiresAt,expiry)
        do { try await engine.reviewOrConfirm(actionID:"note"); XCTFail("Expired review must fail") } catch {}
        XCTAssertTrue(engine.archive.receipts.isEmpty)
    }
    @MainActor func testOldSessionAndTimerUndoCannotOverwriteLaterState() async throws {
        let session1 = ProposedAction(id:"a",tool:.setSession,summary:"Focus",arguments:.init(project:"A",sessionKind:.focus))
        let session2 = ProposedAction(id:"b",tool:.setSession,summary:"Walk",arguments:.init(project:"B",sessionKind:.walk))
        let timer = ProposedAction(id:"c",tool:.startTimer,summary:"Start",arguments:.init(title:"Focus",seconds:60))
        let stop = ProposedAction(id:"d",tool:.stopTimer,summary:"Stop",arguments:.init())
        let (engine,_,_,_,_) = try make(try ReplayHTTP([plan("Confirm",actions:[session1,session2,timer,stop])]))
        engine.submit("Prepare actions"); await engine.waitForCurrentTurn()
        try await engine.confirm(actionID:"a",revision:engine.archive.revision); let firstSession = try XCTUnwrap(engine.lastReceipt?.id)
        try await engine.confirm(actionID:"b",revision:engine.archive.revision)
        do { try await engine.undo(receiptID:firstSession); XCTFail("Cannot overwrite later session") } catch {}
        XCTAssertEqual(engine.archive.session.project,"B")
        try await engine.confirm(actionID:"c",revision:engine.archive.revision); let firstTimer = try XCTUnwrap(engine.lastReceipt?.id)
        try await engine.confirm(actionID:"d",revision:engine.archive.revision)
        do { try await engine.undo(receiptID:firstTimer); XCTFail("Cannot undo across newer stop") } catch {}
        XCTAssertNil(engine.archive.timer)
    }
    @MainActor func testUncertainUndoIsJournaledRestoredAndReconciledWithoutRepeatingDeletion() async throws {
        let action = ProposedAction(id:"remind",tool:.createReminder,summary:"Call",arguments:.init(title:"Call",dueAt:time.addingTimeInterval(60)))
        let (engine,repo,native,link,voice) = try make(try ReplayHTTP([plan("Confirm",actions:[action])]))
        engine.submit("Remind"); await engine.waitForCurrentTurn(); try await engine.confirm(actionID:"remind",revision:engine.archive.revision)
        let id = try XCTUnwrap(engine.lastReceipt?.id); native.failAfterUndo = true
        try await engine.undo(receiptID:id)
        XCTAssertEqual(engine.lastReceipt?.status,.undoUncertain); XCTAssertEqual(native.deletes,1)
        let restored = try AssistantOrchestrator(repository:repo,model:engine.model,native:native,link:link,voice:voice,now:{self.time})
        XCTAssertEqual(restored.lastReceipt?.status,.undoUncertain)
        do { try await restored.undo(receiptID:id); XCTFail("Reconcile before retry") } catch {}
        try await restored.reconcile(receiptID:id)
        XCTAssertEqual(restored.lastReceipt?.status,.undone); XCTAssertEqual(native.deletes,1)
    }
}
