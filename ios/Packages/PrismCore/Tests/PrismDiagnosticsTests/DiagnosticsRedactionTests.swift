import XCTest
import PrismDiagnostics

final class DiagnosticsRedactionTests: XCTestCase {
    func testDiagnosticsExportRedactsSecretsByDefault() {
        let event = DiagnosticsEvent(
            timestamp: Date(timeIntervalSince1970: 1_000),
            category: .provider,
            redactedMessage: "Authorization: Bearer sk-secret",
            metadata: ["api_key": "sk-metadata"]
        )

        let export = DiagnosticsRedactor().export(events: [event])

        XCTAssertFalse(export.includesPrivateContent)
        XCTAssertEqual(export.entries[0].message, "Authorization: Bearer [REDACTED]")
        XCTAssertEqual(export.entries[0].metadata["api_key"], "[REDACTED]")
    }
}
