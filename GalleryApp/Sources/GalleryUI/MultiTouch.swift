import Foundation
#if os(iOS)
import SwiftUI
import UIKit
#endif

/// How many fingers are on the screen, so a tap can tell whether it is one.
///
/// SwiftUI's tap has no idea, and a `Button` fires on the lift of the first
/// finger of a two-finger touch like any other. `.simultaneousGesture` — which
/// the wall's pinch has to use so it does not fight the scroll view's pan — is
/// by definition the modifier that does not make the other gestures fail, so
/// nothing anywhere said no: a pinch resized the wall *and* opened the album the
/// still finger was resting on.
///
/// Counting touches is the only signal that separates the two. Movement is not:
/// a real hand does not move both fingers, one stays put and the other does the
/// work, and the still one is an ordinary press as far as the cell underneath is
/// concerned. `testPinchingTheWallDoesNotOpenACell` is the reproduction, and it
/// took a hand-built event stream to get one — see StaggeredTouch.
///
/// Only the wall needs this. The player's tap looked like the same defect but is
/// not: its single tap already has to wait for the double-tap to fail, and the
/// same two-finger gesture never flipped its chrome.
///
/// A singleton for the same reason `WallColumns` is one: this is a property of
/// the screen, not of any particular view, and the one thing that can observe it
/// is a recogniser on the window.
@MainActor
final class MultiTouch {
    static let shared = MultiTouch()

    /// How long after a second finger was last on the screen a tap is still
    /// refused.
    ///
    /// The grace period is the whole point. A tap fires on touch-*up*, and the
    /// fingers of a pinch lift one at a time — the first lift is what SwiftUI
    /// turns into a tap, and by then only one finger is left. Anything deciding
    /// on "are two fingers down right now" would wave through exactly the tap
    /// this exists to swallow.
    static let graceAfterLift: TimeInterval = 0.35

    /// When two or more fingers were last seen together.
    ///
    /// A decaying timestamp rather than a running count, and that is not a
    /// detail. The first version kept a count and cleared it on touch-up: it
    /// only takes one missed end — a sequence UIKit cancels, a recogniser reset
    /// that arrives out of order — for the count to stick at two and refuse
    /// *every* tap in the app from then on. That is not theoretical; it showed
    /// up as an intermittent "an ordinary tap no longer opens a cell" a full
    /// second after the gesture was over. A timestamp cannot get stuck: the
    /// worst a lost event costs is 0.35s.
    private var lastMultiTouch: Date?
    private var isInstalled = false

    /// Whether a tap happening now came from a single finger.
    ///
    /// Always true where nothing reports touches — the desktop, or before the
    /// watcher is on the window. A missing watcher must cost the guard, never
    /// the tap.
    func acceptsTap(now: Date = Date()) -> Bool {
        guard let last = lastMultiTouch else { return true }
        return now.timeIntervalSince(last) >= Self.graceAfterLift
    }

    /// Fed by the window-wide watcher on every touch event.
    ///
    /// `touchCount` counts the touches the event carries, the ones ending in it
    /// included: at the lift that fires the tap, the leaving finger and the one
    /// still down are both still in the event, and that is the moment the guard
    /// has to notice.
    func report(touchCount: Int, now: Date = Date()) {
        guard touchCount >= 2 else { return }
        lastMultiTouch = now
    }
}

#if os(iOS)
extension MultiTouch {
    /// Puts the watcher on the window. Idempotent: the app has one window, and
    /// a second watcher would report the same touches twice.
    func install(on window: UIWindow) {
        guard !isInstalled else { return }
        isInstalled = true
        window.addGestureRecognizer(TouchWatcher())
    }
}

/// Counts the fingers on screen without taking part in recognition.
///
/// It never leaves `.possible`, so it can neither win an arbitration nor make
/// another recogniser lose one — and `canPrevent`/`canBePrevented` say so
/// outright rather than relying on that.
///
/// Moves are watched as well as begins and ends: a pinch can easily last longer
/// than the grace period, and without them a slow one would go stale halfway
/// through and stop being recognised as two fingers.
private final class TouchWatcher: UIGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    convenience init() {
        self.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        report(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        report(event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        report(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        report(event)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    /// Every touch the event carries, not only the ones still down: see
    /// `MultiTouch.report(touchCount:now:)`.
    private func report(_ event: UIEvent) {
        MultiTouch.shared.report(touchCount: event.allTouches?.count ?? 0)
    }
}

/// Installs the watcher as soon as there is a window to put it on.
///
/// A representable rather than reaching into `UIApplication.connectedScenes` at
/// `onAppear`: the window is reachable here by construction, with no guessing
/// about which scene is key or whether one exists yet.
struct MultiTouchInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { InstallerView() }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            MultiTouch.shared.install(on: window)
        }
    }
}
#endif
