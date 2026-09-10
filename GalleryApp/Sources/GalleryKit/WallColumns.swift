import Foundation
import Observation

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

    var canZoomIn: Bool { count > Self.minColumns }
    var canZoomOut: Bool { count < Self.maxColumns }
}
