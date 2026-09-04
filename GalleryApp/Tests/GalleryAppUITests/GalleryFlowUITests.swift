import XCTest

/// End-to-end flow against the real backend.
///
/// This deliberately does not mock the network: the whole point is to prove the
/// client can reach the library, page it, and render it. It therefore requires
/// the machine to be on a network that tinyauth's IP bypass covers (LAN or
/// easytier) — see docs/adr/0004.
final class GalleryFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // The recursive toggle and column count persist in UserDefaults, so
        // without this each test would inherit the previous one's state.
        // NSUserDefaults honours these as command-line overrides — no
        // test-only code needed in the app itself.
        app.launchArguments = ["-folder.recursive", "NO", "-wall.columns", "2"]
        app.launch()
    }

    private func firstFolderCell(timeout: TimeInterval = 30) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'folder-cell:'")
        let cell = app.descendants(matching: .any).matching(predicate).firstMatch
        if !cell.waitForExistence(timeout: timeout) {
            XCTFail("""
            no folder cell appeared — is the backend reachable from this network?
            Hierarchy:
            \(app.debugDescription)
            """)
        }
        return cell
    }

    private func firstMediaCell(timeout: TimeInterval = 30) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'media-cell:'")
        let cell = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: timeout), "no media cell appeared")
        return cell
    }

    /// The wall renders the root folder's children from the live library.
    func testRootWallLoadsFolders() {
        let cell = firstFolderCell()

        // Existence is not enough. A regression once collapsed every column to
        // the 1pt floor (the wall measured its own content to decide its content
        // width); every existence assertion still passed while the wall was a
        // hairline. Assert the cell occupies a plausible share of the screen.
        let screenWidth = app.frame.width
        XCTAssertGreaterThan(screenWidth, 0)
        XCTAssertGreaterThan(
            cell.frame.width,
            screenWidth / 6,
            "cell is \(cell.frame.width)pt wide on a \(screenWidth)pt screen — the wall collapsed"
        )
        XCTAssertGreaterThan(cell.frame.height, 20, "cell has no height")
    }

    /// Tapping a folder pushes a new folder screen — the shallow view's
    /// navigation model (CONTEXT.md).
    func testTappingFolderPushesIntoIt() {
        let folder = firstFolderCell()
        let name = folder.identifier.replacingOccurrences(of: "folder-cell:", with: "")
        folder.tap()

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 15),
            "expected to have pushed into \(name)"
        )
    }

    /// The recursive toggle turns the shallow view into a flattened media wall.
    /// This is the single control that replaces three of the web frontend's
    /// URL "modes".
    func testRecursiveToggleProducesMediaWall() {
        _ = firstFolderCell()

        let toggle = app.buttons["recursive-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "recursive toggle missing")
        toggle.tap()

        // The root recursive view is the whole library, so media must appear
        // where previously there were only folders.
        _ = firstMediaCell(timeout: 45)

    }

    /// Tapping a medium opens the single horizontal-swipe viewer (docs/adr/0001)
    /// and closing it returns to the wall.
    func testOpeningAndClosingViewer() {
        _ = firstFolderCell()

        let toggle = app.buttons["recursive-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()

        let media = firstMediaCell(timeout: 45)
        media.tap()

        let close = app.buttons["viewer-close"]
        if !close.waitForExistence(timeout: 20) {
            XCTFail("viewer did not open. Hierarchy:\n\(app.debugDescription)")
            return
        }
        close.tap()

        XCTAssertTrue(
            toggle.waitForExistence(timeout: 15),
            "closing the viewer should return to the wall"
        )
    }
}
