import XCTest
@testable import PrismShell
import PrismDraw

final class SceneTests: XCTestCase {
    func testEverySceneFitsAndPacksEveryPage() throws {
        let now = Date(timeIntervalSince1970: 1800000000)
        for kind in SceneKind.allCases {
            let items: [SceneItem] = [.init("Option A", String(repeating: "Complete information ", count: 40), actionID: "a"), .init("Option B", "Short", actionID: "b")]
            let scene = kind == .blank ? LensScene.blank : LensScene(kind: kind, title: "SITUATION", body: "A useful complement", items: items, progress: 0.4, timerEnd: now.addingTimeInterval(120))
            try scene.validate(actionIDs: ["a", "b"])
            for page in PrismSceneRenderer.pages(scene, now: now) {
                let bytes = try PrismDrawPacker.pack(page)
                XCTAssertLessThan(bytes.count, 1536)
                for primitive in page.primitives {
                    if case let .text(text,x,y,_,_) = primitive {
                        XCTAssertLessThanOrEqual(text.utf8.count,32); XCTAssertLessThanOrEqual(text.count,24)
                        XCTAssertGreaterThanOrEqual(x, 0); XCTAssertLessThanOrEqual(Int(x)+text.count*24,640)
                        XCTAssertLessThanOrEqual(Int(y)+48,400)
                    }
                }
            }
        }
    }
    func testWrapDoesNotDropLongWordsOrUnicode() {
        let text = String(repeating: "abcdefghij", count: 100)
        XCTAssertEqual(PrismSceneRenderer.wrap(text).joined(),text)
        let unicode = String(repeating: "日本語", count: 40)
        let rows = PrismSceneRenderer.wrap(unicode)
        XCTAssertEqual(rows.joined(),unicode); XCTAssertTrue(rows.allSatisfy { $0.utf8.count <= 32 })
    }
}

final class ContractTests: XCTestCase {
    let time = Date(timeIntervalSince1970: 1800000000)
    func testSchemaRejectsUnknownFieldsMalformedAndUnsafeActions() throws {
        let good = ExperiencePlan(turn: .init(canonicalAnswer: "Complete answer", spokenResponse: "Spoken explanation", lensScene: .init(kind: .fact, title: "Fact", body: "42")))
        let data = try ShellJSON.encoder().encode(good)
        XCTAssertEqual(try ExperienceSchema.decode(data, now: time), good)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var turn = try XCTUnwrap(json["turn"] as? [String: Any]); var scene = try XCTUnwrap(turn["lensScene"] as? [String: Any])
        scene["x"] = 123; turn["lensScene"] = scene; json["turn"] = turn
        XCTAssertThrowsError(try ExperienceSchema.decode(JSONSerialization.data(withJSONObject: json), now: time))
        XCTAssertThrowsError(try ExperienceSchema.decode(Data("{truncated".utf8), now: time))
        let unsafe = ProposedAction(id: "x", tool: .createReminder, summary: "Later", arguments: .init(title: "Call", dueAt: time.addingTimeInterval(-1)))
        XCTAssertThrowsError(try unsafe.validate(now: time))
        let ambiguous = AssistantTurn(canonicalAnswer: "Which time?", proposedActions: [.init(id: "a", tool: .startTimer, summary: "Start", arguments: .init(title: "Focus", seconds: 30))], clarification: "Which time?")
        XCTAssertThrowsError(try ambiguous.validate(now: time))
    }
    func testQueueBackpressureCoalescingEpochAndFragmentBounds() throws {
        var queue = DeviceWriteQueue()
        let first = try queue.enqueue(kind: .draw, payload: Data(repeating: 1, count: 200), maxWriteLength: 20)
        let epoch = queue.epoch
        XCTAssertNotNil(queue.take(canSend: true, withResponse: true))
        XCTAssertNil(queue.take(canSend: true, withResponse: true))
        _ = try queue.enqueue(kind: .draw, payload: Data([2]), maxWriteLength: 20)
        _ = try queue.enqueue(kind: .draw, payload: Data([3]), maxWriteLength: 20)
        XCTAssertEqual(queue.messages.count, 2); XCTAssertEqual(queue.messages[0].id, first)
        queue.acknowledge(epoch: epoch)
        var count = 0
        while let frame = queue.take(canSend: true, withResponse: false) { XCTAssertLessThanOrEqual(frame.count,20); count += 1 }
        XCTAssertGreaterThan(count, 20)
        queue.reset(); queue.acknowledge(epoch: epoch); XCTAssertFalse(queue.awaitingResponse)
        XCTAssertNil(queue.take(canSend: false, withResponse: false))
    }
    func testAudioCancelReplayAndStaleDeadline() throws {
        var gate = AudioCaptureGate(); let id = UUID()
        gate.begin(id: id, now: time)
        XCTAssertThrowsError(try gate.started(id: UUID(), stream: 3, now: time))
        try gate.started(id: id, stream: 3, now: time)
        gate.cancel()
        XCTAssertThrowsError(try gate.complete(stream: 3, bytes: Data([1]), now: time))
        gate.begin(id: id, now: time); try gate.started(id: id, stream: 4, now: time)
        XCTAssertThrowsError(try gate.complete(stream: 4, bytes: Data([1]), now: time.addingTimeInterval(21)))
        gate.begin(id: id, now: time); try gate.started(id: id, stream: 5, now: time)
        XCTAssertEqual(try gate.complete(stream: 5, bytes: Data([1]), now: time),id)
        XCTAssertThrowsError(try gate.complete(stream: 5, bytes: Data([1]), now: time))
    }
    func testCalendarCandidateMechanicsDoNotInterpretProjectMeaning() {
        var snapshot = ContextSnapshot(observedAt: time)
        snapshot.calendar = [.init(id: "event",title: "Unfamiliar project name",start: time.addingTimeInterval(600),end:time.addingTimeInterval(1200))]
        let candidates = CalendarProactiveSource().candidates(snapshot: snapshot,now:time)
        XCTAssertEqual(candidates.count,1)
        XCTAssertEqual(CalendarProactiveSource().candidates(snapshot:snapshot,now:time.addingTimeInterval(100)).count,0)
        snapshot.unavailableSources = ["calendar"]
        XCTAssertTrue(CalendarProactiveSource().candidates(snapshot:snapshot,now:time).isEmpty)
    }
    func testDrawRejectsEntireTextBoundsNotOnlyAnchor() {
        XCTAssertThrowsError(try PrismDrawPacker.pack(.init(appID:"test",primitives:[.text(String(repeating:"x",count:32),x:320,y:44,color:0,anchor:.middleCenter)])))
    }
}

