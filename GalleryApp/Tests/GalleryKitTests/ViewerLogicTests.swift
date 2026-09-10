import CoreGraphics
import XCTest

@testable import GalleryApp

/// The gesture arbitration that went wrong on device: swipes dropping and the
/// picture juddering while pinching.
final class ViewerGestureTests: XCTestCase {
    /// At 1x the horizontal drag belongs to the pager. The pan gesture must not
    /// even be in the recognition chain, or it steals swipes.
    func testPanOnlyOnceZoomed() {
        XCTAssertFalse(ViewerGesture.allowsPan(scale: 1))
        XCTAssertFalse(ViewerGesture.allowsPan(scale: 1.005), "a hair above 1 still counts as fit")
        XCTAssertTrue(ViewerGesture.allowsPan(scale: 1.5))
        XCTAssertTrue(ViewerGesture.allowsPan(scale: 6))
    }

    /// A swipe that is mostly sideways must not be taken as a dismiss, otherwise
    /// left/right paging "sometimes does nothing".
    func testDismissRequiresVerticalDominance() {
        let mostlySideways = CGSize(width: 100, height: 40)
        XCTAssertFalse(ViewerGesture.isDismissDrag(translation: mostlySideways, scale: 1))

        let clearlyDown = CGSize(width: 20, height: 120)
        XCTAssertTrue(ViewerGesture.isDismissDrag(translation: clearlyDown, scale: 1))

        let upward = CGSize(width: 0, height: -120)
        XCTAssertFalse(ViewerGesture.isDismissDrag(translation: upward, scale: 1), "up is not dismiss")
    }

    /// While zoomed a downward drag is panning, not dismissing.
    func testZoomedDragIsNeverDismiss() {
        let down = CGSize(width: 0, height: 200)
        XCTAssertFalse(ViewerGesture.isDismissDrag(translation: down, scale: 2.5))
        XCTAssertFalse(
            ViewerGesture.shouldCommitDismiss(
                translation: down, velocity: CGSize(width: 0, height: 2000), scale: 2.5
            )
        )
    }

    func testDismissCommitsOnDistanceOrFlick() {
        let slow = CGSize(width: 0, height: 10)
        let far = CGSize(width: 0, height: 200)
        let fast = CGSize(width: 0, height: 1500)

        XCTAssertTrue(
            ViewerGesture.shouldCommitDismiss(translation: far, velocity: .zero, scale: 1),
            "a long drag commits"
        )
        XCTAssertTrue(
            ViewerGesture.shouldCommitDismiss(
                translation: CGSize(width: 0, height: 80), velocity: fast, scale: 1
            ),
            "a fast flick that actually travels commits"
        )
        XCTAssertFalse(
            ViewerGesture.shouldCommitDismiss(translation: slow, velocity: slow, scale: 1),
            "a small slow drag springs back"
        )
    }

    /// A short diagonal flick clears vertical dominance but is felt as a swipe,
    /// not as a dismiss.
    func testShortFlickDoesNotDismiss() {
        XCTAssertFalse(
            ViewerGesture.shouldCommitDismiss(
                translation: CGSize(width: 25, height: 40),
                velocity: CGSize(width: 0, height: 900),
                scale: 1
            ),
            "40pt of travel is a swipe, not a dismiss"
        )
    }

    /// A single threshold made a pinch hovering near it swap the KFImage URL
    /// repeatedly, each swap flashing the placeholder — what read as "jumping".
    func testOriginalTierHasHysteresis() {
        // Rising: both assertions must pass currentlyUsingOriginal: false, or
        // they take the exit branch and never exercise originalEnterScale at all.
        XCTAssertFalse(ViewerGesture.shouldUseOriginal(scale: 1.7, currentlyUsingOriginal: false))
        XCTAssertFalse(
            ViewerGesture.shouldUseOriginal(scale: 1.5, currentlyUsingOriginal: false),
            "between the two thresholds, a *rising* pinch must not switch yet"
        )
        XCTAssertTrue(ViewerGesture.shouldUseOriginal(scale: 1.9, currentlyUsingOriginal: false))

        // Falling: already on the original, it stays there between the two
        // thresholds instead of flipping back immediately.
        XCTAssertTrue(ViewerGesture.shouldUseOriginal(scale: 1.6, currentlyUsingOriginal: true))
        XCTAssertTrue(ViewerGesture.shouldUseOriginal(scale: 1.5, currentlyUsingOriginal: true))
        XCTAssertFalse(ViewerGesture.shouldUseOriginal(scale: 1.3, currentlyUsingOriginal: true))

        XCTAssertLessThan(
            ViewerGesture.originalExitScale,
            ViewerGesture.originalEnterScale,
            "without a gap there is no hysteresis at all"
        )
    }

