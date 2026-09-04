import Foundation
import Observation

/// Drives one folder screen.
///
/// A folder has exactly two ways of being looked at (see CONTEXT.md): the
/// **shallow view** (this level's children, folders included) and the
/// **recursive view** (every descendant medium, flattened). They are one toggle,
/// not two modes — but they come from different endpoints, and only the
/// recursive one is paged, because only it can run to six figures.
@Observable
@MainActor
final class FolderStore {
    static let pageSize = 150

    let path: String
    private let client: GalleryClient

    var recursive: Bool {
        didSet {
            guard recursive != oldValue else { return }
            RecursivePreference.store(recursive)
            Task { await reload() }
        }
    }

    private(set) var entries: [WallEntry] = []
    private(set) var error: GalleryError?

    /// Which load is in flight, rather than a bare Bool. A superseded load's
    /// `defer` must not clear the flag for the load that replaced it — that
    /// window let the wall fire another fetch at the same offset and append
    /// every item twice.
    private var loadingToken: Int?
    var isLoading: Bool { loadingToken != nil }
    /// Total in the recursive view; nil in the shallow view, which is never paged.
    private(set) var total: Int?

    private var reachedEnd = false
    private var loadToken = 0

    init(path: String, client: GalleryClient, recursive: Bool = RecursivePreference.load()) {
        self.path = path
        self.client = client
        self.recursive = recursive
    }

    var displayName: String {
        path.isEmpty ? "图库" : String(path.split(separator: "/").last ?? "")
    }

    /// True once every page has been fetched (or in the shallow view, which
    /// arrives whole).
    var isComplete: Bool { reachedEnd }

    func loadInitial() async {
        guard entries.isEmpty, !isLoading else { return }
        await reload()
    }

    func reload() async {
        loadToken += 1
        let token = loadToken
        entries = []
        total = nil
        reachedEnd = false
        error = nil
        await loadNextPage(token: token)
    }

    /// Called as the wall approaches its end. No-ops in the shallow view and
    /// once every page has landed.
    func loadMoreIfNeeded() async {
        guard recursive, !reachedEnd, !isLoading, error == nil else { return }
        await loadNextPage(token: loadToken)
    }

    private func loadNextPage(token: Int) async {
        loadingToken = token
        defer { if loadingToken == token { loadingToken = nil } }

        do {
            if recursive {
                let page = try await client.mediaPage(
                    path: path, offset: entries.count, limit: Self.pageSize
                )
                guard token == loadToken else { return }
                entries.append(contentsOf: page.items.map { WallEntry.media($0) })
                total = page.total
                // Trust the item count, not the total: a rescan between pages
                // could shift the total, and an empty page is the honest signal.
                reachedEnd = page.items.isEmpty || entries.count >= page.total
            } else {
                let shallow = try await client.explore(path: path)
                guard token == loadToken else { return }
                entries = shallow
                reachedEnd = true
            }
        } catch let galleryError as GalleryError {
            guard token == loadToken else { return }
            error = galleryError
        } catch {
            guard token == loadToken else { return }
            self.error = .badResponse
        }
    }

    /// Clears a page error and tries again. Deliberately separate from
    /// `loadMoreIfNeeded`: after a failure the wall must stop asking on its own
    /// (or a dead network becomes a fetch loop), but the user must still have a
    /// way back — otherwise a blip on page 3 leaves a wall that silently never
    /// grows again.
    func retry() async {
        guard error != nil else { return }
        error = nil
        if entries.isEmpty {
            await reload()
        } else {
            await loadNextPage(token: loadToken)
        }
    }
}

/// The recursive toggle is a viewing habit, so it persists across launches.
enum RecursivePreference {
    private static let key = "folder.recursive"

    static func load() -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func store(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
