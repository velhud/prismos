import XCTest
import PrismDraw
import PrismModels
@testable import PrismRuntime

final class LocalAppsTests: XCTestCase {
    func testChronosClampsStopsAtZeroAndRendersAlarmUnderBudget() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var chronos = ChronosEngine(state: ChronosState(totalSeconds: 90))

        chronos.start(at: start)
        chronos.tick(at: start.addingTimeInterval(91))
        let payload = try PrismDrawPacker.pack(chronos.render(at: start.addingTimeInterval(91)))

        XCTAssertEqual(chronos.state.runState, .alarm)
        XCTAssertEqual(chronos.state.remaining(at: start.addingTimeInterval(91)), 0)
        XCTAssertEqual(chronos.alertRequest()?.delivery, .notificationAndHaptic)
        XCTAssertLessThanOrEqual(payload.count, PrismDrawConstants.maxPayloadBytes)
    }

    func testChronosTimerTruthSurvivesFocusStylePauseResume() {
        let start = Date(timeIntervalSince1970: 1_000)
        var chronos = ChronosEngine(state: ChronosState(totalSeconds: 300))

        chronos.start(at: start)
        chronos.pause(at: start.addingTimeInterval(42))
        chronos.start(at: start.addingTimeInterval(100))

        XCTAssertEqual(chronos.state.remaining(at: start.addingTimeInterval(110)), 248)
    }

    func testTeleprompterImportsWrapsAdvancesBookmarksAndRenders() throws {
        let script = TeleprompterEngine.importScript(
            title: "Toast",
            body: "We are gathered here today to celebrate a great achievement",
            maxLineCharacters: 18
        )
        var teleprompter = TeleprompterEngine(script: script)

        teleprompter.next()
        teleprompter.bookmarkOrReset()
        let payload = try PrismDrawPacker.pack(teleprompter.render())

        XCTAssertGreaterThan(script.chunks.count, 1)
        XCTAssertEqual(teleprompter.script.bookmarkIndex, 1)
        XCTAssertLessThanOrEqual(payload.count, PrismDrawConstants.maxPayloadBytes)
    }

    func testTeleprompterEmptyScriptFallbackIsBudgetSafe() throws {
        let teleprompter = TeleprompterEngine()

        let payload = try PrismDrawPacker.pack(teleprompter.render())

        XCTAssertLessThanOrEqual(payload.count, PrismDrawConstants.maxPayloadBytes)
    }

    func testSignalOrdersDismissesReloadsAndPrivacyMasksCards() throws {
        let info = SignalCard(source: "PRISM", title: "Sync", body: "Done", priority: .info, handoffURL: "https://example.com/signal")
        let critical = SignalCard(source: "SYS", title: "Battery", body: "Low", priority: .critical)
        var signal = SignalStack(cards: [info, critical])

        XCTAssertEqual(signal.currentCard?.title, "Battery")
        XCTAssertEqual(signal.currentIndex, 0)
        signal.moveSelection(by: 1)
        XCTAssertEqual(signal.currentCard?.title, "Sync")
        XCTAssertEqual(signal.currentIndex, 1)
        XCTAssertEqual(signal.openCurrentHandoff(), "https://example.com/signal")

        signal.dismissCurrent()
        XCTAssertEqual(signal.currentCard?.title, "Battery")
        XCTAssertEqual(signal.currentIndex, 0)

        signal.togglePrivacy()
        let viewport = signal.render()
        let payload = try PrismDrawPacker.pack(viewport)

        XCTAssertTrue(viewport.primitives.contains { primitive in
            if case let .text(text, _, _, _, _) = primitive {
                return text == "PRIVATE" || text == "OPEN PHONE"
            }
            return false
        })
        XCTAssertLessThanOrEqual(payload.count, PrismDrawConstants.maxPayloadBytes)

        signal.reloadSession()
        XCTAssertEqual(signal.currentCard?.id, critical.id)
        XCTAssertEqual(signal.visibleCards.map(\.title), ["Battery", "Sync"])
    }

    func testSignalCleanupRemovesExpiredArtifacts() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expired = SignalCard(source: "SYS", title: "Old", body: "Gone", expiresAt: now.addingTimeInterval(-1))
        let active = SignalCard(source: "SYS", title: "New", body: "Here", expiresAt: now.addingTimeInterval(60))
        var signal = SignalStack(cards: [expired, active])

        signal.cleanupExpired(now: now)

        XCTAssertEqual(signal.visibleCards.map(\.title), ["New"])
    }
}
