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

    /// What a swipe is sent to.
    ///
    /// Not `app` on macOS: the application element has no frame there, so a
    /// swipe aimed at it fails with "unable to find hit point". The window has
    /// one. Same reason `testRootWallLoadsAlbums` measures the window rather
    /// than the app.
    private var swipeTarget: XCUIElement {
        #if os(macOS)
        app.windows.firstMatch
        #else
        app
        #endif
    }

    /// Scrolls the wall. `swipeUp`/`swipeDown` synthesise touch-style gestures
    /// that an AppKit scroll view ignores — the same trap as `tap()` vs
    /// `click()` below, and it made the chrome look like it never moved.
    private func scrollWall(towardsEnd: Bool) {
        #if os(macOS)
        // Aimed at the wall, not the window: a scroll delivered to the window
        // does not reach the scroll view inside it and moved nothing at all.
        // Generously: the desktop window is wide, its cells are correspondingly
        // tall, and the lazy stack's render window reaches well past the
        // viewport — a few hundred points does not retire the first cell, which
        // is what the chrome's visibility is derived from.
        control("masonry-wall").scroll(byDeltaX: 0, deltaY: towardsEnd ? -1200 : 1200)
        #else
        if towardsEnd { swipeTarget.swipeUp() } else { swipeTarget.swipeDown() }
        #endif
    }

    /// Moves the full-screen player one page along. `swipeLeft` is a touch-style
    /// gesture that the AppKit-backed pager ignores — 40 of them left the
    /// position on 1.
    private func pageForward() {
        #if os(macOS)
        control("viewer-pager").scroll(byDeltaX: -700, deltaY: 0)
        #else
        swipeTarget.swipeLeft()
        #endif
    }

    /// A drag from the very left edge — the interactive pop gesture, not a
    /// content swipe. `swipeRight()` starts in the middle of the screen and
    /// never reaches the edge recogniser.
    private func edgeSwipeBack() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.002, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// The visible text of an element. macOS leaves `label` empty for a SwiftUI
    /// `Text` and puts the string in `value` instead.
    private func text(of element: XCUIElement) -> String {
        if !element.label.isEmpty { return element.label }
        return (element.value as? String) ?? ""
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

    /// Resizing the wall must not also open what is under the fingers.
    ///
    /// The cells are `Button`s, and a SwiftUI tap does not care how many fingers
    /// are on the screen. The pinch is attached with `.simultaneousGesture` —
    /// the modifier whose entire meaning is "do not make the other gestures
    /// fail" — so nothing stopped a pinch from resizing the wall *and* opening
    /// the album the still finger happened to be resting on. See MultiTouch.
    func testPinchingTheWallDoesNotOpenACell() throws {
        #if os(macOS)
        // Pinch is a touch gesture. The desktop resizes the wall with ⌘+wheel
        // and from the menu bar, neither of which can carry a stray click along.
        throw XCTSkip("pinch is a touch gesture — the macOS wall resizes with ⌘+wheel")
        #else
        try XCTSkipUnless(
            StaggeredTouch.isAvailable,
            "the two-finger synthesiser is out of date — see StaggeredTouch"
        )
        let cell = firstFolderCell()
        let title = control("top-title-button")
        require(title, "the top bar is missing", timeout: 15)
        let titleBefore = text(of: title)
        let frame = cell.frame

        // One finger holds the cell while the other lands late and pulls away.
        // See StaggeredTouch for why XCTest's own `pinch` cannot show this up —
        // and note that this synthesised gesture does *not* actually re-column
        // the wall: whatever SwiftUI's `MagnifyGesture` wants out of an event
        // stream, a hand-built one does not give it. What it does reproduce is
        // the half that matters here, the stationary finger reading as a press.
        StaggeredTouch.pinch(
            holding: CGPoint(x: frame.midX, y: frame.midY),
            dragging: CGPoint(x: frame.midX, y: frame.midY + 200),
            to: CGPoint(x: frame.midX, y: frame.midY + 350)
        )
        // Navigation is animated and the wall it lands on has to load, so give
        // it time to have happened before concluding that it did not.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(
            text(of: title), titleBefore,
            "the still finger opened a cell — the wall is now showing \(text(of: title))"
        )

        // The gesture those two fingers are there for still works. Spreading
        // means "bigger pictures": from the 2 columns setUp pins, the wall goes
        // to 1 and every cell roughly doubles in width.
        //
        // Deliberately not followed by "and a real pinch still re-columns the
        // wall". XCTest sizes a synthesised pinch to the target's unoccluded
        // rect, and since the wall runs under the floating chrome that rect
        // varies with whatever the library happens to put on screen — the same
        // assertion passed and failed across runs because the travel sometimes
        // fell short of MasonryLayout.columnHysteresis. It was the synthesiser
        // being approximate, never the wall, and a test that fails a third of
        // the time teaches people to ignore it. What is asserted below covers
        // the risk this fix actually carries: a guard that eats taps.
        //
        // One finger still opens what it lands on.
        //
        // Tapped by its own identifier rather than through `firstFolderCell()`
        // twice: an XCUIElement query re-resolves on every access, so reading
        // the name off "the first cell" and then pressing "the first cell" can
        // land on two different albums if the wall moved in between — which,
        // after a gesture that drags, it may well have.
        let identifier = firstFolderCell().identifier
        let name = String(
            identifier.replacingOccurrences(of: "folder-cell:", with: "")
                .split(separator: "/").last ?? ""
        )
        control(identifier).press()
        waitUntil(
            "an ordinary tap no longer opens a cell — the guard is eating taps",
            timeout: 15
        ) {
            text(of: title) == name
        }
        #endif
    }

    /// The left-edge swipe goes back.
    ///
    /// The screen hides the navigation bar to draw its own chrome, and UIKit
    /// disables the interactive pop gesture along with the bar — so this was
    /// silently gone, on the one platform where it is how people go back. See
    /// InteractivePopEnabler; the code here used to claim the gesture "stays
    /// with the system", and this test is why that claim is no longer there.
    func testEdgeSwipeGoesBack() throws {
        #if os(macOS)
        throw XCTSkip("the edge swipe is a touch gesture — the desktop pushes inside a split view")
        #else
        _ = firstFolderCell()
        let title = control("top-title-button")
        require(title, "the top bar is missing", timeout: 15)
        let root = text(of: title)

        // On the root there is nothing to pop, and the gesture must decline
        // rather than run. Enabling it by clearing the recogniser's delegate —
        // the recipe found everywhere — lets it start here and leaves the
        // navigation controller wedged; the last step is what catches that.
        edgeSwipeBack()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(text(of: title), root, "swiping at the root went somewhere")

        openFolderAndWaitForTitle(toChangeFrom: root)
        edgeSwipeBack()
        waitUntil("the edge swipe did not pop — the app is still on \(text(of: title))") {
            text(of: title) == root
        }

        // And the stack still works afterwards.
        openFolderAndWaitForTitle(toChangeFrom: root)
        #endif
    }

    /// Opens the first folder on the wall and waits until the title says so.
    @discardableResult
    private func openFolderAndWaitForTitle(toChangeFrom previous: String) -> String {
        let title = control("top-title-button")
        firstFolderCell().press()
        waitUntil("opening a folder no longer goes anywhere") {
            text(of: title) != previous
        }
        return text(of: title)
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
    func testChromeHidesOnScrollDownAndReturnsOnScrollUp() throws {
        #if os(macOS)
        // iOS-only, and the reason is worth keeping: on macOS the wall does
        // scroll (the probe cell below moves), but the chrome never reacts —
        // the first-visible-item index that ScrollIntent is derived from does
        // not change. Either the lazy stack's render window on a 1100pt-wide
        // desktop window is deep enough that item 0 never retires, or AppKit's
        // lazy containers simply do not fire appear/disappear the way UIKit's
        // do. Which one it is has not been established, so this is a known gap
        // in macOS behaviour, not a test that needs re-tuning. Do not "fix" it
        // by scrolling harder until it passes.
        throw XCTSkip("chrome auto-hide is unverified on macOS — see the note here")
        #else
        _ = firstFolderCell()

        let tab = control("view-switcher:album")
        let title = control("top-title-button")
        require(tab, "the switcher is missing", timeout: 15)

        // Asserted on how far the chrome has *moved*, not on where it is.
        // Absolute frames are screen coordinates, and the two platforms do not
        // agree on the origin or on how much of the screen the app occupies —
        // an iOS-shaped "is it below the bottom edge" test read the macOS top
        // bar as being 942pt above the screen. Displacement is the mechanism
        // anyway: hiding is a 120pt offset.
        let tabRest = tab.frame.minY
        let titleRest = title.frame.minY
        let slid: CGFloat = 100

        // Several swipes: the first one only leaves the lazy container's render
        // window, where the wall still counts as being at the top.
        let probe = firstFolderCell()
        let probeRest = probe.frame.minY
        for _ in 0..<4 {
            scrollWall(towardsEnd: true)
        }
        // Checked separately so a failure says which half broke: the wall not
        // moving at all is a different bug from the chrome not reacting.
        XCTAssertGreaterThan(
            abs(probe.frame.minY - probeRest), slid,
            "the wall itself never scrolled — the gesture never reached it"
        )
        waitUntil("the switcher did not slide away (moved \(tab.frame.minY - tabRest)pt from \(tabRest))") {
            abs(tab.frame.minY - tabRest) > slid
        }
        waitUntil("the top bar did not slide away (moved \(title.frame.minY - titleRest)pt from \(titleRest))") {
            abs(title.frame.minY - titleRest) > slid
        }

        // Scrolling up brings it straight back — but only while the scroll is
        // live: once it settles, the chrome leaves again unless the wall is back
        // at the top. That is the intent (idle in the middle of the wall means a
        // clean screen), and it makes a single "swipe then assert" a race
        // against ScrollIntent.idleDelay. So: swipe, look briefly, swipe again.
        var returned = false
        for _ in 0..<5 where !returned {
            scrollWall(towardsEnd: false)
            let deadline = Date().addingTimeInterval(0.8)
            while Date() < deadline && !returned {
                returned = abs(tab.frame.minY - tabRest) < 20
                    && abs(title.frame.minY - titleRest) < 20
                if !returned { Thread.sleep(forTimeInterval: 0.1) }
            }
        }
        XCTAssertTrue(returned, "scrolling up never brought the chrome back")

        // And at the top it stays, with no timer involved.
        for _ in 0..<10 {
            scrollWall(towardsEnd: false)
        }
        waitUntil("the chrome should stay up once the wall is back at the top") {
            abs(tab.frame.minY - tabRest) < 20 && abs(title.frame.minY - titleRest) < 20
        }
        #endif
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
    func testRandomStreamKeepsGoingPastTheFirstBatch() throws {
        #if os(macOS)
        // iOS-only for a mechanical reason, not a behavioural one: nothing found
        // so far advances the full-screen pager on macOS. `swipeLeft` is a
        // touch-style gesture AppKit ignores (40 of them left the position on
        // 1), and `scroll(byDeltaX:)` cannot be aimed at the pager either — it
        // ignoresSafeArea, so its frame comes back as {271, -1050, 1510, 1050}
        // and XCTest finds no hit point in it. The thing under test — that the
        // stream keeps fetching — is platform-independent and covered on iOS.
        throw XCTSkip("no way found to page the macOS viewer from a UI test")
        #else
        _ = firstFolderCell()

        let randomTab = control("view-switcher:random")
        require(randomTab, "the random tab is missing", timeout: 15)
        randomTab.press()
        require(control("viewer-close"), "random did not open the player", timeout: 45)

        // Comfortably past RandomStream.batchSize (30). A sequence that never
        // grew would simply stop moving at its end.
        for _ in 0..<40 {
            pageForward()
        }

        XCTAssertEqual(app.state, .runningForeground, "the app died swiping the stream")
        XCTAssertTrue(
            control("viewer-close").exists,
            "the player closed itself — the stream ran out instead of fetching another batch"
        )
        // The counter is the position with no denominator (docs/adr/0008), and
        // it must have moved well past the first batch.
        //
        // Required, not `if counter.exists`. Everything above this passes when
        // the stream quietly stops — swiping past the end of a ScrollView does
        // not close the player — so this is the only assertion in the test that
        // can fail. It is also the only thing anywhere that proves iOS's
        // `fullScreenCover(item:)` re-publishes grown items under an unchanged
        // id, which is what ViewerContext's stable id is betting on.
        // By identifier, not by matching the label against a number pattern:
        // the pattern found nothing on macOS, and "which element is the counter"
        // is not something a test should be inferring anyway.
        let counter = control("viewer-counter")
        require(counter, "the position counter never appeared", timeout: 10)
        let reading = text(of: counter)
        guard let position = Int(reading) else {
            return XCTFail("counter read '\(reading)', expected a bare position")
        }
        XCTAssertGreaterThan(
            position, Self.randomBatchSize,
            "position \(position) never left the opening batch — the stream stopped growing"
        )
        #endif
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
    /// **Known open issue on macOS.** A run on macOS 27.0 beta (26A5425a) died
    /// with `Abort trap: 6` — `swift::fatalError` in `getSuperclassMetadata`
    /// while instantiating generic metadata inside the *system*
    /// `_AVKit_SwiftUI` framework. The whole stack is Apple's; the app only
    /// says `VideoPlayer(player:)`. It is not deterministic: other runs created
    /// video pages and played them fine. If macOS starts crashing around video,
    /// that is this, and the mitigation is to drop the SwiftUI shim on macOS and
    /// wrap `AVPlayerView` in an `NSViewRepresentable` instead.
    ///
    /// Note also that paging does not work on macOS (see
    /// testRandomStreamKeepsGoingPastTheFirstBatch), so there this only ever
    /// inspects the first sampled item and skips when it is not a video.
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
        //
        // macOS cannot page at all (see the note above), so there this inspects
        // only the item random happened to open on and skips otherwise. Worth
        // keeping rather than making the whole test iOS-only: the AVKit crash it
        // guards against showed up exactly this way, on the first sampled item.
        let video = control("viewer-video")
        var swipes = 0
        #if !os(macOS)
        while !video.exists && swipes < 40 {
            pageForward()
            swipes += 1
        }
        #endif
        try XCTSkipUnless(
            video.exists,
            "no video came up in \(swipes + 1) samples — nothing to exercise AVKit with"
        )

        // Let it actually start playing: the failure being guarded against here
        // is a crash while AVKit builds its player, not a missing element.
        Thread.sleep(forTimeInterval: 6)
        XCTAssertEqual(app.state, .runningForeground, "the app died while playing a video")

        // And swiping *off* a playing video must tear the player down cleanly.
        pageForward()
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
