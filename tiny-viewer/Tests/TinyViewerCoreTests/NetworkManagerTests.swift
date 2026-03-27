import Foundation
import XCTest

@testable import TinyViewerCore

private struct NetworkManagerTestFailure: Error {}

private func nmFail(_ message: String? = nil) throws -> Never {
    if let message {
        print(message)
    }
    throw NetworkManagerTestFailure()
}

private func nmRequire(_ condition: @autoclosure () -> Bool, _ message: String? = nil) throws {
    if !condition() {
        try nmFail(message)
    }
}

private func nmRequireEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String? = nil) throws {
    try nmRequire(actual == expected, message ?? "Expected \(expected), got \(actual)")
}

private func nmRequireValue<T>(_ value: T?, _ message: String? = nil) throws -> T {
    guard let value else {
        try nmFail(message ?? "Expected non-nil value")
    }
    return value
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func setRequestHandler(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        requestHandler = handler
        lock.unlock()
    }

    static func clearRequestHandler() {
        lock.lock()
        requestHandler = nil
        lock.unlock()
    }

    private static func currentHandler() -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer { lock.unlock() }
        return requestHandler
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.currentHandler() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class NetworkManagerTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.clearRequestHandler()
        super.tearDown()
    }

    func testFetchImagesDecodesSuccessfulResponseWithoutRealHTTP() async throws {
        let config = ImageGalleryConfig(baseURL: "https://example.com", category: "cats")
        let session = makeSession()
        let manager = NetworkManager(session: session)

        MockURLProtocol.setRequestHandler { request in
            try nmRequireEqual(request.url?.absoluteString, "https://example.com/api/image/cats")

            let response = HTTPURLResponse(
                url: try nmRequireValue(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            [{"name":"cover","path":"albums/cover.jpg","width":1200,"height":800}]
            """.data(using: .utf8)!
            return (response, data)
        }
        
        let images = try await manager.fetchImages(config: config)

        try nmRequireEqual(images.count, 1)
        try nmRequireEqual(images.first?.name, "cover")
        try nmRequireEqual(images.first?.path, "albums/cover.jpg")
        try nmRequireEqual(images.first?.width, 1200)
        try nmRequireEqual(images.first?.height, 800)
    }

    func testFetchImagesRejectsNon200Responses() async throws {
        let config = ImageGalleryConfig(baseURL: "https://example.com")
        let session = makeSession()
        let manager = NetworkManager(session: session)

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(
                url: try nmRequireValue(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("[]".utf8))
        }

        do {
            _ = try await manager.fetchImages(config: config)
            try nmFail("Expected invalidResponse for non-200 response")
        } catch let error as NetworkError {
            guard case .invalidResponse = error else {
                try nmFail("Expected invalidResponse, got \(error)")
            }
        } catch {
            try nmFail("Expected NetworkError.invalidResponse, got \(error)")
        }
    }

    func testFetchImagesMapsDecodeFailuresToDeterministicError() async throws {
        let config = ImageGalleryConfig(baseURL: "https://example.com")
        let session = makeSession()
        let manager = NetworkManager(session: session)

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(
                url: try nmRequireValue(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"not\":\"an array\"}".utf8))
        }

        do {
            _ = try await manager.fetchImages(config: config)
            try nmFail("Expected decodingFailed for invalid JSON payload")
        } catch let error as NetworkError {
            guard case .decodingFailed = error else {
                try nmFail("Expected decodingFailed, got \(error)")
            }
        } catch {
            try nmFail("Expected NetworkError.decodingFailed, got \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
