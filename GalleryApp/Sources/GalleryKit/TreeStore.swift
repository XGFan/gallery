import Foundation
import Observation

/// Holds the folder tree behind the navigation drawer / sidebar, plus its
/// expansion state.
///
/// This is a store rather than plain `@State` on the root view for one specific
/// reason. On iOS the tree is read *only* inside the drawer's content, which
/// SwiftUI does not evaluate while building the presenting view's body. A
/// `@State` mutation therefore produced an identical body, SwiftUI kept the
/// already-rendered content, and the drawer spun on its spinner forever even
/// though the fetch had long since succeeded. Observation tracks the read where
/// it actually happens, so the drawer refreshes itself.
///
/// It doubles as the leaf oracle for the view switcher — see `hasChildren`.
@Observable
@MainActor
final class TreeStore {
    private(set) var tree: FolderTree?
    private(set) var error: GalleryError?
    private var isLoading = false

    /// Paths that have at least one child in the tree. See `hasChildren`.
    private var branchPaths: Set<String> = []

    /// Which nodes the user has open. Auto-expansion to the current path adds to
    /// this rather than fighting it, so a manual collapse stays collapsed.
    private(set) var expanded: Set<String> = []

    private let client: GalleryClient

    /// `tree` is seeded only by tests. The leaf oracle below decides which views
    /// the switcher offers, so it is worth covering without a live backend.
    init(client: GalleryClient, tree: FolderTree? = nil) {
        self.client = client
        if let tree {
            self.tree = tree
            branchPaths = Self.collectBranchPaths(of: tree.root)
        }
    }

    /// The tree is small and changes only when the library is rescanned, so one
    /// fetch per launch is enough. A failed attempt leaves `tree` nil, which is
    /// what lets the error view's retry come back through here.
    func load() async {
        guard tree == nil, !isLoading else { return }
        isLoading = true
        // Owned by the store, not by the caller's task: SwiftUI cancels a
        // `.task` during view churn, and a cancelled fetch must not become an
        // error screen the sidebar never retries from. See FolderStore.
        await Task { await self.fetch() }.value
    }

    private func fetch() async {
        defer { isLoading = false }
        do {
            let loaded = try await client.tree()
            tree = loaded
            branchPaths = Self.collectBranchPaths(of: loaded.root)
            error = nil
        } catch let galleryError as GalleryError {
            error = galleryError
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = .badResponse
        }
    }

    // MARK: - Leaf oracle

    /// Whether this path has subfolders — which is exactly "the `album` view
    /// would be non-empty", and therefore what decides whether the switcher
    /// shows `explore` and `album` at all (docs/adr/0007).
    ///
    /// The equivalence holds because `ToTree()` only emits directories whose
    /// `Cover()` is non-empty, i.e. whose subtree holds media: a child in the
    /// tree guarantees a descendant that directly holds media, and no child
    /// guarantees none. So this answers precisely, with no extra request, what
    /// the web frontend has to guess at by counting slashes in keys.
    ///
    /// Defaults to `true` while the tree is missing. Being wrong in that
    /// direction shows two tabs that turn out empty; being wrong the other way
    /// hides views that exist, which is worse.
    func hasChildren(_ path: String) -> Bool {
        guard tree != nil else { return true }
        return branchPaths.contains(path)
    }

    private static func collectBranchPaths(of root: FolderTree.Node) -> Set<String> {
        var result: Set<String> = []
        func walk(_ node: FolderTree.Node) {
            if !node.children.isEmpty { result.insert(node.path) }
            for child in node.children { walk(child) }
        }
        walk(root)
        return result
    }

    // MARK: - Expansion

    func isExpanded(_ path: String) -> Bool { expanded.contains(path) }

    func toggleExpansion(_ path: String) {
        if expanded.contains(path) {
            // Collapsing a node collapses what was open beneath it, so
            // re-opening it does not explode back to a previous session's shape.
            expanded = expanded.filter { $0 != path && !$0.hasPrefix(path + "/") }
        } else {
            expanded.insert(path)
        }
    }

    /// Opens every ancestor of `path` so the current folder is visible in the
    /// tree without the user hunting for it. Additive on purpose — it never
    /// closes anything the user opened.
    func revealAncestors(of path: String) {
        guard !path.isEmpty else { return }
        var prefix = ""
        for segment in path.split(separator: "/").dropLast() {
            prefix = prefix.isEmpty ? String(segment) : prefix + "/" + segment
            expanded.insert(prefix)
        }
    }
}
