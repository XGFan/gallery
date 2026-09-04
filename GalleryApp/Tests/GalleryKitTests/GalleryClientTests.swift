import XCTest

@testable import GalleryApp

/// Serves canned HTTP responses so the client and the paging state machine can
/// be driven without a backend.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status: Int = 200
        var contentType: String = "application/json; charset=utf-8"
        var body: Data = Data()
        var delay: TimeInterval = 0
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Response)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = Self.handler?(request) ?? Response()
        let deliver = { [weak self] in
            guard let self, let url = self.request.url else { return }
            let http = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": response.contentType]
            )!
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if response.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}

private func stubbedClient() -> GalleryClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return GalleryClient(
        baseURL: URL(string: "https://gallery.example.com")!,
        session: URLSession(configuration: config)
    )
}

final class GalleryClientDecodingTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// The backend declares `cover` as a non-pointer struct with `omitempty`,
    /// which does nothing for a struct — so a folder whose subtree holds no
    /// media serialises as `"cover": {}`. A required `path` made that fail to
    /// decode, and because the failure is top-level it took the entire listing
    /// with it: one media-less subfolder blanked out its parent.
    func testEmptyCoverObjectDoesNotPoisonTheWholeListing() async throws {
        let json = """
        {"directories":[
          {"name":"empty","path":"a/empty","cover":{}},
          {"name":"real","path":"a/real","cover":{"name":"c.jpg","path":"a/real/c.jpg","width":100,"height":200}}
        ],"images":[],"videos":[],"others":[]}
        """
        StubURLProtocol.handler = { _ in .init(body: Data(json.utf8)) }

        let entries = try await stubbedClient().explore(path: "a")

        XCTAssertEqual(entries.count, 2, "the empty cover must not drop either folder")
        guard case .folder(let empty) = entries[0] else { return XCTFail("expected a folder") }
        XCTAssertNil(empty.cover?.path, "empty cover has no path")
        XCTAssertEqual(empty.aspectRatioFallbackCheck, 2.0 / 3.0, accuracy: 0.001)
    }

    /// A proxy's 502 error page is HTML too. Reporting it as "you're on the
    /// wrong network" sends the user to debug their Wi-Fi while the backend is
    /// merely restarting.
    func testServerErrorIsNotReportedAsNetworkProblem() async {
        StubURLProtocol.handler = { _ in
            .init(status: 502, contentType: "text/html", body: Data("<html>bad gateway</html>".utf8))
        }

        do {
            _ = try await stubbedClient().explore(path: "a")
            XCTFail("expected a failure")
        } catch let error as GalleryError {
            XCTAssertEqual(error, .http(502), "got \(error) — a 502 is a server error, not a network one")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// The genuine tinyauth signature: URLSession follows the 302 and lands on
    /// a 200 HTML login page.
    func testTwoHundredHtmlIsReportedAsNeedingTrustedNetwork() async {
        StubURLProtocol.handler = { _ in
            .init(status: 200, contentType: "text/html", body: Data("<html>login</html>".utf8))
        }

        do {
            _ = try await stubbedClient().explore(path: "a")
            XCTFail("expected a failure")
        } catch let error as GalleryError {
            XCTAssertEqual(error, .needsTrustedNetwork)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}


// File scope on purpose: the stub's handler is `@Sendable`, so it cannot capture
// `self` of a `@MainActor` XCTestCase.
private func mediaPageJSON(offset: Int, limit: Int, total: Int) -> Data {
    let end = min(offset + limit, total)
    let items = (offset..<max(offset, end)).map { index in
        """
        {"type":"image","name":"\(index).jpg","path":"p/\(index).jpg","width":100,"height":200}
        """
    }
    return Data("""
    {"items":[\(items.joined(separator: ","))],"total":\(total),"offset":\(offset),"limit":\(limit)}
    """.utf8)
}

private func intValue(in query: String, key: String) -> Int? {
    for pair in query.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1)
        if parts.count == 2, parts[0] == key { return Int(parts[1]) }
    }
    return nil
}

@MainActor
final class FolderStorePagingTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// A superseded load's `defer` used to clear the in-flight flag while its
    /// replacement was still running. That re-opened the paging guard, letting
    /// the wall fetch the same offset again and append every item twice.
    ///
    /// Asserted directly on the flag rather than through a duplicate-entry
    /// count: the duplicate only appears if the wall happens to ask for more
    /// inside that window, which makes an entry-count assertion timing-dependent
    /// and prone to passing while the bug is present.
    func testSupersededLoadMustNotClearTheInFlightFlag() async {
        // The superseded (shallow) load returns *before* its replacement.
        StubURLProtocol.handler = { request in
            if request.url?.path.contains("/api/explore/") == true {
                return .init(body: Data("""
                {"directories":[],"images":[],"videos":[],"others":[]}
                """.utf8), delay: 0.25)
            }
            let query = request.url?.query ?? ""
            let offset = intValue(in: query, key: "offset") ?? 0
            return .init(body: mediaPageJSON(offset: offset, limit: 150, total: 400), delay: 1.2)
        }

        let store = FolderStore(path: "p", client: stubbedClient(), recursive: false)
        let load = Task { await store.loadInitial() }
        try? await Task.sleep(nanoseconds: 50_000_000)

        store.recursive = true   // supersedes the shallow load already in flight

        // By now the shallow load has returned (0.25s) and been discarded, while
        // the recursive one (1.2s) is still running.
        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertTrue(
            store.isLoading,
            "the superseded load cleared the in-flight flag while its replacement was still running"
        )

        _ = await load.result
        try? await Task.sleep(nanoseconds: 900_000_000)
    }

    /// A page failure must not permanently end paging with no way back.
    func testPageErrorIsRecoverableViaRetry() async {
        let failFirstMore = Mutex(false)
        StubURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            let offset = intValue(in: query, key: "offset") ?? 0
            if offset > 0 && !failFirstMore.exchangeTrue() {
                return .init(status: 500, body: Data("{}".utf8))
            }
            return .init(body: mediaPageJSON(offset: offset, limit: 150, total: 400))
        }

        let store = FolderStore(path: "p", client: stubbedClient(), recursive: true)
        await store.loadInitial()
        XCTAssertEqual(store.entries.count, 150)

        await store.loadMoreIfNeeded()
        XCTAssertNotNil(store.error, "the failed page should surface an error")
        XCTAssertEqual(store.entries.count, 150, "a failed page must not append anything")

        await store.retry()
        XCTAssertNil(store.error, "retry should clear the error")
        XCTAssertEqual(store.entries.count, 300, "retry should actually fetch the page")
    }

}

/// Minimal one-shot flag usable from the `@Sendable` stub handler.
final class Mutex: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) { self.value = value }

    /// Returns the previous value and sets it to true.
    func exchangeTrue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = true
        return old
    }
}

extension FolderNode {
    /// Exercises the cover's ratio fallback without reaching into WallEntry.
    var aspectRatioFallbackCheck: Double { cover?.aspectRatio ?? 2.0 / 3.0 }
}
