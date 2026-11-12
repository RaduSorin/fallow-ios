import XCTest

/// Walks through Fallow the way a person would, on the Simulator. The app starts with a fresh,
/// empty vault every time ("-ui-testing"): the key lives in memory, there is no Face ID prompt
/// and no notification prompt. Texts are the English ones.
final class FallowUITests: XCTestCase {
    nonisolated(unsafe) private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    // MARK: Helpers

    /// The four first-run cards, then Face ID (in memory here).
    @MainActor
    private func finishSetup() {
        XCTAssertTrue(app.staticTexts["A quiet pause, one month at a time."].waitForExistence(timeout: 10))
        for _ in 0..<3 { app.buttons["Continue"].tap() }
        app.buttons["Protect with Face ID"].tap()
        XCTAssertTrue(tab("Today").waitForExistence(timeout: 10), "the app did not open after setup")
    }

    @MainActor
    private func tab(_ name: String) -> XCUIElement {
        let inBar = app.tabBars.buttons[name]
        return inBar.exists ? inBar : app.buttons[name].firstMatch
    }

    /// A text field by its identifier, single line or many.
    @MainActor
    private func field(_ id: String) -> XCUIElement {
        let single = app.textFields[id]
        if single.waitForExistence(timeout: 3) { return single }
        let multi = app.textViews[id]
        XCTAssertTrue(multi.waitForExistence(timeout: 3), "no field \(id)")
        return multi
    }

    @MainActor
    private func type(_ text: String, into id: String) {
        let element = field(id)
        element.tap()
        element.typeText(text)
    }

    /// A new plant shows its moment over everything; "Later" leaves it in the herbarium.
    @MainActor
    private func dismissPlantMoments() {
        let later = app.buttons["Later"]
        var guardCount = 0
        while later.waitForExistence(timeout: 2), guardCount < 6 {
            later.tap()
            guardCount += 1
        }
    }

    @MainActor
    private func text(containing part: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }

    @MainActor
    private func anyText(containing part: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !element.isHittable, swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    @MainActor
    private func planMonth(_ intention: String) {
        app.buttons["Plan the month"].firstMatch.tap()
        type(intention, into: "planner.intention")
        app.buttons["Save"].tap()
        dismissPlantMoments()
    }

    // MARK: Tests

    @MainActor
    func testFirstRunOpensAnEmptyToday() {
        launch()
        finishSetup()
        XCTAssertTrue(anyText(containing: "No intention yet").waitForExistence(timeout: 5))
        for name in ["Month", "Herbarium", "Me", "Today"] {
            XCTAssertTrue(tab(name).exists, "tab \(name) missing")
        }
    }

    @MainActor
    func testSetupCanGoBack() {
        launch()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["When should Fallow remind you?"].waitForExistence(timeout: 3))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["A quiet pause, one month at a time."].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPlanningTheMonthPutsTheIntentionOnTop() {
        launch()
        finishSetup()
        planMonth("Make room for slowness")
        XCTAssertTrue(anyText(containing: "Make room for slowness").waitForExistence(timeout: 5))
        tab("Month").tap()
        XCTAssertTrue(anyText(containing: "Make room for slowness").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Change the plan"].exists)
    }

    @MainActor
    func testThePlanCannotBeSavedWithoutAnIntention() {
        launch()
        finishSetup()
        app.buttons["Plan the month"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testWritingANoteShowsItToday() {
        launch()
        finishSetup()
        let write = app.buttons["Write a note"]
        scrollTo(write)
        write.tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled, "an empty note can be saved")
        type("Saw the first snow", into: "note.text")
        app.buttons["Save"].tap()
        dismissPlantMoments()
        XCTAssertTrue(anyText(containing: "Saw the first snow").waitForExistence(timeout: 5))
    }

    @MainActor
    func testARhythmIsTickedForToday() {
        launch()
        finishSetup()
        app.buttons["Add"].firstMatch.tap()
        type("Walk without the phone\n", into: "rhythm.new")
        app.buttons["Done"].tap()
        let row = app.buttons["rhythm.Walk without the phone"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Not yet today")
        row.tap()
        dismissPlantMoments()
        XCTAssertEqual(row.value as? String, "Done today")
        row.tap()
        XCTAssertEqual(row.value as? String, "Not yet today")
    }

    @MainActor
    func testTheWorryListGoesToTheJournal() {
        launch()
        finishSetup()
        let start = app.buttons["Start the worry list"]
        scrollTo(start)
        start.tap()
        XCTAssertFalse(app.buttons["Continue"].isEnabled, "an empty list can go on")
        type("3 bills to pay", into: "worry.text")
        app.buttons["Continue"].tap() // sort: clay by default
        XCTAssertTrue(app.staticTexts["3 bills to pay"].waitForExistence(timeout: 3), "the number was cut from the worry")
        app.buttons["Continue"].tap() // clay order
        app.buttons["Continue"].tap() // one small step
        let option = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "3 bills to pay")).firstMatch
        if option.waitForExistence(timeout: 3) { option.tap() }
        app.buttons["Continue"].tap() // the Good Parent
        app.buttons["Save to journal"].tap()
        dismissPlantMoments()
        XCTAssertTrue(anyText(containing: "Clay: 3 bills to pay").waitForExistence(timeout: 5))
    }

    @MainActor
    func testAnEmptyReflectionCannotBeSaved() {
        launch()
        finishSetup()
        tab("Month").tap()
        let start = app.buttons["Start the reflection"]
        scrollTo(start)
        start.tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        type("A slower month", into: "reflection.changed")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        dismissPlantMoments()
        XCTAssertTrue(app.buttons["Read or change it"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAnExerciseCanBeWrittenAndStarted() {
        launch()
        finishSetup()
        tab("Me").tap()
        app.buttons["My exercises"].tap()
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Write an exercise"].tap()
        type("Three breaths", into: "exercise.title")
        app.buttons["Save"].tap()
        dismissPlantMoments()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Three breaths")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Three breaths"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLockingKeepsWhatWasWritten() {
        launch()
        finishSetup()
        planMonth("Kept after locking")
        tab("Me").tap()
        let lock = app.buttons["Lock now"]
        scrollTo(lock)
        lock.tap()
        // Unlocking is immediate here (no Face ID): the journal opens again from the encrypted file.
        XCTAssertTrue(tab("Today").waitForExistence(timeout: 10))
        tab("Today").tap()
        XCTAssertTrue(anyText(containing: "Kept after locking").waitForExistence(timeout: 5))
    }

    @MainActor
    func testEraseEverythingStartsOver() {
        launch()
        finishSetup()
        planMonth("To be erased")
        tab("Me").tap()
        let erase = app.buttons["Erase everything"]
        scrollTo(erase)
        erase.tap()
        app.buttons["Erase from this iPhone"].tap()
        XCTAssertTrue(app.staticTexts["A quiet pause, one month at a time."].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTheHerbariumShowsThePlantThatCame() {
        launch()
        finishSetup()
        planMonth("A first intention")
        tab("Herbarium").tap()
        XCTAssertTrue(anyText(containing: "pressed").waitForExistence(timeout: 5))
        XCTAssertTrue(anyText(containing: "First intention").waitForExistence(timeout: 5))
    }
}
