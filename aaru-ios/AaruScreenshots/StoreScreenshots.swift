import XCTest

/// The App Store's pictures (REL-005): walks the signed-in app and saves one PNG per screen.
/// Not a test of anything and never run in CI: it has its own scheme, "Aaru Screenshots".
///
/// The app must already be signed in on the simulator; this never signs in and never resets the
/// app. `scripts/store-screenshots.sh` sets the status bar, runs it on each device and collects
/// the files from `SCREENSHOT_DIR`.
@MainActor
final class StoreScreenshots: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        app.launch()
    }

    func testStoreScreens() throws {
        let home = tab("Home")
        guard home.waitForExistence(timeout: 20) else {
            throw XCTSkip("The app is not signed in on this simulator. Sign in, then run again.")
        }

        home.tap()
        snap("01-home")

        tab("Library").tap()
        snap("02-library")

        // One show with seasons to tick, from the Watching row: whichever of the demo
        // account's is on screen (an iPhone shows fewer than an iPad).
        if let show = firstVisible(["The Last of Us", "Slow Horses", "The Bear", "One Piece"]) {
            show.tap()
            snap("03-title")
            back()
        }

        tab("Calendar").tap()
        snap("04-calendar")

        tab("Discover").tap()
        let onAir = app.buttons["On air"].firstMatch
        if onAir.waitForExistence(timeout: 5) {
            onAir.tap()
        }
        snap("05-discover")

        tab("Home").tap()
        askTheOwl("Add Dune, Arrival and Blade Runner 2049 to my plan to watch")
        snap("06-assistant")
        discardThePlan()
    }

    /// The plan stays a proposal: the picture is of the question, and the account is left as it was.
    private func discardThePlan() {
        let review = app.buttons["Review and save"].firstMatch
        if review.exists, review.isHittable {
            review.tap()
        }
        let decline = app.buttons["Not this"].firstMatch
        for _ in 0 ..< 5 where !(decline.exists && decline.isHittable) {
            app.swipeUp()
        }
        guard decline.exists, decline.isHittable else { return }
        decline.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch
        if confirm.waitForExistence(timeout: 3) {
            confirm.tap()
        }
    }

    private func firstVisible(_ names: [String]) -> XCUIElement? {
        for name in names {
            let named = NSPredicate(format: "label BEGINSWITH %@", name)
            let found = app.descendants(matching: .any).matching(named).allElementsBoundByIndex
            if let hit = found.first(where: \.isHittable) {
                return hit
            }
        }
        return nil
    }

    /// Opens the assistant card, asks one question and waits for the reply to finish.
    private func askTheOwl(_ question: String) {
        let owl = app.buttons["Ask Aaru"].firstMatch
        guard owl.waitForExistence(timeout: 5) else { return }
        owl.tap()
        let newChat = app.buttons["New chat"].firstMatch
        if newChat.waitForExistence(timeout: 2), newChat.isHittable {
            newChat.tap()
        }
        let field = app.textFields["Ask Aaru"].firstMatch
        guard field.waitForExistence(timeout: 5) else { return }
        field.tap()
        field.typeText(question)
        app.buttons.matching(identifier: "arrow.up.circle.fill").firstMatch.tap()
        let card = NSPredicate(format: "label IN %@", ["Review and save", "Approve"])
        // The reply streams, and a plan's card comes last.
        _ = app.buttons.matching(card).firstMatch.waitForExistence(timeout: 60)
        hideKeyboard()
    }

    /// An iPad's keyboard has a key for it; on an iPhone the card's transcript drags it away.
    private func hideKeyboard() {
        let hide = app.buttons["Hide keyboard"].firstMatch
        if hide.exists {
            hide.tap()
        } else if app.keyboards.firstMatch.exists {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36))
            from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        }
    }

    // MARK: Getting around

    /// A tab by its name: the bar on iPhone, the floating bar or the sidebar on iPad.
    private func tab(_ name: String) -> XCUIElement {
        let inBar = app.tabBars.buttons[name]
        return inBar.exists ? inBar : app.buttons[name].firstMatch
    }

    private func back() {
        let button = app.navigationBars.buttons.firstMatch
        if button.exists {
            button.tap()
        }
    }

    // MARK: Saving

    /// Lets posters and rows settle, then saves the screen: to `SCREENSHOT_DIR` when the script
    /// set it (the simulator shares the Mac's disk), and to the test report either way.
    private func snap(_ name: String) {
        Thread.sleep(forTimeInterval: 6)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !folder.isEmpty else { return }
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try shot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("Could not save \(name): \(error.localizedDescription)")
        }
    }
}
