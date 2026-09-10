import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

/// How many columns the wall is showing.
///
/// App-wide rather than per-folder-screen, for one reason: the menu bar. The
/// toolbar's ±' buttons are gone (gestures and shortcuts only), and a menu
/// command has no way to reach a particular screen's `@State`. A single shared
/// value is also what the user means — "make the pictures bigger" is a setting,
/// not a property of the folder they happen to be in.
///
/// A singleton is the pragmatic shape here: this app has exactly one window, and
/// `.commands` in the `App` scene has nothing else to talk to.
@Observable
@MainActor
final class WallColumns {
    static let shared = WallColumns()

    static let minColumns = 1
    #if os(macOS)
    static let maxColumns = 8
    static let defaultColumns = 5
    #else
    static let maxColumns = 5
    static let defaultColumns = 2
    #endif

    static let range = minColumns...maxColumns

    private static let key = "wall.columns"

    var count: Int {
        didSet {
            let clamped = Swift.min(Swift.max(count, Self.minColumns), Self.maxColumns)
            if clamped != count {
                count = clamped
                return
            }
            guard clamped != oldValue else { return }
            UserDefaults.standard.set(clamped, forKey: Self.key)
        }
    }

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.key)
        count = Self.range.contains(stored) ? stored : Self.defaultColumns
    }

    /// Positive means "bigger pictures", which is *fewer* columns — the same
    /// direction a pinch means it.
    func zoom(_ steps: Int) {
        count = Swift.min(Swift.max(count - steps, Self.minColumns), Self.maxColumns)
    }

    #if os(macOS)
    // MARK: - ⌘ + scroll wheel

    private static var scrollZoomInstalled = false

    /// Installs the ⌘ + wheel handler once per process.
    ///
    /// Deliberately not per-view and not per-window. A local event monitor is
    /// app-global, so one installed by each `RootView` would step the column
    /// count once per live monitor — and `WindowGroup` hands out a second
    /// window for ⌘N, which would silently double every notch. Installed once
    /// and never removed: it costs nothing when ⌘ is not held, and the only
    /// thing that could remove it is the process exiting anyway.
    static func installScrollZoom() {
        guard !scrollZoomInstalled else { return }
        scrollZoomInstalled = true

        var accumulated: CGFloat = 0
        // A trackpad reports many small deltas per gesture and a mouse wheel one
        // big one per notch; accumulating to a threshold makes both feel like
        // discrete steps instead of a slider.
        let threshold: CGFloat = 6

        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            accumulated += event.scrollingDeltaY
            while abs(accumulated) >= threshold {
                let direction = accumulated > 0 ? 1 : -1
                MainActor.assumeIsolated { WallColumns.shared.zoom(direction) }
                accumulated -= CGFloat(direction) * threshold
            }
            // Swallowed: letting it through would scroll the wall at the same
            // time as resizing it.
            return nil
        }
    }
    #endif
}
