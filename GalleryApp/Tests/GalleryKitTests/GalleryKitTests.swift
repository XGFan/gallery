import XCTest

@testable import GalleryApp

final class GalleryPathTests: XCTestCase {
    /// The library is full of CJK names, spaces and brackets. Slashes must stay
    /// real separators while everything else gets encoded.
    func testEncodesSegmentsButKeepsSlashes() {
        XCTAssertEqual(GalleryPath.encode("Weibo/SIREN"), "Weibo/SIREN")
        XCTAssertEqual(
            GalleryPath.encode("Weibo/kyokyo不是qq啊"),
            "Weibo/kyokyo%E4%B8%8D%E6%98%AFqq%E5%95%8A"
        )

        let bracketed = GalleryPath.encode("Bunny/ [小倉ちよ]サン・ルイ/01.jpg")
        XCTAssertEqual(bracketed.components(separatedBy: "/").count, 3, "slashes must survive")
        XCTAssertTrue(bracketed.hasSuffix("/01.jpg"))
        XCTAssertFalse(bracketed.contains(" "), "spaces must be encoded")
        XCTAssertTrue(bracketed.contains("%5B"), "brackets must be encoded")
    }

    func testEmptyPath() {
        XCTAssertEqual(GalleryPath.encode(""), "")
    }
}

final class MasonryLayoutTests: XCTestCase {
    private struct Item: Identifiable, Hashable {
        let id: Int
        let ratio: Double
    }

    func testAssignsEachItemToShortestColumn() {
        // Square items in 3 columns should round-robin.
        let items = (0..<6).map { Item(id: $0, ratio: 1.0) }
        let columns = MasonryLayout.distribute(
            items, columnCount: 3, columnWidth: 100, aspectRatio: { $0.ratio }
        )

        XCTAssertEqual(columns.count, 3)
        XCTAssertEqual(columns.map(\.count), [2, 2, 2])
        XCTAssertEqual(columns[0].map(\.id), [0, 3])
        XCTAssertEqual(columns[1].map(\.id), [1, 4])
        XCTAssertEqual(columns[2].map(\.id), [2, 5])
    }

    /// A very tall item should push later items into the other columns, which is
    /// the entire reason for masonry over a fixed grid.
    func testTallItemDivertsFollowingItems() {
        let items = [
            Item(id: 0, ratio: 0.25),  // very tall
            Item(id: 1, ratio: 1.0),
            Item(id: 2, ratio: 1.0),
        ]
        let columns = MasonryLayout.distribute(
            items, columnCount: 2, columnWidth: 100, aspectRatio: { $0.ratio }
        )

        XCTAssertEqual(columns[0].map(\.id), [0])
        XCTAssertEqual(columns[1].map(\.id), [1, 2])
    }

    /// A zero or garbage ratio must not produce an infinite cell that starves
    /// every other column.
    func testClampsDegenerateRatios() {
        let items = [Item(id: 0, ratio: 0), Item(id: 1, ratio: 1), Item(id: 2, ratio: 1)]
        let columns = MasonryLayout.distribute(
            items, columnCount: 2, columnWidth: 100, aspectRatio: { $0.ratio }
        )
        XCTAssertEqual(columns.flatMap(\.self).count, 3, "no item may be dropped")

        let height = MasonryLayout.cellHeight(columnWidth: 100, aspectRatio: 0)
        XCTAssertTrue(height.isFinite && height > 0, "got \(height)")
        XCTAssertEqual(height, 500, accuracy: 0.001, "clamped to the 0.2 floor")
    }

    func testZeroColumnsYieldsNothingRatherThanCrashing() {
        let columns = MasonryLayout.distribute(
            [Item(id: 0, ratio: 1)], columnCount: 0, columnWidth: 100, aspectRatio: { $0.ratio }
        )
        XCTAssertTrue(columns.isEmpty)
    }
}

final class MediaItemTests: XCTestCase {
    func testDecodesPagedResponseIncludingSnakeCaseDuration() throws {
        let json = """
        {"items":[
          {"type":"image","name":"a.jpg","path":"d/a.jpg","width":100,"height":200},
          {"type":"video","name":"b.mp4","path":"d/b.mp4","width":1920,"height":1080,"duration_sec":12.5}
        ],"total":8,"offset":0,"limit":2}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(MediaPage.self, from: json)

        XCTAssertEqual(page.total, 8)
        XCTAssertEqual(page.items.count, 2)
        XCTAssertFalse(page.items[0].isVideo)
        XCTAssertTrue(page.items[1].isVideo)
        XCTAssertEqual(page.items[1].durationSec, 12.5)
        XCTAssertEqual(page.items[0].aspectRatio, 0.5, accuracy: 0.001)
    }

    /// The backend omits width/height until the size probe has run.
    func testMissingSizeFallsBackToPortraitRatio() {
        let item = MediaItem(
            raw: .init(name: "x.jpg", path: "x.jpg", width: nil, height: nil, durationSec: nil),
            type: .image
        )
        XCTAssertEqual(item.aspectRatio, 2.0 / 3.0, accuracy: 0.001)
    }

    func testFolderCoverDetectsVideoByExtension() {
        XCTAssertTrue(CoverNode(name: nil, path: "a/b.MP4", width: 1, height: 1).isVideo)
        XCTAssertFalse(CoverNode(name: nil, path: "a/b.jpg", width: 1, height: 1).isVideo)
    }
}

final class FolderTreeTests: XCTestCase {
    /// `/api/tree` returns bare nested objects with no schema.
    func testParsesNestedObjectsIntoPaths() throws {
        let raw: [String: Any] = [
            "Weibo": ["SIREN": [String: Any]()],
            "Bunny": [String: Any](),
        ]
        let root = FolderTree.parse(raw, name: "", path: "")

        XCTAssertEqual(root.children.map(\.name), ["Bunny", "Weibo"], "sorted for stable display")

        let weibo = try XCTUnwrap(root.children.first { $0.name == "Weibo" })
        XCTAssertEqual(weibo.path, "Weibo")

        let siren = try XCTUnwrap(weibo.children.first)
        XCTAssertEqual(siren.path, "Weibo/SIREN")
        XCTAssertTrue(siren.isLeaf)
        XCTAssertNil(siren.optionalChildren, "leaves must not show a disclosure")
    }
}

final class DurationFormatTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(WallCell.formatDuration(0), "0:00")
        XCTAssertEqual(WallCell.formatDuration(65), "1:05")
        XCTAssertEqual(WallCell.formatDuration(3661), "1:01:01")
    }
}
