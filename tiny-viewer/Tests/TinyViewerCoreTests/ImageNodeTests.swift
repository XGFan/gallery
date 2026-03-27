import Foundation
import XCTest

@testable import TinyViewerCore

private struct TestFailure: Error {}

private func require(_ condition: @autoclosure () -> Bool) throws {
    if !condition() {
        throw TestFailure()
    }
}

final class ImageNodeTests: XCTestCase {
    func testAspectRatioUsesDimensions() throws {
        let node = ImageNode(name: "cover", path: "covers/cover.jpg", width: 1920, height: 1080)

        try require(node.id == "covers/cover.jpg")
        try require(abs(node.aspectRatio - (16.0 / 9.0)) <= 0.0001)
    }

    func testAspectRatioFallsBackToSquareWhenHeightMissing() throws {
        let node = ImageNode(name: "fallback", path: "fallback.jpg", width: 800, height: nil)

        try require(abs(node.aspectRatio - 1.0) <= 0.0001)
    }
}
