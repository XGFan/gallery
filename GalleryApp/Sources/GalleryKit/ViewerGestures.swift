import CoreGraphics
import Foundation

/// Gesture arbitration for the full-screen viewer.
///
/// Pure on purpose: these are the decisions that went wrong on device (swipes
/// dropping, zoom juddering) and they are impossible to test through the UI.
enum ViewerGesture {
    /// Below this the image is considered "not zoomed". Not exactly 1.0 because
    /// a pinch that ends a hair above 1 should still behave as un-zoomed.
    static let zoomEpsilon: CGFloat = 1.01

    static func isZoomed(_ scale: CGFloat) -> Bool { scale > zoomEpsilon }

    /// Panning is only meaningful once the image is larger than the screen.
    /// While un-zoomed the horizontal drag belongs to the pager and the vertical
    /// drag belongs to dismiss — so the pan gesture must not be attached at all.
    static func allowsPan(scale: CGFloat) -> Bool { isZoomed(scale) }

    /// A drag counts as a dismiss attempt only when it is clearly downward.
    /// Requiring vertical dominance keeps a slightly-off horizontal swipe from
    /// being stolen from the pager — the cause of "swiping left/right sometimes
    /// does nothing".
    static func isDismissDrag(translation: CGSize, scale: CGFloat) -> Bool {
        guard !isZoomed(scale) else { return false }
        guard translation.height > 0 else { return false }
        return translation.height > abs(translation.width) * verticalDominance
    }

    /// How much more vertical than horizontal a drag must be to read as dismiss.
    static let verticalDominance: CGFloat = 1.5

    static let dismissDistanceThreshold: CGFloat = 120
    static let dismissVelocityThreshold: CGFloat = 800
    /// Even a fast flick must travel this far. Without it a short diagonal flick
    /// (25pt across, 40pt down) clears vertical dominance and closes the viewer
    /// on what the user experienced as a swipe.
    static let dismissMinimumTravel: CGFloat = 60

    /// Commit the dismiss on either a long enough drag or a fast enough flick.
    static func shouldCommitDismiss(translation: CGSize, velocity: CGSize, scale: CGFloat) -> Bool {
        guard isDismissDrag(translation: translation, scale: scale) else { return false }
        if translation.height > dismissDistanceThreshold { return true }
        return velocity.height > dismissVelocityThreshold
            && translation.height > dismissMinimumTravel
    }

    /// Visual feedback while dragging to dismiss: 1 → 0 as the drag progresses.
    static func dismissProgress(translation: CGSize) -> CGFloat {
        guard translation.height > 0 else { return 0 }
        return min(translation.height / (dismissDistanceThreshold * 2), 1)
    }

    // MARK: - Image tier

    /// Enter the original above this magnification…
    static let originalEnterScale: CGFloat = 1.8
    /// …and fall back to the cheaper tier only below this one.
    ///
    /// The gap is deliberate. With a single threshold, a pinch that hovers around
    /// it swaps the KFImage's URL repeatedly — each swap tears the view down and
    /// re-enters the placeholder, which is what reads as the picture "jumping".
    static let originalExitScale: CGFloat = 1.4

    static func shouldUseOriginal(scale: CGFloat, currentlyUsingOriginal: Bool) -> Bool {
        currentlyUsingOriginal ? scale > originalExitScale : scale > originalEnterScale
    }

    // MARK: - Zoom

    static let maxScale: CGFloat = 6
    static let doubleTapScale: CGFloat = 2.5

    static func clampScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, 1), maxScale)
    }

    /// Double tap toggles between fit and a fixed magnification.
    static func scaleAfterDoubleTap(current: CGFloat) -> CGFloat {
        isZoomed(current) ? 1 : doubleTapScale
    }
}

/// The player's one adjustable dimension (CONTEXT.md). The swipe axis is
/// deliberately not an option — it is a fixed convention, see docs/adr/0006 —
/// and neither is the order: since docs/adr/0008 the player simply plays the
/// sequence it is handed and does not know or care where it came from.
enum AutoAdvance {
    static let defaultInterval: TimeInterval = 3
    static let intervalChoices: [TimeInterval] = [2, 3, 5, 8, 15]

    private static let intervalKey = "viewer.autoAdvanceInterval"
    private static let enabledKey = "viewer.autoAdvance"

    static func loadInterval() -> TimeInterval {
        let stored = UserDefaults.standard.double(forKey: intervalKey)
        return intervalChoices.contains(stored) ? stored : defaultInterval
    }

    static func storeInterval(_ value: TimeInterval) {
        UserDefaults.standard.set(value, forKey: intervalKey)
    }

    static func loadEnabled() -> Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static func storeEnabled(_ value: Bool) { UserDefaults.standard.set(value, forKey: enabledKey) }

    /// How long to dwell on an item before advancing.
    ///
    /// A video is given its full duration: a 3-second timer would tear down a
    /// five-minute clip three seconds in, killing playback and the connection.
    /// The chosen rule is "photos use the interval, videos play to the end",
    /// falling back to the interval when the duration is unknown.
    static func dwellTime(for item: MediaItem, interval: TimeInterval) -> TimeInterval {
        guard item.isVideo else { return interval }
        guard let duration = item.durationSec, duration > 0 else { return interval }
        return Swift.max(interval, duration)
    }

    /// Advancing wraps in a bounded sequence: reaching the end continues from
    /// the start, so leaving a slideshow running never silently stops.
    ///
    /// An unbounded one must not wrap. A `random` stream has no "round" to
    /// complete (docs/adr/0008) — wrapping there would teleport back to sample
    /// #1 whenever the next batch had not landed yet, inventing exactly the
    /// cycle that ADR says does not exist. Waiting in place is right: the batch
    /// is already on its way.
    static func nextIndex(current: Int, count: Int, wraps: Bool = true) -> Int? {
        guard count > 0 else { return nil }
        guard current >= 0, current < count else { return wraps ? 0 : nil }
        guard current + 1 < count else { return wraps ? 0 : nil }
        return current + 1
    }
}
