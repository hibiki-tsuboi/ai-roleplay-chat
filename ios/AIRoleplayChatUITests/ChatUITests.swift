import XCTest

@MainActor
final class ChatUITests: XCTestCase {
    func testFiveTurnResultSurvivesRelaunchAndCanRestartWithOpenAI() {
        let app = launchApp()
        app.segmentedControls["aiProviderPicker"].buttons["OpenAI"].tap()
        app.buttons["startConversation"].tap()
        completePractice(in: app)
        let score = app.otherElements["evaluationScore"].firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        XCTAssertTrue(score.label.contains("78"))
        XCTAssertFalse(app.buttons["sendMessage"].exists)
        capture(app, name: "practice-result-score")
        app.swipeUp()
        capture(app, name: "practice-result-feedback")

        app.terminate()
        app.launch()
        app.buttons["conversationRow"].firstMatch.tap()
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        XCTAssertTrue(score.label.contains("78"))
        app.buttons["restartPractice"].tap()
        XCTAssertTrue(app.staticTexts["practiceProgress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["practiceProgress"].label, "0 / 5 往復")
        XCTAssertEqual(app.staticTexts["conversationProvider"].label, "OpenAI")
        XCTAssertTrue(app.descendants(matching: .any)["messageInput"].firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.buttons.matching(identifier: "conversationRow").count, 2)
    }

    func testGeminiEvaluationFailureCanRetryWithoutAnotherChatTurn() {
        let app = launchApp()
        app.segmentedControls["aiProviderPicker"].buttons["Gemini"].tap()
        app.buttons["startConversation"].tap()
        completePractice(in: app, firstText: "evaluation-retry-once")
        XCTAssertTrue(app.staticTexts["evaluationError"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["sendMessage"].exists)
        capture(app, name: "practice-evaluation-retry")
        app.buttons["retryEvaluation"].tap()
        XCTAssertTrue(app.otherElements["evaluationScore"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["conversationProvider"].label, "Gemini")
    }

    private func completePractice(in app: XCUIApplication, firstText: String = "How is the report?") {
        for turn in 1...5 {
            let input = app.descendants(matching: .any)["messageInput"].firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            input.tap()
            input.typeText(turn == 1 ? firstText : "Let us check the next step \(turn).")
            app.buttons["sendMessage"].tap()
            if turn < 5 {
                let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(turn) / 5 往復"),
                    object: app.staticTexts["practiceProgress"])
                XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 10), .completed)
            }
        }
    }

    func testProviderSelectionStaysWithEachConversation() {
        let app = launchApp()
        let picker = app.segmentedControls["aiProviderPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Gemini"].tap()
        capture(app, name: "scenario-gemini-selected")
        app.buttons["startConversation"].tap()
        XCTAssertEqual(app.staticTexts["conversationProvider"].label, "Gemini")
        send("First Gemini turn", in: app, expecting: "Gemini:")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        picker.buttons["OpenAI"].tap()
        app.buttons["startConversation"].tap()
        XCTAssertEqual(app.staticTexts["conversationProvider"].label, "OpenAI")
        send("First OpenAI turn", in: app, expecting: "OpenAI:")

        app.terminate()
        app.launch()
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["OpenAI"].isSelected)
        let geminiHistory = app.buttons.matching(identifier: "conversationRow")
            .matching(NSPredicate(format: "label CONTAINS %@", "Gemini")).firstMatch
        XCTAssertTrue(geminiHistory.waitForExistence(timeout: 5))
        geminiHistory.tap()
        XCTAssertEqual(app.staticTexts["conversationProvider"].label, "Gemini")
        send("Continue Gemini history", in: app, expecting: "Gemini:", replyCount: 2)
        capture(app, name: "gemini-history-continued")
    }

    func testConversationCanBeSentReopenedAndContinued() {
        let app = launchApp()
        app.buttons["startConversation"].tap()
        let input = app.descendants(matching: .any)["messageInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sendMessage"].isEnabled)
        input.tap()
        input.typeText("How is the report?")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["assistantMessage"].firstMatch.waitForExistence(timeout: 45))
        XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 1)
        XCTAssertFalse(app.staticTexts["assistantMessage"].firstMatch.label.isEmpty)
        capture(app, name: "chat-first-reply")

        app.terminate()
        app.launch()
        app.buttons["conversationRow"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["assistantMessage"].firstMatch.waitForExistence(timeout: 5))
        let nextInput = app.descendants(matching: .any)["messageInput"].firstMatch
        nextInput.tap()
        nextInput.typeText("Can I help?")
        app.buttons["sendMessage"].tap()
        let twoReplies = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 2"),
            object: app.staticTexts.matching(identifier: "assistantMessage")
        )
        XCTAssertEqual(XCTWaiter.wait(for: [twoReplies], timeout: 45), .completed)
        XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 2)
        capture(app, name: "chat-continued")
    }

    func testFailureRetainsInputAndCanBeRetried() {
        let app = launchApp()
        app.buttons["startConversation"].tap()
        let input = app.descendants(matching: .any)["messageInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("retry-once")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["sendError"].waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "retry-once")
        XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 0)
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["assistantMessage"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 1)
        XCTAssertFalse(app.staticTexts["sendError"].exists)
    }

    func testHistoryCanBeDeleted() {
        let app = launchApp()
        app.buttons["startConversation"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.buttons["conversationRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["削除"].tap()
        XCTAssertTrue(app.staticTexts["emptyHistory"].waitForExistence(timeout: 5))
        capture(app, name: "scenario-empty-history")
    }

    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchEnvironment["ROLEPLAY_API_BASE_URL"] = ProcessInfo.processInfo.environment["ROLEPLAY_UI_TEST_API"]
            ?? "http://localhost:8788"
        app.launchEnvironment["ROLEPLAY_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["startConversation"].waitForExistence(timeout: 10))
        return app
    }

    private func send(_ text: String, in app: XCUIApplication, expecting prefix: String, replyCount: Int = 1) {
        let input = app.descendants(matching: .any)["messageInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(text)
        app.buttons["sendMessage"].tap()
        let replies = app.staticTexts.matching(identifier: "assistantMessage")
        let received = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", replyCount), object: replies
        )
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 10), .completed)
        XCTAssertTrue(replies.element(boundBy: replyCount - 1).label.hasPrefix(prefix))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
