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

final class MediaOrderTests: XCTestCase {
    private func media(_ n: Int, videosEvery: Int = 0) -> [MediaItem] {
        (0..<n).map { index in
            let isVideo = videosEvery > 0 && index % videosEvery == 0
            return MediaItem(
                raw: .init(
                    name: "\(index)", path: "p/\(index)", width: 100, height: 200, durationSec: nil
                ),
                type: isVideo ? .video : .image
            )
        }
    }

    /// An unreproducible shuffle is untestable, hence the seed.
    func testShuffleIsDeterministicForASeed() {
        let items = media(50)
        XCTAssertEqual(
            MediaOrder.shuffled(items, seed: 42).map(\.id),
            MediaOrder.shuffled(items, seed: 42).map(\.id)
        )
        XCTAssertNotEqual(
            MediaOrder.shuffled(items, seed: 42).map(\.id),
            MediaOrder.shuffled(items, seed: 43).map(\.id)
        )
    }

    /// The property that actually matters: nothing is lost or duplicated.
    func testShuffleIsAPermutation() {
        let items = media(200)
        let shuffled = MediaOrder.shuffled(items, seed: 7)

        XCTAssertEqual(shuffled.count, items.count)
        XCTAssertEqual(Set(shuffled.map(\.id)), Set(items.map(\.id)))
        XCTAssertNotEqual(shuffled.map(\.id), items.map(\.id), "200 items should not shuffle to identity")
    }

    /// Isolated mode from a photo must never drop the user into a video.
    func testIsolatedSequenceKeepsEntryKind() {
        let items = media(30, videosEvery: 3)
        let photo = items.first { !$0.isVideo }!

        let (isolated, start) = MediaOrder.sequence(from: items, entry: photo, mixed: false, seed: 1)
        XCTAssertFalse(isolated.contains { $0.isVideo }, "isolated must not include the other kind")
        XCTAssertEqual(isolated[start].id, photo.id, "start index must point at the entry item")

        let (mixed, mixedStart) = MediaOrder.sequence(from: items, entry: photo, mixed: true, seed: 1)
        XCTAssertTrue(mixed.contains { $0.isVideo }, "mixed keeps both kinds")
        XCTAssertEqual(mixed[mixedStart].id, photo.id)
    }

    /// Shuffling the whole folder has no entry to match, so isolated means
    /// photos only.
    func testIsolatedWholeFolderDropsVideos() {
        let items = media(30, videosEvery: 3)
        let (isolated, _) = MediaOrder.sequence(from: items, entry: nil, mixed: false, seed: 5)
        XCTAssertFalse(isolated.isEmpty)
        XCTAssertFalse(isolated.contains { $0.isVideo })

        let (mixed, _) = MediaOrder.sequence(from: items, entry: nil, mixed: true, seed: 5)
        XCTAssertEqual(mixed.count, items.count)
    }

    func testUnseededSequenceKeepsOriginalOrder() {
        let items = media(10)
        let (ordered, _) = MediaOrder.sequence(from: items, entry: nil, mixed: true, seed: nil)
        XCTAssertEqual(ordered.map(\.id), items.map(\.id))
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
