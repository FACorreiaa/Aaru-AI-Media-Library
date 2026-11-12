import XCTest

/// Drives the running app from a script on the Mac, one command a line, without relaunching it.
/// A tool for preparing the store account, not a test: it does nothing unless `DRIVER_SCRIPT` is set.
///
///     tap <label>        first button, cell, or text with that label
///     tapn <n> <label>   the n-th match, from 0
///     at <x> <y>         a tap at a point of the screen, each 0…1
///     field              taps the first text field
///     type <text>        into whatever has the keyboard ("\n" sends Return)
///     clear              empties the focused field
///     open <url>         a deep link
///     swipe up|down|left|right
///     wait <seconds>     ·   snap <name>   ·   dump <name>
@MainActor
final class Driver: XCTestCase {
    private let app = XCUIApplication()
    private let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory()

    func testRunScript() throws {
        guard let path = ProcessInfo.processInfo.environment["DRIVER_SCRIPT"],
              let script = try? String(contentsOfFile: path, encoding: .utf8)
        else { throw XCTSkip("No DRIVER_SCRIPT.") }
        continueAfterFailure = true
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
        var log: [String] = []
        for line in script.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let rest = parts.count > 1 ? parts[1] : ""
            log.append("\(line) -> \(run(parts[0], rest))")
        }
        try log.joined(separator: "\n").write(toFile: folder + "/log.txt", atomically: true, encoding: .utf8)
    }

    private func run(_ command: String, _ rest: String) -> String {
        switch command {
        case "tap":
            return tap(rest, index: 0)
        case "tapn":
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            return tap(parts.last ?? "", index: Int(parts.first ?? "") ?? 0)
        case "at":
            return tapPoint(rest)
        case "field":
            return focusField()
        case "type":
            app.typeText(rest.replacingOccurrences(of: "\\n", with: "\n"))
        case "clear":
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60))
        case "open":
            guard let url = URL(string: rest) else { return "bad url" }
            app.open(url)
        default:
            return look(command, rest)
        }
        return "ok"
    }

    private func tapPoint(_ rest: String) -> String {
        let point = rest.split(separator: " ").compactMap { Double($0) }
        guard point.count == 2 else { return "bad point" }
        app.coordinate(withNormalizedOffset: CGVector(dx: point[0], dy: point[1])).tap()
        return "ok"
    }

    private func focusField() -> String {
        let fields = [app.searchFields.firstMatch, app.textFields.firstMatch, app.textViews.firstMatch]
        guard let field = fields.first(where: { $0.exists && $0.isHittable }) else { return "NO FIELD" }
        field.tap()
        return "ok"
    }

    /// The commands that move nothing in the app's data: looking, waiting, saving what is on screen.
    private func look(_ command: String, _ rest: String) -> String {
        switch command {
        case "swipe":
            swipe(rest)
        case "wait":
            Thread.sleep(forTimeInterval: Double(rest) ?? 1)
        case "snap":
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(rest).png"))
        case "dump":
            try? app.debugDescription.write(toFile: "\(folder)/\(rest).txt", atomically: true, encoding: .utf8)
        default:
            return "unknown"
        }
        return "ok"
    }

    private func tap(_ label: String, index: Int) -> String {
        let named = NSPredicate(format: "label == %@", label)
        let begins = NSPredicate(format: "label BEGINSWITH %@", label)
        for predicate in [named, begins] {
            let found = app.descendants(matching: .any).matching(predicate)
            if index == 0, !found.firstMatch.waitForExistence(timeout: 4) {
                continue
            }
            let hittable = found.allElementsBoundByIndex.filter(\.isHittable)
            if hittable.count > index {
                hittable[index].tap()
                return "ok (\(hittable.count) hittable)"
            }
        }
        return "NOT FOUND"
    }

    private func swipe(_ direction: String) {
        switch direction {
        case "up": app.swipeUp()
        case "down": app.swipeDown()
        case "left": app.swipeLeft()
        default: app.swipeRight()
        }
    }
}
