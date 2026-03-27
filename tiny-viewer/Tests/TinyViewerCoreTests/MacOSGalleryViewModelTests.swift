import Foundation
import XCTest

@testable import TinyViewerCore
@testable import TinyViewerMacOS

private struct MacOSGalleryViewModelTestFailure: Error {}
private enum MacOSGalleryViewModelTestError: Error {
    case fetchFailed
}

private func macRequire(_ condition: @autoclosure () -> Bool, _ message: String? = nil) throws {
    if !condition() {
        if let message {
            print(message)
        }
        throw MacOSGalleryViewModelTestFailure()
    }
}

private func macRequireEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String? = nil) throws {
    try macRequire(actual == expected, message ?? "Expected \(expected), got \(actual)")
}

@MainActor
private final class MockSlideshowTimer: SlideshowTimerControlling {
    var invalidateCallCount = 0

    func invalidate() {
        invalidateCallCount += 1
    }
}

@MainActor
final class MacOSGalleryViewModelTests: XCTestCase {
    func testNextImageWrapsAroundFromLastToFirst() throws {
        let viewModel = makeViewModel(imageCount: 4)
        viewModel.currentIndex = 3

        viewModel.nextImage()

        try macRequireEqual(viewModel.currentIndex, 0)
    }

    func testPreviousImageWrapsAroundFromFirstToLast() throws {
        let viewModel = makeViewModel(imageCount: 4)
        viewModel.currentIndex = 0

        viewModel.previousImage()

        try macRequireEqual(viewModel.currentIndex, 3)
    }

    func testNearbyPrefetchURLsExcludeCurrentAndWrapAround() throws {
        let viewModel = makeViewModel(imageCount: 8)
        viewModel.currentIndex = 7

        let urls = viewModel.nearbyImageURLsForPrefetch().map(\.absoluteString)

        try macRequireEqual(
            urls,
            [
                "https://example.com/file/image-4.jpg",
                "https://example.com/file/image-5.jpg",
                "https://example.com/file/image-6.jpg",
                "https://example.com/file/image-0.jpg",
                "https://example.com/file/image-1.jpg",
                "https://example.com/file/image-2.jpg"
            ]
        )
        try macRequire(!urls.contains("https://example.com/file/image-7.jpg"))
    }

    func testTogglePlaybackUsesInjectedTimerSeamAndStopsDeterministically() async throws {
        let viewModel = makeViewModel(imageCount: 2)
        let timer = MockSlideshowTimer()
        var createdIntervals: [TimeInterval] = []
        var timerTick: (@Sendable () -> Void)?

        viewModel.slideshowTimerFactory = { interval, tick in
            createdIntervals.append(interval)
            timerTick = tick
            return timer
        }

        viewModel.togglePlayback()

        try macRequire(viewModel.isPlaying)
        try macRequireEqual(createdIntervals, [3.0])
        try macRequireEqual(timer.invalidateCallCount, 0)

        timerTick?()
        await Task.yield()
        try macRequireEqual(viewModel.currentIndex, 1)

        timerTick?()
        await Task.yield()
        try macRequireEqual(viewModel.currentIndex, 0)

        viewModel.togglePlayback()

        try macRequire(!viewModel.isPlaying)
        try macRequireEqual(timer.invalidateCallCount, 1)
    }

    func testLoadImagesSetsErrorAndStopsLoadingWhenFetchFails() async throws {
        let viewModel = makeViewModel(imageCount: 0)

        viewModel.imageFetcher = { _ in
            throw MacOSGalleryViewModelTestError.fetchFailed
        }

        await viewModel.loadImages()

        try macRequire(viewModel.error is MacOSGalleryViewModelTestError)
        try macRequire(!viewModel.isLoading)
    }

    func testLoadImagesSuccessClearsErrorAndResetsIndex() async throws {
        let viewModel = makeViewModel(imageCount: 2)
        viewModel.error = MacOSGalleryViewModelTestError.fetchFailed
        viewModel.currentIndex = 1

        viewModel.imageFetcher = { _ in
            [ImageNode(name: "loaded", path: "loaded.jpg")]
        }

        await viewModel.loadImages()

        try macRequireEqual(viewModel.images.count, 1)
        try macRequireEqual(viewModel.images.first?.path, "loaded.jpg")
        try macRequireEqual(viewModel.currentIndex, 0)
        try macRequire(viewModel.error == nil)
        try macRequire(!viewModel.isLoading)
    }

    private func makeViewModel(imageCount: Int) -> TinyViewerMacOS.GalleryViewModel {
        let config = ImageGalleryConfig(baseURL: "https://example.com")
        let viewModel = TinyViewerMacOS.GalleryViewModel(config: config)
        viewModel.images = (0..<imageCount).map {
            ImageNode(name: "image-\($0)", path: "image-\($0).jpg")
        }
        return viewModel
    }
}
