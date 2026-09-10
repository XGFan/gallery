import Foundation
import Observation

/// The navigation stack, plus the one thing the tree needs to know: where the
/// user currently is.
///
/// Kept as a model rather than as `@State` on the root view because three
/// separate places drive it — the wall (drilling in), the tree (jumping), and
/// the path sheet (jumping up) — and two of them live far from the stack.
///
/// Every entry point declares which view it lands in. The mapping is the table
/// in docs/adr/0007; the methods below are that table in code.
@Observable
@MainActor
final class Navigator {
    /// The root screen is not part of `routes` — a NavigationStack's root never
    /// is — so its view lives here.
    var rootView: FolderViewKind = .album
    var routes: [Route] = []

    /// The folder on screen. The tree highlights it and expands to reveal it.
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

    /// Jumping from the tree or the path sheet.
    ///
    /// The stack is reset to a single entry so Back returns to the root rather
    /// than replaying the jump. A node with subfolders lands in `album` (show me
    /// what is under here); a leaf lands in `image` (there is nothing under
    /// here, show me the pictures).
    func jump(to path: String, hasChildren: Bool) {
        let view: FolderViewKind = hasChildren ? .album : .image
        if path.isEmpty {
            rootView = view
            routes = []
        } else {
            routes = [Route(path: path, view: view)]
        }
    }

    /// Going to an ancestor from the path sheet.
    ///
    /// The crumbs are derived from the current folder's path, which is not the
    /// same thing as the stack: after a jump the stack holds one deep entry
    /// whose ancestors were never visited. So an ancestor that *is* on the stack
    /// is popped to (keeping its own view and scroll position), and one that is
    /// not is jumped to like any other jump.
    func goToAncestor(path: String, hasChildren: Bool) {
        if path.isEmpty, routes.isEmpty { return }
        if path.isEmpty {
            routes = []
            return
        }
        guard let index = routes.firstIndex(where: { $0.path == path }) else {
            jump(to: path, hasChildren: hasChildren)
            return
        }
        routes.removeSubrange((index + 1)...)
    }
}
