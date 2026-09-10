import Foundation
import Observation

/// The navigation stack, plus the one thing the tree needs to know: where the
/// user currently is.
///
/// Kept as a model rather than as `@State` on the root view because two
/// separate places drive it — the wall (drilling in) and the sidebar (jumping)
/// — and the sidebar lives far from the stack.
///
/// Every entry point declares which view it lands in. The mapping is the table
/// in docs/adr/0007; the methods below are that table in code. The root screen
/// is not part of `routes` — a NavigationStack's root never is — and it opens
/// in `album` (`RootView`); going back to it keeps whatever view it has.
@Observable
@MainActor
final class Navigator {
    var routes: [Route] = []

    /// The folder on screen. The sidebar highlights it among its siblings.
    var currentPath: String { routes.last?.path ?? "" }

    /// Drilling into a folder from a wall.
    ///
    /// `explore` continues to `explore` — the user is walking the tree level by
    /// level. `album` goes to `image`, because a cell in the album view *is* an
    /// album and the only reason to open one is to look at what is in it.
    func open(folder path: String, from view: FolderViewKind) {
        switch view {
        case .explore: routes.append(Route(path: path, view: .explore))
        case .album, .image: routes.append(Route(path: path, view: .image))
        }
    }

    /// Jumping from the sidebar.
    ///
    /// An ancestor that is on the stack is popped to, keeping its own view and
    /// scroll position — the sidebar's header is the way back up, and going up
    /// should feel like Back, not like a fresh arrival. Anything else resets the
    /// stack to a single entry so Back returns to the root rather than replaying
    /// the jump. A node with subfolders lands in `album` (show me what is under
    /// here); a leaf lands in `image` (there is nothing under here, show me the
    /// pictures).
    func jump(to path: String, hasChildren: Bool) {
        if path.isEmpty {
            routes = []
            return
        }
        if let index = routes.firstIndex(where: { $0.path == path }) {
            routes.removeSubrange((index + 1)...)
            return
        }
        routes = [Route(path: path, view: hasChildren ? .album : .image)]
    }
}