    func testScaleClampAndDoubleTap() {
        XCTAssertEqual(ViewerGesture.clampScale(0.2), 1, "never below fit")
        XCTAssertEqual(ViewerGesture.clampScale(99), ViewerGesture.maxScale)
        XCTAssertEqual(ViewerGesture.scaleAfterDoubleTap(current: 1), ViewerGesture.doubleTapScale)
        XCTAssertEqual(ViewerGesture.scaleAfterDoubleTap(current: 3), 1, "double tap while zoomed fits")
    }
}

final class AutoAdvanceTests: XCTestCase {
    /// Wrapping means leaving a slideshow running never silently stops.
    /// An unbounded stream has no round to complete: running off the loaded end
    /// must wait for the next batch, not teleport back to sample #1.
    func testAdvanceDoesNotWrapWhenUnbounded() {
        XCTAssertNil(AutoAdvance.nextIndex(current: 29, count: 30, wraps: false))
        XCTAssertEqual(AutoAdvance.nextIndex(current: 28, count: 30, wraps: false), 29)
        XCTAssertNil(AutoAdvance.nextIndex(current: 99, count: 30, wraps: false),
                     "an out-of-range position must not restart the stream either")
    }

    func testAdvanceWraps() {
        XCTAssertEqual(AutoAdvance.nextIndex(current: 0, count: 3), 1)
        XCTAssertEqual(AutoAdvance.nextIndex(current: 2, count: 3), 0)
        XCTAssertEqual(AutoAdvance.nextIndex(current: 0, count: 1), 0)
    }

    func testAdvanceHandlesDegenerateInput() {
        XCTAssertNil(AutoAdvance.nextIndex(current: 0, count: 0))
        XCTAssertEqual(AutoAdvance.nextIndex(current: -1, count: 3), 0)
        XCTAssertEqual(AutoAdvance.nextIndex(current: 99, count: 3), 0)
    }
}

extension AutoAdvanceTests {
    private func item(video: Bool, duration: Double?) -> MediaItem {
        MediaItem(
            raw: .init(name: "x", path: "x", width: 1, height: 1, durationSec: duration),
            type: video ? .video : .image
        )
    }

    /// A 3s timer would tear a five-minute clip down three seconds in.
    func testVideoDwellsForItsDuration() {
        XCTAssertEqual(AutoAdvance.dwellTime(for: item(video: false, duration: nil), interval: 3), 3)
        XCTAssertEqual(AutoAdvance.dwellTime(for: item(video: true, duration: 300), interval: 3), 300)
        XCTAssertEqual(
            AutoAdvance.dwellTime(for: item(video: true, duration: nil), interval: 3), 3,
            "unknown duration falls back to the interval"
        )
        XCTAssertEqual(
            AutoAdvance.dwellTime(for: item(video: true, duration: 1), interval: 3), 3,
            "a clip shorter than the interval still gets the full interval"
        )
    }
}

/// The navigation mapping from docs/adr/0007 — which view each entry point
/// lands in. It is a table, it is easy to get subtly wrong, and getting it wrong
/// is invisible until someone notices they keep landing in the wrong view.
@MainActor
final class NavigatorTests: XCTestCase {
    func testDrillingInFromExploreStaysInExplore() {
        let nav = Navigator()
        nav.open(folder: "A", from: .explore)
        XCTAssertEqual(nav.routes, [Route(path: "A", view: .explore)])
    }

    /// A cell in the album view *is* an album; the only reason to open one is to
    /// look at what is inside it.
    func testDrillingInFromAlbumLandsInImage() {
        let nav = Navigator()
        nav.open(folder: "A/B", from: .album)
        XCTAssertEqual(nav.routes, [Route(path: "A/B", view: .image)])
    }

