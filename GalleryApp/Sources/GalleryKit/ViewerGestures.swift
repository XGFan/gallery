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

    /// Commit the dismiss on either a long enough drag or a fast enough flick.
    static func shouldCommitDismiss(translation: CGSize, velocity: CGSize, scale: CGFloat) -> Bool {
        guard isDismissDrag(translation: translation, scale: scale) else { return false }
        return translation.height > dismissDistanceThreshold
            || velocity.height > dismissVelocityThreshold
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

/// The two orthogonal dimensions of how a sequence is consumed (CONTEXT.md).
/// The swipe axis is deliberately *not* here — it is a fixed convention, not an
/// option. See docs/adr/0006.
struct ViewerOptions: Equatable, Sendable {
    var shuffled: Bool = false
    var autoAdvance: Bool = false
    var interval: TimeInterval = AutoAdvance.defaultInterval

    static let `default` = ViewerOptions()
}

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

    /// Advancing wraps: reaching the end continues from the start, so leaving a
    /// slideshow running never silently stops.
    static func nextIndex(current: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard current >= 0, current < count else { return 0 }
        return (current + 1) % count
    }
}
