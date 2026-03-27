import Foundation
import XCTest

@testable import TinyViewerCore
@testable import TinyViewerIOS

private struct IOSGalleryViewModelTestFailure: Error {}
private enum IOSGalleryViewModelTestError: Error {
    case fetchFailed
}

private func iosRequire(_ condition: @autoclosure () -> Bool, _ message: String? = nil) throws {
    if !condition() {
        if let message {
            print(message)
        }
        throw IOSGalleryViewModelTestFailure()
    }
}

private func iosRequireEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String? = nil) throws {
    try iosRequire(actual == expected, message ?? "Expected \(expected), got \(actual)")
}

@MainActor
final class IOSGalleryViewModelTests: XCTestCase {
    func testNextImageWrapsAroundFromLastToFirst() throws {
        let viewModel = makeViewModel(imageCount: 4)
        viewModel.currentIndex = 3

        viewModel.nextImage()

        try iosRequireEqual(viewModel.currentIndex, 0)
    }

    func testPreviousImageWrapsAroundFromFirstToLast() throws {
        let viewModel = makeViewModel(imageCount: 4)
        viewModel.currentIndex = 0

        viewModel.previousImage()

        try iosRequireEqual(viewModel.currentIndex, 3)
    }

    func testNearbyPrefetchURLsExcludeCurrentAndWrapAround() throws {
        let viewModel = makeViewModel(imageCount: 8)
        viewModel.currentIndex = 0

        let urls = viewModel.nearbyImageURLsForPrefetch().map(\.absoluteString)

        try iosRequireEqual(
            urls,
            [
                "https://example.com/file/image-5.jpg",
                "https://example.com/file/image-6.jpg",
                "https://example.com/file/image-7.jpg",
                "https://example.com/file/image-1.jpg",
                "https://example.com/file/image-2.jpg",
                "https://example.com/file/image-3.jpg"
            ]
        )
        try iosRequire(!urls.contains("https://example.com/file/image-0.jpg"))
    }

    func testLoadImagesSetsErrorAndStopsLoadingWhenFetchFails() async throws {
        let viewModel = makeViewModel(imageCount: 0)

        viewModel.imageFetcher = { _ in
            throw IOSGalleryViewModelTestError.fetchFailed
        }

        await viewModel.loadImages()

        try iosRequire(viewModel.error is IOSGalleryViewModelTestError)
        try iosRequire(!viewModel.isLoading)
    }

    func testLoadImagesSuccessClearsErrorAndResetsIndex() async throws {
        let viewModel = makeViewModel(imageCount: 2)
        viewModel.error = IOSGalleryViewModelTestError.fetchFailed
        viewModel.currentIndex = 1

        viewModel.imageFetcher = { _ in
            [ImageNode(name: "loaded", path: "loaded.jpg")]
        }

        await viewModel.loadImages()

        try iosRequireEqual(viewModel.images.count, 1)
        try iosRequireEqual(viewModel.images.first?.path, "loaded.jpg")
        try iosRequireEqual(viewModel.currentIndex, 0)
        try iosRequire(viewModel.error == nil)
        try iosRequire(!viewModel.isLoading)
    }

    private func makeViewModel(imageCount: Int) -> TinyViewerIOS.GalleryViewModel {
        let config = ImageGalleryConfig(baseURL: "https://example.com")
        let viewModel = TinyViewerIOS.GalleryViewModel(config: config)
        viewModel.images = (0..<imageCount).map {
            ImageNode(name: "image-\($0)", path: "image-\($0).jpg")
        }
        return viewModel
    }
}