    func testJumpingToABranchLandsInAlbumAndResetsTheStack() {
        let nav = Navigator()
        nav.open(folder: "A", from: .explore)
        nav.open(folder: "A/B", from: .explore)

        nav.jump(to: "X/Y", hasChildren: true)
        XCTAssertEqual(nav.routes, [Route(path: "X/Y", view: .album)],
                       "a jump resets the stack so Back returns to the root")
    }

    func testJumpingToALeafLandsInImage() {
        let nav = Navigator()
        nav.jump(to: "X/Y", hasChildren: false)
        XCTAssertEqual(nav.routes, [Route(path: "X/Y", view: .image)])
    }

    func testJumpingToTheRootEmptiesTheStack() {
        let nav = Navigator()
        nav.open(folder: "A", from: .explore)
        nav.jump(to: "", hasChildren: true)

        XCTAssertTrue(nav.routes.isEmpty, "the root is the stack's root, not an entry in it")
        XCTAssertEqual(nav.rootView, .album)
        XCTAssertEqual(nav.currentPath, "")
    }

    /// An ancestor that is on the stack is popped to, keeping its own view.
    func testGoingToAnAncestorOnTheStackPops() {
        let nav = Navigator()
        nav.open(folder: "A", from: .explore)
        nav.open(folder: "A/B", from: .explore)
        nav.open(folder: "A/B/C", from: .explore)

        nav.goToAncestor(path: "A", hasChildren: true)
        XCTAssertEqual(nav.routes.map(\.path), ["A"])
        XCTAssertEqual(nav.routes.first?.view, .explore, "popping must not rewrite the view")
    }

    /// After a jump the stack holds one deep entry whose ancestors were never
    /// visited — those are exactly the crumbs the user wants, so they jump.
    func testGoingToAnAncestorNotOnTheStackJumps() {
        let nav = Navigator()
        nav.jump(to: "A/B/C", hasChildren: false)

        nav.goToAncestor(path: "A", hasChildren: true)
        XCTAssertEqual(nav.routes, [Route(path: "A", view: .album)])
    }

    func testCurrentPathFollowsTheTopOfTheStack() {
        let nav = Navigator()
        XCTAssertEqual(nav.currentPath, "")
        nav.open(folder: "A", from: .explore)
        XCTAssertEqual(nav.currentPath, "A")
    }
}

/// The leaf oracle. "No children in the tree" is what hides `explore` and
/// `album`, so a wrong answer either shows two dead tabs or hides two live ones.
final class FolderViewKindTests: XCTestCase {
    func testEveryViewIsOfferedWhenTheFolderHasSubfolders() {
        XCTAssertEqual(FolderViewKind.available(hasSubfolders: true), [.explore, .album, .image])
    }

    /// In a leaf, `album` is empty and `explore` is a duplicate of `image`.
    func testALeafOnlyOffersImage() {
        XCTAssertEqual(FolderViewKind.available(hasSubfolders: false), [.image])
    }
}

@MainActor
final class TreeStoreTests: XCTestCase {
    private func store(_ raw: [String: Any]) -> TreeStore {
        let tree = FolderTree(root: FolderTree.parse(raw, name: "", path: ""))
        return TreeStore(client: GalleryClient(baseURL: URL(string: "https://example.invalid")!), tree: tree)
    }

    func testBranchesAndLeavesAreToldApart() {
        let s = store(["A": ["B": [String: Any]()], "C": [String: Any]()])
        XCTAssertTrue(s.hasChildren(""), "the root has children")
        XCTAssertTrue(s.hasChildren("A"))
        XCTAssertFalse(s.hasChildren("A/B"), "a leaf has no children")
        XCTAssertFalse(s.hasChildren("C"))
    }

    /// Being wrong towards "it has children" shows two tabs that turn out empty;
    /// being wrong the other way hides views that exist. Default to the former.
    func testMissingTreeAssumesEverythingIsABranch() {
        let s = TreeStore(client: GalleryClient(baseURL: URL(string: "https://example.invalid")!))
        XCTAssertTrue(s.hasChildren("anything"))
    }

    func testRevealingAncestorsOpensEveryLevelButTheLeafItself() {
        let s = store([String: Any]())
        s.revealAncestors(of: "A/B/C")

        XCTAssertTrue(s.isExpanded("A"))
        XCTAssertTrue(s.isExpanded("A/B"))
        XCTAssertFalse(s.isExpanded("A/B/C"), "the destination itself need not be open")
    }

