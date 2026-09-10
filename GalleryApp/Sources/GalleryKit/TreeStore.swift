import Foundation
import Observation

/// Holds the folder tree behind the navigation drawer / sidebar.
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

    // MARK: - Levels

    /// The subfolders of `path`, in the tree's own order — one level of the
    /// sidebar (docs/adr/0010). Empty while the tree is missing, and empty for a
    /// path the tree does not hold: a folder with no media anywhere beneath it
    /// is reachable through `explore` but is not in the tree (see `hasChildren`).
    func children(of path: String) -> [FolderTree.Node] {
        guard let tree else { return [] }
        var node = tree.root
        for segment in path.split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == segment }) else { return [] }
            node = next
        }
        return node.children
    }

    /// The folder above `path`. The root's parent is the root itself, which is
    /// what lets "the level that holds the current folder" be asked of any path.
    static func parentPath(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }
}
