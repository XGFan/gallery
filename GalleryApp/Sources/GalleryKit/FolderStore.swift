import Foundation
import Observation

/// Drives one folder screen.
///
/// A folder has three ways of being looked at (see CONTEXT.md and
/// docs/adr/0007): `explore`, `album`, `image`. They come from three different
/// endpoints, and only `image` is paged, because only it can run to six figures.
///
/// The view is handed in by the route, not read from a global preference. A
/// global one meant flipping it in one folder silently changed every other
/// folder in the app.
@Observable
@MainActor
final class FolderStore {
    static let pageSize = 150

    let path: String
    private let client: GalleryClient

    var view: FolderViewKind {
        didSet {
            guard view != oldValue else { return }
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
    /// Total in the `image` view; nil in the other two, which arrive whole.
    private(set) var total: Int?

    private var reachedEnd = false
    private var loadToken = 0

    init(path: String, view: FolderViewKind, client: GalleryClient) {
        self.path = path
        self.view = view
        self.client = client
    }

    var displayName: String {
        path.isEmpty ? "图库" : String(path.split(separator: "/").last ?? "")
    }

    /// True once every page has been fetched (or in the unpaged views, which
    /// arrive whole).
    var isComplete: Bool { reachedEnd }

    /// The media on the wall, in wall order. `album` yields none — it lists
    /// folders only.
    var mediaEntries: [MediaItem] {
        entries.compactMap { entry in
            if case .media(let m) = entry { return m }
            return nil
        }
    }

    /// The first page.
    ///
    /// The fetch runs in a Task the store owns rather than as a child of the
    /// caller's. `.task` is cancelled whenever SwiftUI tears the view's task
    /// down — which on macOS happens during `NavigationSplitView`'s startup
    /// churn, before the request finishes — and a cancelled URLSession task
    /// surfaced as `NSURLErrorCancelled`, which the wall then showed as a dead
    /// error screen it never retried from. An unstructured Task does not
    /// inherit cancellation, so the load survives the view's churn; awaiting it
    /// keeps the caller's semantics unchanged.
    func loadInitial() async {
        guard entries.isEmpty, !isLoading else { return }
        await Task { await self.reload() }.value
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

    /// Called as the wall approaches its end. No-ops in the unpaged views and
    /// once every page has landed.
    func loadMoreIfNeeded() async {
        guard view.isPaged, !reachedEnd, !isLoading, error == nil else { return }
        await loadNextPage(token: loadToken)
    }

    private func loadNextPage(token: Int) async {
        loadingToken = token
        defer { if loadingToken == token { loadingToken = nil } }

        do {
            switch view {
            case .image:
                let page = try await client.mediaPage(
                    path: path, offset: entries.count, limit: Self.pageSize
                )
                guard token == loadToken else { return }
                entries.append(contentsOf: page.items.map { WallEntry.media($0) })
                total = page.total
                // Trust the item count, not the total: a rescan between pages
                // could shift the total, and an empty page is the honest signal.
                reachedEnd = page.items.isEmpty || entries.count >= page.total
            case .explore:
                let shallow = try await client.explore(path: path)
                guard token == loadToken else { return }
                entries = shallow
                reachedEnd = true
            case .album:
                let albums = try await client.album(path: path)
                guard token == loadToken else { return }
                entries = albums
                reachedEnd = true
            }
        } catch let galleryError as GalleryError {
            guard token == loadToken else { return }
            error = galleryError
        } catch is CancellationError {
            // Nobody is waiting for this answer any more. Reporting it would
            // put an error screen in front of the user for something they never
            // did, and the wall would sit there refusing to fetch again.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // The same thing, reported by URLSession instead of by Swift
            // concurrency.
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
