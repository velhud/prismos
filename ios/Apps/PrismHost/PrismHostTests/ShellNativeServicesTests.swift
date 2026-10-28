import XCTest
import PrismAI
import PrismShell
@testable import PrismHost

private actor AudioHTTPBoundary: HTTPTransport {
    var bodies: [Data] = []
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        bodies.append(request.httpBody ?? Data())
        return (Data(#"{"text":"Complete real microphone transcript"}"#.utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
    }
}
final class ShellNativeServicesTests: XCTestCase {
    @MainActor func testDisabledContextDoesNotRequestPermissionsOrInventEvents() async {
        let boundary = EventKitShellTools(secrets:InMemorySecretStore())
        boundary.agentEndpoint = nil
        let snapshot = await boundary.context(privacy:PrivacySettings(),now:Date())
        XCTAssertTrue(snapshot.calendar.isEmpty); XCTAssertTrue(snapshot.agentExceptions.isEmpty)
        XCTAssertTrue(snapshot.unavailableSources.contains("calendar")); XCTAssertTrue(snapshot.unavailableSources.contains("agents"))
        var privacy = PrivacySettings(); privacy.agentEnabled = true
        let unconfigured = await boundary.context(privacy:privacy,now:Date())
        XCTAssertTrue(unconfigured.unavailableSources.contains("agents"))
    }
    func testCurrentFileTranscriptionBuildsWAVFromActualConvertedSamples() async throws {
        let http = AudioHTTPBoundary()
        let client = OpenAIAudioTranscriptionClient(configuration:.init(transcriptionModel:"gpt-transcribe"),apiKeyProvider:{"fixture"},userApprovedCloudProcessing:{true},transport:http)
        let pcm = MonocleAudioConverter().signed8BitPCMTo16BitLittleEndian(Data([0,127,128,255]))
        let input = TranscriptionInput(pcm16MonoLittleEndian:pcm,sampleRate:8000)
        let result = try await client.transcribe(input)
        XCTAssertEqual(result.requestID,input.requestID)
        let bodies = await http.bodies
        let body = try XCTUnwrap(bodies.first)
        XCTAssertNotNil(body.range(of:Data("RIFF".utf8))); XCTAssertNotNil(body.range(of:Data("WAVE".utf8)))
        XCTAssertNotNil(body.range(of:pcm)); XCTAssertNotNil(body.range(of:Data("gpt-transcribe".utf8)))
    }
    func testCloudDenialStopsBeforeHTTPBoundary() async throws {
        let http = AudioHTTPBoundary()
        let client = OpenAIAudioTranscriptionClient(configuration:.init(transcriptionModel:"gpt-transcribe"),apiKeyProvider:{"fixture"},userApprovedCloudProcessing:{false},transport:http)
        do { _ = try await client.transcribe(.init(pcm16MonoLittleEndian:Data([0,0]),sampleRate:8000)); XCTFail("Expected denied") }
        catch { XCTAssertEqual(error as? ProviderError,.missingApproval) }
        let bodies = await http.bodies; XCTAssertTrue(bodies.isEmpty)
    }
}

@MainActor private final class NotificationBoundaryDouble: TimerNotificationBoundary {
    var allowed = true
    var prompts = 0
    var cancels = 0
    var pending: FocusTimer?
    var onSchedule: (() async -> Void)?
    func requestAccess() async throws -> Bool { prompts += 1; return allowed }
    func authorized() async -> Bool { allowed }
    func cancel() { pending = nil; cancels += 1 }
    func schedule(_ timer: FocusTimer) async throws { await onSchedule?(); pending = timer }
}
extension ShellNativeServicesTests {
    @MainActor func testTimerRestorationClearsOrphanAndNeverPromptsImplicitly() async throws {
        let boundary = NotificationBoundaryDouble()
        boundary.pending = FocusTimer(id:"orphan",title:"Old",end:Date().addingTimeInterval(90))
        let scheduler = NativeTimerNotifications(boundary:boundary)
        await scheduler.synchronize(nil)
        XCTAssertNil(boundary.pending); XCTAssertEqual(boundary.prompts,0)
        boundary.allowed = false
        await scheduler.synchronize(.init(id:"new",title:"Focus",end:Date().addingTimeInterval(60)))
        XCTAssertNil(boundary.pending); XCTAssertEqual(boundary.prompts,0)
        XCTAssertTrue(scheduler.status.contains("allow notifications"))
    }
    @MainActor func testTimerUndoDuringSuspendedSchedulingConvergesToCanonicalState() async {
        let boundary = NotificationBoundaryDouble(); let scheduler = NativeTimerNotifications(boundary:boundary)
        boundary.onSchedule = { await scheduler.synchronize(nil) }
        await scheduler.synchronize(.init(id:"new",title:"Focus",end:Date().addingTimeInterval(60)))
        XCTAssertNil(boundary.pending); XCTAssertEqual(boundary.cancels,2)
        XCTAssertEqual(boundary.prompts,0)
    }
}
