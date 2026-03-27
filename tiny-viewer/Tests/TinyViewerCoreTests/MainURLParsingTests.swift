import XCTest

@testable import TinyViewerMain

private struct MainURLParsingTestFailure: Error {}

private func parseRequire(_ condition: @autoclosure () -> Bool, _ message: String? = nil) throws {
    if !condition() {
        if let message {
            print(message)
        }
        throw MainURLParsingTestFailure()
    }
}

private func parseRequireEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String? = nil) throws {
    try parseRequire(actual == expected, message ?? "Expected \(expected), got \(actual)")
}

final class MainURLParsingTests: XCTestCase {
    func testParseCategoryHandlesRawPathAndQueryStripping() throws {
        let category = parseCategoryFromURLString("tinyviewer://Weibo/folder/path?foo=bar")

        try parseRequireEqual(category, "Weibo/folder/path")
    }

    func testParseCategoryHandlesEncodedPathAndDecoding() throws {
        let category = parseCategoryFromURLString("tinyviewer://Weibo/kyokyo%E4%B8%8D%E6%98%AFqq%E5%95%8A?foo=bar")

        try parseRequireEqual(category, "Weibo/kyokyo不是qq啊")
    }

    func testParseCategoryTrimsLeadingAndTrailingSlashes() throws {
        let category = parseCategoryFromURLString("tinyviewer:///Weibo/album///")

        try parseRequireEqual(category, "Weibo/album")
    }

    func testParseCategoryUsesCategoryQueryWhenOpenURLProvided() throws {
        let category = parseCategoryFromURLString("tinyviewer://open?category=Weibo%2FSub%20Album&foo=bar")

        try parseRequireEqual(category, "Weibo/Sub Album")
    }

    func testParseCategoryUsesCategoryQueryWithoutScheme() throws {
        let category = parseCategoryFromURLString("open?category=raw%2Fpath")

        try parseRequireEqual(category, "raw/path")
    }
}
