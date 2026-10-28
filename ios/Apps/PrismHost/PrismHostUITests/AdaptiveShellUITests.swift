import XCTest
import PrismShell

final class AdaptiveShellUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ plans: [ExperiencePlan], id: UUID = UUID()) throws {
        app = XCUIApplication()
        app.launchEnvironment["PRISMOS_ACCEPTANCE_SESSION"] = id.uuidString
        app.launchEnvironment["PRISMOS_ACCEPTANCE_PLANS"] = String(decoding:try ShellJSON.encoder().encode(plans),as:UTF8.self)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout:15))
    }
    private func enableCloud() {
        app.tabBars.buttons["Settings"].tap()
        let cloud = app.switches["settings.cloud"]
        XCTAssertTrue(cloud.waitForExistence(timeout:5))
        cloud.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        XCTAssertEqual(cloud.value as? String,"1")
        app.tabBars.buttons["Home"].tap()
    }
    private func ask(_ text: String, answer: String) {
        let input = app.descendants(matching:.any).matching(identifier:"assistant.input").firstMatch
        if !input.isHittable { app.swipeDown(); app.swipeDown() }
        XCTAssertTrue(input.waitForExistence(timeout:5)); input.tap(); input.typeText(text)
        let submit = app.buttons["assistant.ask"]
        XCTAssertTrue(submit.exists); submit.tap()
        let output = app.staticTexts["assistant.completeAnswer"]
        let predicate = NSPredicate(format:"label == %@",answer)
        let expected = expectation(for:predicate,evaluatedWith:output)
        let result = XCTWaiter.wait(for: [expected], timeout:10)
        if result != .completed { print(app.debugDescription) }
        XCTAssertEqual(result, .completed)
    }
    func testFiveTurnsLongAnswerLibraryAndProcessRelaunch() throws {
        let id = UUID()
        let answers = (1...5).map { "Answer \($0): " + String(repeating:"Complete detail. ",count:80) + "Last conclusion \($0)." }
        let plans = answers.map { ExperiencePlan(turn:.init(canonicalAnswer:$0,spokenResponse:"A separate spoken explanation.",lensScene:.init(kind:.fact,title:"RESULT",body:"Useful complement"))) }
        try launch(plans,id:id); enableCloud()
        for i in 0..<5 { ask("Question \(i+1)",answer:answers[i]) }
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout:10)); app.tabBars.buttons["Library"].tap()
        let fifth = app.staticTexts["Question 5"].firstMatch
        XCTAssertTrue(fifth.waitForExistence(timeout:5)); fifth.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label == %@", answers[4])).firstMatch.waitForExistence(timeout:5))
        let attachment = XCTAttachment(screenshot:app.screenshot()); attachment.name = "Complete stored fifth turn after relaunch"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testNoteConfirmReceiptUndoAndPrivacyControls() throws {
        let body = "A complete structured note retained independently of the lens."
        let action = ProposedAction(id:"save",tool:.saveNote,summary:"Save naming decision",arguments:.init(title:"Naming decision",body:body,project:"Cedar",topic:"Naming"))
        let plan = ExperiencePlan(turn:.init(canonicalAnswer:"Please confirm the prepared note.",lensScene:.init(kind:.confirmation,title:"SAVE NOTE",body:"Cedar / naming"),proposedActions:[action]))
        try launch([plan]); enableCloud(); ask("Remember this thought",answer:plan.turn.canonicalAnswer)
        app.buttons["Confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Note saved: Naming decision"].firstMatch.waitForExistence(timeout:5))
        app.tabBars.buttons["Library"].tap()
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("complete structured note")
        XCTAssertTrue(app.staticTexts["Naming decision"].firstMatch.waitForExistence(timeout:5))
        app.buttons["Close"].tap()
        app.tabBars.buttons["Home"].tap(); app.buttons["assistant.undo"].firstMatch.tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertFalse(app.staticTexts["Naming decision"].firstMatch.exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["Developer console"].exists)
        let attachment = XCTAttachment(screenshot:app.screenshot()); attachment.name = "Normal settings without developer console"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testLibraryEditingSharingDeletionAndDeveloperSeparation() throws {
        let action = ProposedAction(id:"save",tool:.saveNote,summary:"Save test note",arguments:.init(title:"Editable note",body:"The original complete thought."))
        try launch([ExperiencePlan(turn:.init(canonicalAnswer:"Review the note",proposedActions:[action]))]); enableCloud()
        ask("Save a thought",answer:"Review the note")
        app.buttons["Confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Note saved: Editable note"].firstMatch.waitForExistence(timeout:5))
        app.tabBars.buttons["Library"].tap(); app.staticTexts["Editable note"].firstMatch.tap()
        app.buttons["Edit note"].tap()
        let editor = app.textViews["artifact.editBody"]
        XCTAssertTrue(editor.waitForExistence(timeout:5)); editor.tap()
        editor.typeText(" Additional durable detail.")
        app.buttons["Save changes"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Additional durable detail.")).firstMatch.waitForExistence(timeout:5))
        app.buttons["artifact.share"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout:5))
        app.cells["Copy"].tap()
        app.buttons["Delete artifact"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["Editable note"].firstMatch.exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["Developer console"].exists)
        let developer = app.switches["Developer Mode"]
        for _ in 0..<5 { if developer.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(developer.exists)
        developer.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        XCTAssertTrue(app.buttons["Developer console"].waitForExistence(timeout:5))
    }
    func testAllSceneKindsOnNativeHomeAndExactLensPreview() throws {
        let actions = [ProposedAction(id:"a",tool:.saveNote,summary:"Option A",arguments:.init(title:"A",body:"Option A")),ProposedAction(id:"b",tool:.saveNote,summary:"Option B",arguments:.init(title:"B",body:"Option B"))]
        let plans = SceneKind.allCases.map { kind -> ExperiencePlan in
            let scene = kind == .blank ? LensScene.blank : LensScene(kind:kind,title:kind.rawValue.uppercased(),body:"Useful complementary content",items:[.init("Option A","First value",actionID:kind == .choice ? "a" : nil),.init("Option B","Second value",actionID:kind == .choice ? "b" : nil)],progress:0.6,timerEnd:Date().addingTimeInterval(300))
            return .init(turn:.init(canonicalAnswer:"Scene: " + kind.rawValue,lensScene:scene,proposedActions:kind == .choice ? actions : []))
        }
        try launch(plans); enableCloud()
        for (index,plan) in plans.enumerated() {
            ask("Generate scene \(index)",answer:plan.turn.canonicalAnswer)
            app.tabBars.buttons["Lens"].tap()
            XCTAssertTrue(app.otherElements.matching(NSPredicate(format:"label BEGINSWITH %@","Monocle display preview")).firstMatch.waitForExistence(timeout:5))
            let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); attachment.name = plan.turn.lensScene.kind.rawValue; attachment.lifetime = .keepAlways; add(attachment)
            app.tabBars.buttons["Home"].tap()
        }
    }
    func testCloudDeniedAndInstantBlank() throws {
        try launch([])
        let input = app.descendants(matching:.any).matching(identifier:"assistant.input").firstMatch
        input.tap(); input.typeText("Do not send without permission"); app.buttons["assistant.ask"].tap()
        XCTAssertTrue(app.staticTexts["assistant.error"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["assistant.completeAnswer"].exists)
        app.buttons["assistant.blank"].tap()
        XCTAssertEqual(app.staticTexts["assistant.phase"].label,"Ready")
        app.tabBars.buttons["Library"].tap()
        XCTAssertFalse(app.staticTexts["Do not send without permission"].exists)
    }
}
