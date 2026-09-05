import Foundation

/// One viewable thing in the library: an image or a video.
///
/// Mirrors the backend's paged `MediaItem`. The backend merges images and videos
/// into a single path-sorted sequence precisely so the client can render them
/// into one wall — see `docs/api_endpoints.md` §2.3.1.
struct MediaItem: Decodable, Identifiable, Hashable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case image
        case video
    }

    let type: Kind
    let name: String
    let path: String
    let width: Int
    let height: Int
    let durationSec: Double?

    var id: String { path }
    var isVideo: Bool { type == .video }

    /// Sizes are decoded leniently on purpose.
    ///
    /// The backend tags `Size` with `omitempty`, which *does* apply to `int` —
    /// so a medium whose size probe has not run yet (freshly scanned, or a video
    /// whose ffprobe failed) serialises with no `width`/`height` at all. Making
    /// them required would fail the decode at the top level and take the whole
    /// page down over one un-probed file. Zero then falls through to the
    /// portrait fallback in `aspectRatio`.
    /// Declared explicitly: providing `init(from:)` stops Swift from
    /// synthesising these. The snake_case `duration_sec` is handled by the
    /// decoder's key strategy, so the name here stays camelCase.
    enum CodingKeys: String, CodingKey {
        case type, name, path, width, height, durationSec
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(Kind.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        path = try container.decode(String.self, forKey: .path)
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
        durationSec = try container.decodeIfPresent(Double.self, forKey: .durationSec)
    }

    /// Width / height. Falls back to 2:3 (the library skews portrait) when the
    /// backend has not probed the size yet, so the wall never divides by zero.
    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 2.0 / 3.0 }
        return Double(width) / Double(height)
    }
}

/// A page of the recursive view.
struct MediaPage: Decodable, Sendable {
    let items: [MediaItem]
    let total: Int
    let offset: Int
    let limit: Int
}

/// A folder as returned inside the shallow view, carrying a cover to show on the wall.
struct FolderNode: Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let path: String
    let cover: CoverNode?

    var id: String { path }
}

/// A folder's cover.
///
/// Every field is optional, `path` included. The backend declares cover as a
/// non-pointer struct with `omitempty` — which does nothing for a struct — so a
/// folder whose whole subtree holds no media serialises as `"cover": {}`.
/// A required `path` would make that empty object fail to decode, and because
/// the failure is at the top level it would take the *entire* folder listing
/// with it: one media-less subfolder anywhere would blank out its parent.
struct CoverNode: Decodable, Hashable, Sendable {
    let name: String?
    let path: String?
    let width: Int?
    let height: Int?

    var aspectRatio: Double {
        guard let width, let height, width > 0, height > 0 else { return 2.0 / 3.0 }
        return Double(width) / Double(height)
    }

    /// Folder covers can themselves be videos, which need the poster route
    /// rather than the thumbnail route.
    var isVideo: Bool {
        path.map(MediaKindGuess.isVideoPath) ?? false
    }
}

/// The shallow view: this folder's direct children.
struct ExploreResponse: Decodable, Sendable {
    let directories: [FolderNode]?
    let images: [MediaItem.Raw]?
    let videos: [MediaItem.Raw]?
}

extension MediaItem {
    /// `/api/explore` predates the paged endpoint and returns images and videos
    /// in separate arrays with no `type` field, so they are decoded untyped and
    /// tagged here.
    struct Raw: Decodable, Sendable {
        let name: String
        let path: String
        let width: Int?
        let height: Int?
        let durationSec: Double?
    }

    init(raw: Raw, type: Kind) {
        self.type = type
        self.name = raw.name
        self.path = raw.path
        self.width = raw.width ?? 0
        self.height = raw.height ?? 0
        self.durationSec = raw.durationSec
    }
}

/// What a cell on the wall can be. The shallow view mixes folders with media;
/// the recursive view contains media only.
enum WallEntry: Identifiable, Hashable, Sendable {
    case folder(FolderNode)
    case media(MediaItem)

    var id: String {
        switch self {
        case .folder(let f): "d:" + f.path
        case .media(let m): "m:" + m.path
        }
    }

    var aspectRatio: Double {
        switch self {
        case .folder(let f): f.cover?.aspectRatio ?? 2.0 / 3.0
        case .media(let m): m.aspectRatio
        }
    }
}

enum MediaKindGuess {
    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv", "avi", "flv", "wmv", "ts", "ogv",
    ]

    static func isVideoPath(_ path: String) -> Bool {
        guard let ext = path.split(separator: ".").last else { return false }
        return videoExtensions.contains(ext.lowercased())
    }
}
