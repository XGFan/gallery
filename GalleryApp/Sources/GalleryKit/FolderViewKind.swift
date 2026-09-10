import Foundation

/// The three ways a folder can be looked at.
///
/// The names are the web frontend's own — one vocabulary across both frontends,
/// deliberately not translated into a parallel set of terms. See CONTEXT.md and
/// docs/adr/0007.
///
/// They are two dimensions, not three modes: **是否递归 × 列文件夹还是列媒体**.
/// `album` is the one that is easy to misread — it is *recursive*, not
/// "explore without the media".
enum FolderViewKind: String, Hashable, Sendable, CaseIterable {
    /// This folder's direct children: subfolders and this level's media, mixed.
    case explore
    /// Every descendant folder that directly holds media, flattened. Recursive.
    case album
    /// Every descendant medium, flattened. Recursive.
    case image

    /// Views that say nothing in a leaf folder: `album` comes back empty and
    /// `explore` shows exactly what `image` shows. Hidden there — see
    /// docs/adr/0007.
    var needsSubfolders: Bool {
        switch self {
        case .explore, .album: true
        case .image: false
        }
    }

    /// Only `image` can run to six figures, so only `image` is paged.
    var isPaged: Bool { self == .image }

    /// Which views the switcher offers for a folder.
    ///
    /// In a leaf folder `album` comes back empty and `explore` shows exactly
    /// what `image` shows, so both are hidden — the same thing the web frontend
    /// does, only decided exactly rather than by counting slashes in keys.
    /// See docs/adr/0007.
    static func available(hasSubfolders: Bool) -> [FolderViewKind] {
        allCases.filter { !$0.needsSubfolders || hasSubfolders }
    }
}

/// Where a folder screen sits: a path plus which of the three views it shows.
///
/// The view travels with the route rather than living in a global preference.
/// That is the whole point — a global toggle meant flipping it in one folder
/// silently changed every other one. docs/adr/0007 carries the mapping for
/// every navigation entry point.
struct Route: Hashable, Sendable {
    let path: String
    let view: FolderViewKind

    init(path: String, view: FolderViewKind) {
        self.path = path
        self.view = view
    }
}