extension ContractTests {
    func testBlankInterruptsFragmentedWriteAfterOneAcknowledgementAndPreservesNewAsk() throws {
        var queue = DeviceWriteQueue(); let epoch = queue.epoch
        try queue.enqueue(kind:.draw,payload:Data(repeating:0,count:200),maxWriteLength:20)
        _ = queue.take(canSend:true,withResponse:true)
        queue.discardPendingAfterAcknowledgement()
        let clear = Data("CLEAR".utf8); let ask = Data("ASK".utf8)
        try queue.enqueue(kind:.controlJSON,payload:clear,maxWriteLength:20)
        try queue.enqueue(kind:.controlJSON,payload:ask,maxWriteLength:20)
        XCTAssertNil(queue.take(canSend:true,withResponse:true))
        queue.acknowledge(epoch:epoch)
        let receiver = PrismFrameReassembler(); var messages: [Data] = []
        while let frame = queue.take(canSend:true,withResponse:false) { if let complete = try receiver.ingest(frame,now:0) { messages.append(complete.payload) } }
        XCTAssertEqual(messages,[clear,ask])
    }
    func testDeviceClockAndDuplicateGateRejectOldOrReplayedGestures() throws {
        var gate = DeviceEventGate(); gate.newBoot("boot"); gate.synchronize(deviceTimestamp:100_000,receivedAt:time)
        let fresh = try ShellJSON.decoder().decode(DeviceControlEvent.self,from:Data(#"{"event":"BTN","id":"R","gesture":"DOUBLE","ts":100100}"#.utf8))
        XCTAssertTrue(gate.accept(fresh,receivedAt:time.addingTimeInterval(0.1),readyAt:time))
        XCTAssertFalse(gate.accept(fresh,receivedAt:time.addingTimeInterval(0.2),readyAt:time))
        let old = try ShellJSON.decoder().decode(DeviceControlEvent.self,from:Data(#"{"event":"BTN","id":"R","gesture":"TAP","ts":80000}"#.utf8))
        XCTAssertFalse(gate.accept(old,receivedAt:time,readyAt:time))
    }
    func testReassemblyRejectsChangedTotalsAndBoundsConcurrentStreams() throws {
        let receiver = PrismFrameReassembler()
        for id: UInt16 in 1...4 {
            _ = try receiver.ingest(.init(header:.init(kind:.streamAudio,flags:.start,messageID:id,sequence:0,totalLength:10),payloadFragment:Data([1])),now:0)
        }
        XCTAssertThrowsError(try receiver.ingest(.init(header:.init(kind:.streamAudio,flags:.start,messageID:5,sequence:0,totalLength:10),payloadFragment:Data([1])),now:0))
        XCTAssertThrowsError(try receiver.ingest(.init(header:.init(kind:.streamAudio,flags:.end,messageID:1,sequence:1,totalLength:9),payloadFragment:Data([1])),now:0)) { error in
            XCTAssertEqual(error as? PrismProtocolError,.inconsistentLength)
        }
    }
}
import PrismProtocol

extension ContractTests {
    func testModelCannotManufactureHostReceiptArtifacts() throws {
        let plan = ExperiencePlan(turn:.init(canonicalAnswer:"A claim",artifacts:[.init(title:"Created",body:"Fabricated receipt",kind:.receipt)]))
        XCTAssertThrowsError(try plan.validate(now:Date()))
        XCTAssertThrowsError(try ExperienceSchema.decode(ShellJSON.encoder().encode(plan),now:Date()))
    }
}
