import Foundation

enum GalleryError: LocalizedError, Equatable {
    /// The request was answered with a login page instead of data. See
    /// docs/adr/0004: the backend sits behind tinyauth with a LAN IP bypass, so
    /// off-network requests get a 302 to the login page rather than a 401.
    case needsTrustedNetwork
    case http(Int)
    case badResponse
    /// Carries the underlying decoding failure. Without it every schema
    /// mismatch collapses into one unactionable sentence, which is exactly what
    /// made a real field mismatch take an afternoon to find.
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .needsTrustedNetwork:
            "当前网络需要登录才能访问图库。请接入家庭局域网或 easytier 后重试。"
        case .http(let code):
            "服务器返回 \(code)。"
        case .badResponse:
            "服务器返回了无法解析的内容。"
        case .decoding(let detail):
            "无法解析服务器返回的内容：\(detail)"
        }
    }
}

/// Percent-encoding for a library path.
///
/// The library contains CJK names, spaces and brackets (e.g.
/// `Bunny/ [小倉ちよ]サン・ルイ 華麗なる聖騎士/01.jpg`). Each path *segment* is
/// encoded independently so the slashes stay real separators — the same rule the
/// web frontend uses in `customEncodeURI`.
enum GalleryPath {
    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_.!~*'()")
        return set
    }()

    static func encode(_ path: String) -> String {
        path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? String(segment)
            }
            .joined(separator: "/")
    }
}

struct GalleryClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Asset URLs

    /// Grid *and* full-screen both use this tier. See docs/adr/0005: at 1920px
    /// long edge it already exceeds the phone's physical resolution, and sharing
    /// one tier makes opening an image from the wall a cache hit.
    func thumbnailURL(_ path: String) -> URL { build("/thumbnail/", path) }

    /// Only needed once the user pinches past the 1920px tier.
    func originalURL(_ path: String) -> URL { build("/file/", path) }

    func posterURL(_ path: String) -> URL { build("/poster/", path) }

    func videoURL(_ path: String) -> URL { build("/video/", path) }

    /// The right image for a wall cell: videos have no thumbnail, only a poster.
    func wallImageURL(for entry: WallEntry) -> URL? {
        switch entry {
        case .media(let m):
            m.isVideo ? posterURL(m.path) : thumbnailURL(m.path)
        case .folder(let f):
            f.cover?.path.map { path in
                MediaKindGuess.isVideoPath(path) ? posterURL(path) : thumbnailURL(path)
            }
        }
    }

    private func build(_ prefix: String, _ path: String) -> URL {
        let encoded = GalleryPath.encode(path)
        return URL(string: prefix + encoded, relativeTo: baseURL)?.absoluteURL
            ?? baseURL.appendingPathComponent(prefix).appendingPathComponent(path)
    }

    // MARK: - API

    /// The recursive view, one page at a time.
    func mediaPage(path: String, offset: Int, limit: Int) async throws -> MediaPage {
        var components = urlComponents("/api/media/", path)
        components.queryItems = [
            .init(name: "flat", value: "true"),
            .init(name: "offset", value: String(offset)),
            .init(name: "limit", value: String(limit)),
        ]
        return try await fetch(MediaPage.self, from: components)
    }

    /// The shallow view: this folder's direct children, folders included.
    func explore(path: String) async throws -> [WallEntry] {
        let response = try await fetch(ExploreResponse.self, from: urlComponents("/api/explore/", path))
        var entries: [WallEntry] = (response.directories ?? []).map { .folder($0) }
        entries += (response.images ?? []).map { .media(MediaItem(raw: $0, type: .image)) }
        entries += (response.videos ?? []).map { .media(MediaItem(raw: $0, type: .video)) }
        return entries
    }

    /// The whole folder tree, for the navigation sheet / sidebar.
    func tree() async throws -> FolderTree {
        let (data, response) = try await session.data(from: build("/api/tree", ""))
        try validate(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)
        return FolderTree(root: FolderTree.parse(raw, name: "", path: ""))
    }

    // MARK: - Plumbing

    private func urlComponents(_ prefix: String, _ path: String) -> URLComponents {
        let url = build(prefix, path)
        return URLComponents(url: url, resolvingAgainstBaseURL: true) ?? URLComponents()
    }

    private func fetch<T: Decodable>(_ type: T.Type, from components: URLComponents) async throws -> T {
        guard let url = components.url else { throw GalleryError.badResponse }
        let (data, response) = try await session.data(from: url)
        try validate(response, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GalleryError.decoding(Self.describe(error))
        }
    }

    /// Turns a DecodingError into something that names the offending key and
    /// path, rather than a generic "could not parse".
    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return String(describing: error) }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch decoding {
        case .keyNotFound(let key, let context):
            return "缺少字段 \(key.stringValue)（位置 \(path(context))）"
        case .typeMismatch(let type, let context):
            return "字段类型不符，期望 \(type)（位置 \(path(context))）"
        case .valueNotFound(let type, let context):
            return "字段为空，期望 \(type)（位置 \(path(context))）"
        case .dataCorrupted(let context):
            return "内容损坏（位置 \(path(context))）：\(context.debugDescription)"
        @unknown default:
            return String(describing: decoding)
        }
    }

    /// tinyauth answers an unauthenticated request with a redirect to its login
    /// page, which URLSession follows — so the failure surfaces as HTML with a
    /// 200, not as a 401. Detect that and say something actionable.
    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GalleryError.badResponse }

        // Status first. The tinyauth signature is specifically a *2xx* carrying
        // HTML (URLSession followed the 302 to the login page). Testing the
        // content type first would report a proxy's 502 error page as "you are
        // on the wrong network" and send the user off debugging their Wi-Fi
        // while the backend is simply restarting.
        guard (200..<300).contains(http.statusCode) else {
            throw GalleryError.http(http.statusCode)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/html") {
            throw GalleryError.needsTrustedNetwork
        }
    }
}

/// `/api/tree` returns bare nested objects (`{"Weibo": {"SIREN": {}}}`) with no
/// schema, so it is parsed by hand rather than through Codable.
struct FolderTree: Sendable {
    let root: Node

    struct Node: Identifiable, Hashable, Sendable {
        let name: String
        let path: String
        let children: [Node]

        var id: String { path }
        var isLeaf: Bool { children.isEmpty }

        /// `List(children:)` shows a disclosure triangle only when this is
        /// non-nil, so leaves must report nil rather than an empty array.
        var optionalChildren: [Node]? { children.isEmpty ? nil : children }
    }

    static func parse(_ raw: Any, name: String, path: String) -> Node {
        guard let dict = raw as? [String: Any] else {
            return Node(name: name, path: path, children: [])
        }
        let children = dict.keys.sorted().map { key -> Node in
            let childPath = path.isEmpty ? key : path + "/" + key
            return parse(dict[key] as Any, name: key, path: childPath)
        }
        return Node(name: name, path: path, children: children)
    }
}
