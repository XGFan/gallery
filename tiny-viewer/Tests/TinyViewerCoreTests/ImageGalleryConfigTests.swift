import Foundation
import XCTest

@testable import TinyViewerCore

private struct ImageGalleryConfigTestFailure: Error {}

private func cfgRequire(_ condition: @autoclosure () -> Bool, _ message: String? = nil) throws {
    if !condition() {
        if let message {
            print(message)
        }
        throw ImageGalleryConfigTestFailure()
    }
}

private func cfgRequireEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String? = nil) throws {
    try cfgRequire(actual == expected, message ?? "Expected \(expected), got \(actual)")
}

final class ImageGalleryConfigTests: XCTestCase {
    func testAPIEndpointUsesBaseImagePathWhenCategoryIsEmpty() throws {
        let config = ImageGalleryConfig(baseURL: "https://example.com", category: "")

        try cfgRequireEqual(config.apiEndpoint?.absoluteString, "https://example.com/api/image")
    }

    func testAPIEndpointAppendsCategoryPathWhenPresent() throws {
        let config = ImageGalleryConfig(baseURL: "https://example.com", category: "cats")

        try cfgRequireEqual(config.apiEndpoint?.absoluteString, "https://example.com/api/image/cats")
    }

    func testImageURLPreservesAlreadyEncodedPaths() throws {
        let config = ImageGalleryConfig(baseURL: "https://example.com")
        let node = ImageNode(name: "encoded", path: "albums/hello%20world%E4%BD%A0%E5%A5%BD.jpg")

        try cfgRequireEqual(
            config.imageURL(for: node)?.absoluteString,
            "https://example.com/file/albums/hello%20world%E4%BD%A0%E5%A5%BD.jpg"
        )
    }

    func testImageURLPercentEncodesRawPaths() throws {
        let config = ImageGalleryConfig(baseURL: "https://example.com")
        let node = ImageNode(name: "raw", path: "albums/hello world你好.jpg")

        try cfgRequireEqual(
            config.imageURL(for: node)?.absoluteString,
            "https://example.com/file/albums/hello%20world%E4%BD%A0%E5%A5%BD.jpg"
        )
    }
}
