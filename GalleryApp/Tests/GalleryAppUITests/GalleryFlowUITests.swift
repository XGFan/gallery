import XCTest

/// End-to-end flow against the real backend.
///
/// This deliberately does not mock the network: the whole point is to prove the
/// client can reach the library, page it, and render it. It therefore requires
/// the machine to be on a network that tinyauth's IP bypass covers (LAN or
/// easytier) — see docs/adr/0004.
final class GalleryFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Opt-in switch for the macOS run. Pass it through xcodebuild as
    /// `TEST_RUNNER_GALLERY_MACOS_E2E=1`.
    static let macOSOptIn = "GALLERY_MACOS_E2E"

    /// Mirrors `RandomStream.batchSize`. A UI test runs out of process, so it
    /// cannot import the app to read the real one — keep the two in step.
    static let randomBatchSize = 30

    override func setUpWithError() throws {
        #if os(macOS)
        // On macOS this suite drives the real desktop: it warps the pointer to
        // each target and needs the window on the current Space, so it cannot
        // share the machine with whoever is using it. It therefore never runs
        // as a side effect of testing the scheme — only when asked for by name.
        // The check sits before launch() so a skipped run opens no window.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment[Self.macOSOptIn] == "1",
            "macOS E2E takes over the mouse and the current Space; " +
                "run it on purpose with TEST_RUNNER_\(Self.macOSOptIn)=1"
        )
        #endif
        continueAfterFailure = false
        app = XCUIApplication()
        // The column count persists in UserDefaults, so without this each test
        // would inherit the previous one's. NSUserDefaults honours these as
        // command-line overrides — no test-only code needed in the app itself.
        // The view is no longer among them: since docs/adr/0007 it travels with
        // the route rather than living in a global preference, so every launch
        // starts at the root's `album` regardless of what happened last time.
        app.launchArguments = ["-wall.columns", "2"]
        app.launch()
    }

    // MARK: - Finding things

    private func element(prefix: String, timeout: TimeInterval = 30) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// Controls do not keep the same element type across platforms, so match on
    /// the identifier alone rather than on `app.buttons`.
    private func control(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Polls a condition rather than asserting on the spot. The chrome slides
    /// in and out over 0.3s, so reading its frame the instant a swipe returns
    /// catches it mid-animation.
    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 6,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail(what)
    }

    private func require(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 30) {
        if !element.waitForExistence(timeout: timeout) {
            XCTFail("\(what). Hierarchy:\n\(app.debugDescription)")
        }
    }

    private func firstFolderCell(timeout: TimeInterval = 30) -> XCUIElement {
        let cell = element(prefix: "folder-cell:")
        require(
            cell,
            "no folder cell appeared — is the backend reachable from this network?",
            timeout: timeout
        )
        return cell
    }

    private func firstMediaCell(timeout: TimeInterval = 30) -> XCUIElement {
        let cell = element(prefix: "media-cell:")
        require(cell, "no media cell appeared", timeout: timeout)
        return cell
    }

    /// Opens the tree: a drawer on iOS, an always-there sidebar on macOS whose
    /// button toggles the split view's column.
    private func openTree() {
        let anyNode = element(prefix: "tree-node:")
        if anyNode.waitForExistence(timeout: 5) { return }

        let drawer = control("top-drawer-button")
        require(drawer, "the drawer button is missing", timeout: 15)
        drawer.press()
        require(anyNode, "the tree never rendered a node")
    }

    // MARK: - The wall

    /// The app opens on the root's `album` view — every album in the library,
    /// flattened. See docs/adr/0007 for why that is the landing view.
    func testRootWallLoadsAlbums() {
        let cell = firstFolderCell()

        // Existence is not enough. A regression once collapsed every column to
        // the 1pt floor (the wall measured its own content to decide its content
        // width); every existence assertion still passed while the wall was a
        // hairline. Assert the cell occupies a plausible share of the screen.
        // On macOS the application element has no frame — the size lives on the
        // window. Reading app.frame there yields 0 and the assertion fails for a
        // reason that has nothing to do with the wall.
        let windowWidth = app.windows.firstMatch.frame.width
        let containerWidth = windowWidth > 0 ? windowWidth : app.frame.width
        XCTAssertGreaterThan(containerWidth, 0, "could not measure the container")
        XCTAssertGreaterThan(
            cell.frame.width,
            containerWidth / 6,
            "cell is \(cell.frame.width)pt wide in a \(containerWidth)pt container — the wall collapsed"
        )
        XCTAssertGreaterThan(cell.frame.height, 20, "cell has no height")
    }

    /// The switcher's whole job: `image` turns the wall into every descendant
    /// medium, flattened.
    func testSwitchingToImageProducesMediaWall() {
        _ = firstFolderCell()

        let imageTab = control("view-switcher:image")
        require(imageTab, "the image tab is missing", timeout: 15)
        imageTab.press()

        _ = firstMediaCell(timeout: 45)
    }

    /// The chrome gets out of the way while scrolling down and comes back on
    /// the way up. It is the reason the wall gets the whole screen, and nothing
    /// else covers it.
    ///
    /// Asserted on position, not on `exists` or `isHittable`: neither of those
    /// reflects a SwiftUI view that is transparent, non-hit-testable and marked
    /// accessibility-hidden — both keep reporting it as present. Where it *is*
    /// is unambiguous.
    func testChromeHidesOnScrollDownAndReturnsOnScrollUp() {
        _ = firstFolderCell()

        let tab = control("view-switcher:album")
        let title = control("top-title-button")
        require(tab, "the switcher is missing", timeout: 15)
        let screenHeight = app.windows.firstMatch.frame.height
        XCTAssertLessThan(tab.frame.minY, screenHeight, "the switcher should be up at rest")
        XCTAssertGreaterThan(title.frame.maxY, 0, "the top bar should be up at rest")

        // Several swipes: the first one only leaves the lazy container's render
        // window, where the wall still counts as being at the top.
        for _ in 0..<4 {
            app.swipeUp()
        }
        waitUntil("the switcher stayed over the wall while scrolling down") {
            tab.frame.minY >= screenHeight
        }
        waitUntil("the top bar stayed over the wall while scrolling down") {
            title.frame.maxY <= 0
        }

        // Scrolling up brings it straight back — but only for as long as the
        // scroll is live: once it settles the chrome leaves again unless the
        // wall is back at the top, which is the point (idle in the middle of the
        // wall means a clean screen). So the window here is deliberately shorter
        // than ScrollIntent.idleDelay; a longer one races that timer and the
        // test flaps.
        app.swipeDown()
        app.swipeDown()
        waitUntil("scrolling up should bring the switcher back", timeout: 1.2) {
            tab.frame.minY < screenHeight
        }
        waitUntil("scrolling up should bring the top bar back", timeout: 1.2) {
            title.frame.maxY > 0
        }
    }

    /// `explore` is the other end of the switcher: this level only.
    func testSwitchingToExploreShowsThisLevel() {
        _ = firstFolderCell()

        let exploreTab = control("view-switcher:explore")
        require(exploreTab, "the explore tab is missing", timeout: 15)
        exploreTab.press()

        // The root's direct children are folders, and there are far fewer of
        // them than the 1822 albums the flattened view lists.
        require(element(prefix: "folder-cell:"), "explore showed nothing at the root")
    }

    /// A cell in the `album` view *is* an album, so opening one goes straight to
    /// its pictures rather than to another folder listing. This is the mapping
    /// from docs/adr/0007 that a user feels most directly.
    func testOpeningAnAlbumLandsOnItsPictures() {
        let album = firstFolderCell()
        let path = album.identifier.replacingOccurrences(of: "folder-cell:", with: "")
        let name = String(path.split(separator: "/").last ?? "")
        album.press()

        // Not "a cell whose path starts with the album's path". A virtual path
        // (CONTEXT.md) aggregates folders from elsewhere in the library, so
        // `奶酪坏了` is full of media living under `Twitter/cheesegonebad77/…`
        // — the child paths carry no trace of the parent. Assert on the title
        // instead, which is where the app says which folder it is showing.
        // A back button is no good either: macOS pushes inside the split view's
        // detail column and has no navigation bar.
        _ = firstMediaCell(timeout: 45)

        let title = control("top-title-button")
        require(title, "the top bar is missing after opening \(name)", timeout: 15)
        XCTAssertEqual(title.label, name, "opened \(title.label), expected \(name)")
    }

    // MARK: - The tree

    /// The core of the tree's interaction: the triangle expands and *only*
    /// expands. Before docs/adr/0007 a parent row could not be opened without
    /// also navigating, which is what made mid-level folders unreachable.
    func testTreeDisclosureExpandsWithoutNavigating() {
        _ = firstFolderCell()
        openTree()

        let disclosure = element(prefix: "tree-disclosure:")
        require(disclosure, "no expandable node in the tree", timeout: 15)
        let path = disclosure.identifier.replacingOccurrences(of: "tree-disclosure:", with: "")
        disclosure.press()

        require(element(prefix: "tree-node:\(path)/"), "the triangle did not expand \(path)")
        XCTAssertTrue(
            element(prefix: "tree-node:").exists,
            "expanding must not dismiss the tree — that is navigation's job, not the triangle's"
        )
    }

    /// And the row navigates. A directory node is a legitimate destination now,
    /// not just a leaf.
    func testTappingATreeNodeNavigatesToIt() {
        _ = firstFolderCell()
        openTree()

        let node = element(prefix: "tree-node:")
        require(node, "the tree never rendered a node")
        let path = node.identifier.replacingOccurrences(of: "tree-node:", with: "")
        let name = String(path.split(separator: "/").last ?? "")
        node.press()

        // Same virtual-path caveat as testOpeningAnAlbumLandsOnItsPictures:
        // what lands on the wall need not carry this node's path as a prefix.
        let title = control("top-title-button")
        require(title, "tapping the tree node \(path) did not go anywhere", timeout: 20)
        XCTAssertEqual(title.label, name, "landed on \(title.label), expected \(name)")

        let arrived = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'folder-cell:' OR identifier BEGINSWITH 'media-cell:'")
        ).firstMatch
        require(arrived, "\(path) opened but its wall stayed empty", timeout: 30)
    }

    // MARK: - The player

    /// `random` is an action, not a fourth view: it goes straight into the
    /// player, and closing it puts the user back on the wall they left.
    /// See docs/adr/0008.
    func testRandomOpensThePlayerAndComesBack() {
        _ = firstFolderCell()

        let randomTab = control("view-switcher:random")
        require(randomTab, "the random tab is missing", timeout: 15)
        randomTab.press()

        let close = control("viewer-close")
        require(close, "random did not open the player", timeout: 45)
        close.press()

        require(control("view-switcher:random"), "closing the player should return to the wall")
        _ = firstFolderCell(timeout: 20)
    }

    /// The stream has no end: swiping past the opening batch must fetch another
    /// one rather than dead-ending. The two halves are unit-tested separately
    /// (RandomStream appends, ViewerPresenter re-publishes); this covers the
    /// wiring between them, which nothing else does.
    func testRandomStreamKeepsGoingPastTheFirstBatch() {
        _ = firstFolderCell()

        let randomTab = control("view-switcher:random")
        require(randomTab, "the random tab is missing", timeout: 15)
        randomTab.press()
        require(control("viewer-close"), "random did not open the player", timeout: 45)

        // Comfortably past RandomStream.batchSize (30). A sequence that never
        // grew would simply stop moving at its end.
        for _ in 0..<40 {
            app.swipeLeft()
        }

        XCTAssertEqual(app.state, .runningForeground, "the app died swiping the stream")
        XCTAssertTrue(
            control("viewer-close").exists,
            "the player closed itself — the stream ran out instead of fetching another batch"
        )
        // The counter is the position with no denominator (docs/adr/0008), and
        // it must have moved well past the first batch.
        let counter = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '^[0-9]+$'")
        ).firstMatch
        if counter.exists, let position = Int(counter.label) {
            XCTAssertGreaterThan(
                position, Self.randomBatchSize,
                "position \(position) never left the opening batch"
            )
        }
    }

    /// Tapping a medium opens the single horizontal-swipe player (docs/adr/0001)
    /// and closing it returns to the wall.
    func testOpeningAndClosingViewer() {
        _ = firstFolderCell()

        let imageTab = control("view-switcher:image")
        require(imageTab, "the image tab is missing", timeout: 15)
        imageTab.press()

        firstMediaCell(timeout: 45).press()

        let close = control("viewer-close")
        require(close, "the player did not open", timeout: 20)
        close.press()

        require(control("view-switcher:image"), "closing the player should return to the wall")
    }

    /// Opening a video goes through AVKit's `VideoPlayer`, a completely
    /// different view path from the image viewer — and when it fails it does
    /// not fail politely, it takes the process down. This is the only test that
    /// covers it.
    ///
    /// It gets there through `random` rather than by walking to a folder known
    /// to hold clips. The old version opened a hard-coded "Beauty Video" folder,
    /// which the deployed config excludes — so it had been quietly skipping,
    /// covering nothing. A mixed random stream is a few dozen samples drawn from
    /// the whole library, so it reaches videos without the test knowing anything
    /// about how this particular library is arranged.
    func testPlayingAVideoKeepsTheAppAlive() throws {
        _ = firstFolderCell()

        let randomTab = control("view-switcher:random")
        require(randomTab, "the random tab is missing", timeout: 15)
        randomTab.press()
        require(control("viewer-close"), "random did not open the player", timeout: 45)

        // Swipe along the stream until a video page shows up. The library is
        // ~98.6% photos, but the sampler's per-level split makes videos far more
        // likely than that ratio suggests — in practice a handful of swipes.
        let video = control("viewer-video")
        var swipes = 0
        while !video.exists && swipes < 40 {
            app.swipeLeft()
            swipes += 1
        }
        try XCTSkipUnless(
            video.exists,
            "no video came up in \(swipes) samples — nothing to exercise AVKit with"
        )

        // Let it actually start playing: the failure being guarded against here
        // is a crash while AVKit builds its player, not a missing element.
        Thread.sleep(forTimeInterval: 6)
        XCTAssertEqual(app.state, .runningForeground, "the app died while playing a video")

        // And swiping *off* a playing video must tear the player down cleanly.
        app.swipeLeft()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "the app died leaving a video")
    }

    // MARK: - Getting back out

    /// The path sheet replaces the breadcrumb the self-drawn chrome has no room
    /// for. It is the only way back to an ancestor that was never visited — the
    /// case a jump from the tree creates.
    func testPathSheetJumpsToAnAncestor() {
        firstFolderCell().press()
        _ = firstMediaCell(timeout: 45)

        let title = control("top-title-button")
        require(title, "the title is not tappable", timeout: 15)
        title.press()

        let root = control("path-crumb:")
        require(root, "the path sheet did not open, or the root crumb is missing")
        root.press()

        require(control("view-switcher:album"), "jumping to the root should land on album")
        _ = firstFolderCell(timeout: 20)
    }
}

private extension XCUIElement {
    /// `tap()` compiles for macOS, but the event it synthesises there is a
    /// touch-style tap that an AppKit window never receives: the element stays
    /// exactly as it was and the test just times out waiting for a result
    /// (verified on macOS 27 / Xcode 27 — the toggle kept `value: 0`, the folder
    /// never pushed). `click()` is the mouse event a Mac app actually handles.
    func press() {
        #if os(macOS)
        click()
        #else
        tap()
        #endif
    }
}
