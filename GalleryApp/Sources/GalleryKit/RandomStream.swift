import Foundation
import Observation

/// Whether `random` mixes photos and videos, or stays with photos only.
///
/// The only thing this decides any more is the `type` query parameter — see
/// CONTEXT.md. There is deliberately no UI for it in the client; it exists as a
/// stored value so the behaviour can be pinned (including from a test's
/// launch arguments).
enum MixedModePreference {
    private static let key = "viewer.mixedMode"

    /// Defaults to mixed, matching the web frontend's default.
    static func load() -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static func store(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// The sequence behind the `random` action.
///
/// **Not a shuffled list.** It is an unbounded sample stream: the backend picks
/// items, batches can repeat, and there is no total and no "one full round".
/// See docs/adr/0008 — that is what buys instant start and memory that does not
/// depend on folder size (the root folder holds 100k items).
///
/// It replaced a client-side shuffle that could only ever reorder the pages that
/// happened to be loaded — which in a big folder meant "random" reshuffled 150
/// path-adjacent items from a single album.
@Observable
@MainActor
final class RandomStream {
    /// How many items one request asks for. Big enough that swiping does not
    /// outrun the network, small enough to start instantly.
    static let batchSize = 30
    /// Fetch the next batch once this few unseen items remain ahead.
    static let refillMargin = 10
    /// A batch this size or larger is capped by the backend; kept in sync with
    /// the server's own limit so the two never silently disagree.
    static let maxBatchSize = 100

    let path: String
    private let client: GalleryClient
    private let includeVideo: Bool

    private(set) var items: [MediaItem] = []
    private(set) var error: GalleryError?
    private var isLoading = false
    /// Set once the backend answers a batch with nothing: an empty folder must
    /// stop the stream rather than let it retry forever as the user swipes.
    private(set) var isExhausted = false

    init(path: String, client: GalleryClient, includeVideo: Bool = MixedModePreference.load()) {
        self.path = path
        self.client = client
        self.includeVideo = includeVideo
    }

    /// Fetches the opening batch. Returns false when the folder yields nothing,
    /// so the caller can decline to open an empty viewer.
    func start() async -> Bool {
        guard items.isEmpty else { return !items.isEmpty }
        await fetchBatch()
        return !items.isEmpty
    }

    /// Called as the viewer nears the end of what has been fetched. Unlike a
    /// paged folder there is no end to reach — this just keeps the runway ahead
    /// of the user.
    func extendIfNeeded() async {
        guard !isExhausted, !isLoading, error == nil else { return }
        await fetchBatch()
    }

    /// Clears a failed batch and tries once more. Same reasoning as
    /// `FolderStore.retry`: the stream must stop asking on its own after a
    /// failure, but the user needs a way back.
    func retry() async {
        guard error != nil else { return }
        error = nil
        await fetchBatch()
    }

    private func fetchBatch() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let batch = try await client.random(
                path: path, includeVideo: includeVideo, count: Self.batchSize
            )
            if batch.isEmpty {
                isExhausted = true
                return
            }
            items.append(contentsOf: batch)
            error = nil
        } catch let galleryError as GalleryError {
            error = galleryError
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = .badResponse
        }
    }
}