    func testCollapsingANodeCollapsesWhatWasOpenBeneathIt() {
        let s = store([String: Any]())
        s.revealAncestors(of: "A/B/C/D")
        XCTAssertTrue(s.isExpanded("A/B"))

        s.toggleExpansion("A")
        XCTAssertFalse(s.isExpanded("A"))
        XCTAssertFalse(s.isExpanded("A/B"), "re-opening A must not explode back to the old shape")
    }
}

@MainActor
final class WallColumnsTests: XCTestCase {
    func testCountIsClampedToTheRange() {
        let columns = WallColumns()
        columns.count = 0
        XCTAssertEqual(columns.count, WallColumns.minColumns)
        columns.count = 999
        XCTAssertEqual(columns.count, WallColumns.maxColumns)
    }

    /// Positive means "bigger pictures", which is fewer columns — the same
    /// direction a pinch means it.
    func testZoomingInReducesTheColumnCount() {
        let columns = WallColumns()
        columns.count = 3
        columns.zoom(1)
        XCTAssertEqual(columns.count, 2)
        columns.zoom(-1)
        XCTAssertEqual(columns.count, 3)
    }

    func testZoomingPastTheEndsIsANoOpRatherThanAnError() {
        let columns = WallColumns()
        columns.count = WallColumns.minColumns
        columns.zoom(5)
        XCTAssertEqual(columns.count, WallColumns.minColumns)
    }
}

/// What decides whether the chrome is on screen. It is fed by which cells are
/// visible rather than by a scroll offset — see ScrollIntent for why the offset
/// version had to go.
@MainActor
final class ScrollIntentTests: XCTestCase {
    func testChromeShowsAtTheTopAndOnTheWayUp() {
        let scroll = ScrollIntent()
        XCTAssertTrue(scroll.chromeVisible, "a folder that never scrolls must still show its chrome")

        scroll.report(firstVisibleIndex: 40)
        XCTAssertFalse(scroll.chromeVisible, "scrolling down gives the wall the screen")
        XCTAssertTrue(scroll.counterVisible)

        scroll.report(firstVisibleIndex: 30)
        XCTAssertTrue(scroll.chromeVisible, "scrolling up brings it back")
        XCTAssertFalse(scroll.counterVisible, "the two share the bottom edge and must not stack")
    }

    /// The same item reappearing must not read as movement — a lazy container
    /// fires onAppear/onDisappear in bursts around the render window's edge.
    func testRepeatingTheSameIndexIsNotMovement() {
        let scroll = ScrollIntent()
        scroll.report(firstVisibleIndex: 40)
        scroll.report(firstVisibleIndex: 30)
        XCTAssertTrue(scroll.chromeVisible)

        scroll.report(firstVisibleIndex: 30)
        XCTAssertTrue(scroll.chromeVisible, "a repeat is not a scroll down")
    }

    func testBackAtTheFirstItemCountsAsAtTop() {
        let scroll = ScrollIntent()
        scroll.report(firstVisibleIndex: 40)
        XCTAssertFalse(scroll.atTop)

        scroll.report(firstVisibleIndex: 0)
        XCTAssertTrue(scroll.atTop)
        XCTAssertTrue(scroll.chromeVisible)
    }

    func testResetBringsTheChromeBack() {
        let scroll = ScrollIntent()
        scroll.report(firstVisibleIndex: 40)
        XCTAssertFalse(scroll.chromeVisible)

        scroll.reset()
        XCTAssertTrue(scroll.chromeVisible, "the next screen must not inherit a hidden chrome")
    }
}

@MainActor
final class ViewerPresenterTests: XCTestCase {
    private func media(_ n: Int) -> [MediaItem] {
        (0..<n).map {
            MediaItem(
                raw: .init(name: "\($0)", path: "p/\($0)", width: 100, height: 200, durationSec: nil),
                type: .image
            )
        }
    }

    /// Growing the sequence must not look like a different presentation, or the
    /// player is torn down and rebuilt mid-swipe.
    func testGrowingTheSequenceKeepsTheSameIdentity() async {
        let presenter = ViewerPresenter()
        var pool = media(10)
        presenter.present(items: pool, startIndex: 3, extend: { pool })

        let before = presenter.context?.id
        pool = media(40)
        await presenter.requestMore()

        XCTAssertEqual(presenter.context?.items.count, 40)
        XCTAssertEqual(presenter.context?.id, before)
        XCTAssertEqual(presenter.context?.startIndex, 3)
    }

