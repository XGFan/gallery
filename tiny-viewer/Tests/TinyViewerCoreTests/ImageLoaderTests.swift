import Kingfisher
import XCTest

@testable import TinyViewerCore

private struct ImageLoaderTestFailure: Error {}

private func loaderRequire(_ condition: @autoclosure () -> Bool, _ message: String? = nil) throws {
    if !condition() {
        if let message {
            print(message)
        }
        throw ImageLoaderTestFailure()
    }
}

private func loaderRequireEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String? = nil) throws {
    try loaderRequire(actual == expected, message ?? "Expected \(expected), got \(actual)")
}

final class ImageLoaderTests: XCTestCase {
    func testConfigureKingfisherSetsExpectedCacheLimits() throws {
        let cache = ImageCache.default
        let originalMemoryLimit = cache.memoryStorage.config.totalCostLimit
        let originalDiskLimit = cache.diskStorage.config.sizeLimit

        defer {
            cache.memoryStorage.config.totalCostLimit = originalMemoryLimit
            cache.diskStorage.config.sizeLimit = originalDiskLimit
        }

        cache.memoryStorage.config.totalCostLimit = 1
        cache.diskStorage.config.sizeLimit = 2

        ImageLoader().configureKingfisher()

        try loaderRequireEqual(cache.memoryStorage.config.totalCostLimit, 100 * 1024 * 1024)
        try loaderRequireEqual(cache.diskStorage.config.sizeLimit, 500 * 1024 * 1024)
    }
}
