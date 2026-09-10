import Foundation
import Observation

/// What the full-screen player is showing.
///
/// Identifiable only — hashing a value carrying the whole media array is a
/// footgun, and `fullScreenCover(item:)` never needs it.
struct ViewerContext: Identifiable {
    let items: [MediaItem]
    let startIndex: Int
    /// The folder's real total when it exceeds what has been loaded. nil when
    /// the loaded items are all there is.
    var totalCount: Int?
    /// A `random` stream has no end and no total, so the counter shows only the
    /// position. See docs/adr/0008.
    var unbounded: Bool = false

    /// Stable across a sequence that grows underneath it: appending later items
    /// must not look like a different presentation, or the player would be torn
    /// down and rebuilt mid-swipe.
    var id: String {
        (items.indices.contains(startIndex) ? items[startIndex].path : "") + "@\(startIndex)"
    }
}

/// Owns the player's presentation, one level above the folder screens.
///
/// It sits this high for a macOS reason: the player has to cover the *whole
/// window*, sidebar included (docs/adr/0007 — it used to be a sheet, which read
/// as a dialog). A folder screen lives inside the split view's detail column, so
/// an overlay it puts up can only ever cover the right-hand half.
///
/// It also owns growing the sequence, because the two sources grow differently:
/// a paged folder runs out, a random stream never does.
@Observable
@MainActor
final class ViewerPresenter {
    var context: ViewerContext? {
        didSet {
            // Clearing the context from the outside (the iOS cover's binding,
            // a swipe-down dismiss) must not leave the previous sequence's
            // grow-closure behind for the next one to inherit.
            if context == nil { extend = nil }
        }
    }

    /// Returns the grown item list, or nil when there is nothing more.
    private var extend: (() async -> [MediaItem]?)?

    func present(
        items: [MediaItem],
        startIndex: Int,
        totalCount: Int? = nil,
        unbounded: Bool = false,
        extend: (() async -> [MediaItem]?)? = nil
    ) {
        guard !items.isEmpty else { return }
        self.extend = extend
        context = ViewerContext(
            items: items,
            startIndex: startIndex,
            totalCount: totalCount,
            unbounded: unbounded
        )
    }

    /// Called as the player nears the end of what it holds. Without it the
    /// sequence dead-ends at whatever happened to be loaded when it opened.
    func requestMore() async {
        guard let extend, let current = context else { return }
        guard let grown = await extend(), grown.count > current.items.count else { return }
        // Re-check after the await. A batch can land after the user has already
        // swiped the player away, and writing unconditionally there does not
        // just leak — it puts the player back on screen. Matching the id as well
        // as non-nil covers the case where a *different* sequence was opened
        // while this one's batch was in flight.
        guard let latest = context, latest.id == current.id else { return }
        // Only the items change: re-using the start index keeps `id` stable, so
        // the presentation is updated rather than replaced.
        context = ViewerContext(
            items: grown,
            startIndex: latest.startIndex,
            totalCount: latest.totalCount,
            unbounded: latest.unbounded
        )
    }

    func dismiss() {
        context = nil
    }
}