    func testRequestingMoreWithNothingNewLeavesTheContextAlone() async {
        let presenter = ViewerPresenter()
        let pool = media(10)
        presenter.present(items: pool, startIndex: 0, extend: { pool })

        await presenter.requestMore()
        XCTAssertEqual(presenter.context?.items.count, 10)
    }

    /// Clearing from the outside — the iOS cover's binding, a swipe-down — must
    /// not leave the old sequence's grow-closure for the next one to inherit.
    func testDismissingDropsTheGrowClosure() async {
        let presenter = ViewerPresenter()
        presenter.present(items: media(5), startIndex: 0, extend: { self.media(50) })
        presenter.context = nil

        presenter.present(items: media(5), startIndex: 0)
        await presenter.requestMore()
        XCTAssertEqual(presenter.context?.items.count, 5)
    }

    /// A batch can land after the user has already swiped the player away.
    /// Writing the grown sequence unconditionally there does not merely leak —
    /// it puts the player back on screen.
    func testABatchLandingAfterDismissDoesNotReopenThePlayer() async {
        let presenter = ViewerPresenter()
        let pool = media(40)
        presenter.present(items: media(5), startIndex: 0, unbounded: true, extend: { pool })

        // Dismiss while the batch is "in flight", then let it land.
        presenter.dismiss()
        await presenter.requestMore()

        XCTAssertNil(presenter.context, "the player came back from the dead")
    }

    /// And a batch belonging to a sequence the user has since navigated away
    /// from must not overwrite the one now on screen.
    func testAStaleBatchDoesNotOverwriteADifferentSequence() async {
        let presenter = ViewerPresenter()
        let firstPool = media(40)
        presenter.present(items: media(5), startIndex: 0, extend: { firstPool })

        let second = [
            MediaItem(
                raw: .init(name: "x", path: "other/x", width: 1, height: 1, durationSec: nil),
                type: .image
            )
        ]
        presenter.present(items: second, startIndex: 0)
        await presenter.requestMore()

        XCTAssertEqual(presenter.context?.items.count, 1)
        XCTAssertEqual(presenter.context?.items.first?.path, "other/x")
    }

    func testPresentingNothingDoesNotOpenThePlayer() {
        let presenter = ViewerPresenter()
        presenter.present(items: [], startIndex: 0)
        XCTAssertNil(presenter.context)
    }
}

final class MasonryAnchorTests: XCTestCase {
    private struct Item: Identifiable, Hashable {
        let id: Int
    }

    /// Changing the column count re-partitions everything, so the scroll offset
    /// is meaningless afterwards. The anchor is what keeps the wall still.
    func testAnchorIsTheEarliestVisibleItem() {
        let items = (0..<20).map(Item.init)
        // Visibility arrives in column order, not item order.
        let visible: Set<Int> = [11, 7, 9, 8]
        XCTAssertEqual(MasonryLayout.anchorID(items: items, visible: visible), 7)
    }

    func testAnchorIsNilWhenNothingVisible() {
        let items = (0..<5).map(Item.init)
        XCTAssertNil(MasonryLayout.anchorID(items: items, visible: []))
    }

    /// Spreading the fingers means bigger images, which is fewer columns.
    func testPinchMapsToColumnCount() {
        XCTAssertEqual(
            MasonryLayout.columnCount(base: 4, magnification: 2, current: 4, min: 1, max: 8), 2
        )
        XCTAssertEqual(
            MasonryLayout.columnCount(base: 4, magnification: 0.5, current: 4, min: 1, max: 8), 8
        )
        XCTAssertEqual(
            MasonryLayout.columnCount(base: 4, magnification: 1, current: 4, min: 1, max: 8), 4,
            "no magnification, no change"
        )
    }

    func testPinchRespectsRangeAndDegenerateInput() {
        XCTAssertEqual(
            MasonryLayout.columnCount(base: 4, magnification: 100, current: 4, min: 2, max: 8), 2
        )
        XCTAssertEqual(
            MasonryLayout.columnCount(base: 4, magnification: 0.001, current: 4, min: 1, max: 5), 5
        )
        XCTAssertEqual(
            MasonryLayout.columnCount(base: 3, magnification: 0, current: 3, min: 1, max: 8), 3,
            "a zero magnification must not divide by zero"
        )
    }

    /// Without hysteresis a finger hovering near the boundary flips the count
    /// back and forth, each flip re-partitioning the whole wall.
    func testColumnCountHasHysteresis() {
        // base 2 flips at magnification 1.333; jitter around it must not flip.
        for magnification in [1.30, 1.333, 1.36] {
            XCTAssertEqual(
                MasonryLayout.columnCount(
                    base: 2, magnification: magnification, current: 2, min: 1, max: 5
                ),
                2,
                "magnification \(magnification) is inside the dead zone"
            )
        }
        // A decisive spread still changes it.
        XCTAssertEqual(
            MasonryLayout.columnCount(base: 2, magnification: 2.0, current: 2, min: 1, max: 5), 1
        )
    }
}

/// The touch counting that tells a pinch from a tap. The E2E covers the gesture
/// it exists for; this covers the ordering that makes it work, which no gesture
/// can show from the outside.
@MainActor
final class MultiTouchTests: XCTestCase {
    /// The ordinary case: one finger, no reason to refuse anything.
    func testSingleTouchIsAlwaysATap() {
        let touch = MultiTouch()
        let now = Date()
        touch.report(touchCount: 1, now: now)
        XCTAssertTrue(touch.acceptsTap(now: now))
        touch.report(touchCount: 0, now: now)
        XCTAssertTrue(touch.acceptsTap(now: now))
    }

    /// The mechanism the whole thing turns on: a tap fires on touch-*up*, and
    /// the fingers of a pinch lift one at a time. The event that carries the
    /// first lift still carries both touches, which is what the guard sees —
    /// by the time SwiftUI runs the action there is only one finger left.
    func testTapIsRefusedAtTheLiftThatFiresIt() {
        let touch = MultiTouch()
        let start = Date()
        touch.report(touchCount: 1, now: start)
        touch.report(touchCount: 2, now: start)
        XCTAssertFalse(touch.acceptsTap(now: start), "two fingers are down")

        touch.report(touchCount: 2, now: start)
        XCTAssertFalse(touch.acceptsTap(now: start), "the lift that fires the tap")

        touch.report(touchCount: 1, now: start)
        XCTAssertFalse(touch.acceptsTap(now: start), "the last finger leaving")
    }

    /// And it lets go again, or the first tap after every pinch would be eaten.
    func testTapIsAcceptedOnceTheGracePeriodPasses() {
        let touch = MultiTouch()
        let start = Date()
        touch.report(touchCount: 2, now: start)

        let stillInside = start.addingTimeInterval(MultiTouch.graceAfterLift - 0.05)
        XCTAssertFalse(touch.acceptsTap(now: stillInside))

        let after = start.addingTimeInterval(MultiTouch.graceAfterLift + 0.05)
        XCTAssertTrue(touch.acceptsTap(now: after))
    }

    /// The reason this is a decaying timestamp and not a running count. Nothing
    /// says the watcher hears the end of every sequence it heard the start of —
    /// UIKit cancels touches, recognisers reset — and a count that missed one
    /// would sit at two and refuse every tap in the app from then on. That is
    /// what an intermittent "an ordinary tap no longer opens a cell" turned out
    /// to be.
    func testAMissedTouchUpCannotWedgeTapsForGood() {
        let touch = MultiTouch()
        let start = Date()
        touch.report(touchCount: 2, now: start)
        // ...and nothing ever reports the fingers leaving.
        XCTAssertTrue(
            touch.acceptsTap(now: start.addingTimeInterval(1)),
            "a lost touch-up must cost the grace period, not every tap after it"
        )
    }

    /// A long pinch must not go stale halfway through: the moves keep it fresh.
    func testALongPinchStaysRefusedThroughout() {
        let touch = MultiTouch()
        let start = Date()
        for step in 0...20 {
            let now = start.addingTimeInterval(Double(step) * 0.1)
            touch.report(touchCount: 2, now: now)
            XCTAssertFalse(touch.acceptsTap(now: now), "still pinching at \(step)")
        }
    }

    /// Where nothing reports touches — the desktop, or before the watcher
    /// reaches the window — the guard must cost nothing. A missing watcher may
    /// not eat taps.
    func testNoReportsMeansEveryTapGoesThrough() {
        XCTAssertTrue(MultiTouch().acceptsTap())
    }
}
