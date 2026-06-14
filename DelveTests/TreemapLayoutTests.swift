import XCTest
import CoreGraphics
@testable import Delve

final class TreemapLayoutTests: XCTestCase {
    let canvas = CGRect(x: 0, y: 0, width: 800, height: 600)

    // MARK: - Helpers

    private func leaf(_ name: String, _ size: Int64) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name,
                 isDirectory: false, isPackage: false, ownSize: size)
    }

    private func dir(_ name: String, _ children: [FileNode]) -> FileNode {
        let node = FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name,
                            isDirectory: true, isPackage: false, ownSize: 0)
        for child in children {
            child.parent = node
            node.children.append(child)
            node.totalSize += child.totalSize
        }
        return node
    }

    private func names(_ tiles: [TileRect]) -> [String] { tiles.map(\.name) }

    // MARK: - Single-level behavior

    func testLaysOutOnlyDirectChildren() {
        let subdir = dir("sub", [leaf("grandchild", 500)])
        let sibling = leaf("sibling", 500)
        let root = dir("root", [subdir, sibling])

        let tiles = TreemapLayout.layout(root: root, in: canvas)

        XCTAssertEqual(tiles.count, 2)
        XCTAssertTrue(names(tiles).contains("sub"))
        XCTAssertTrue(names(tiles).contains("sibling"))
        XCTAssertFalse(names(tiles).contains("grandchild")) // grandchildren not rendered
    }

    func testSingleChildFillsCanvas() {
        let root = dir("root", [leaf("only.txt", 1000)])
        let tiles = TreemapLayout.layout(root: root, in: canvas)

        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].frame.width, canvas.width, accuracy: 1)
        XCTAssertEqual(tiles[0].frame.height, canvas.height, accuracy: 1)
    }

    func testTotalAreaEqualsCanvas() {
        let children = (1...5).map { leaf("file\($0)", Int64($0 * 100)) }
        let root = dir("root", children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)
        let area = tiles.reduce(0.0) { $0 + $1.frame.width * $1.frame.height }

        XCTAssertEqual(Double(area), Double(canvas.width * canvas.height), accuracy: 1.0)
    }

    func testNoOverlappingTiles() {
        let children = (1...6).map { leaf("file\($0)", Int64($0 * 200)) }
        let root = dir("root", children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)
        for i in 0..<tiles.count {
            for j in (i + 1)..<tiles.count {
                let intersection = tiles[i].frame.intersection(tiles[j].frame)
                let overlapArea = intersection.width * intersection.height
                XCTAssertLessThan(overlapArea, 1.0, "Tiles \(i) and \(j) overlap")
            }
        }
    }

    func testTilesStayWithinCanvas() {
        let children = (1...8).map { leaf("file\($0)", Int64($0 * 150)) }
        let root = dir("root", children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)
        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.frame.minX, canvas.minX - 1)
            XCTAssertGreaterThanOrEqual(tile.frame.minY, canvas.minY - 1)
            XCTAssertLessThanOrEqual(tile.frame.maxX, canvas.maxX + 1)
            XCTAssertLessThanOrEqual(tile.frame.maxY, canvas.maxY + 1)
        }
    }

    func testEmptyRootProducesNoTiles() {
        let root = dir("root", [])
        XCTAssertTrue(TreemapLayout.layout(root: root, in: canvas).isEmpty)
    }

    // MARK: - Aggregate "smaller items" bucket

    func testSmallChildrenAreBucketed() {
        var children = [leaf("big", 10000)]
        children += (1...20).map { leaf("tiny\($0)", 100) } // each 100/12000 ≈ 0.8% < 2%
        let root = dir("root", children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)

        // one big tile + one aggregate tile
        XCTAssertEqual(tiles.count, 2)

        let aggregate = tiles.first { if case .aggregate = $0.content { return true } else { return false } }
        XCTAssertNotNil(aggregate)
        if case .aggregate(let count, let size) = aggregate?.content {
            XCTAssertEqual(count, 20)
            XCTAssertEqual(size, 2000)
        }
    }

    func testBucketedLayoutStillFillsCanvas() {
        var children = [leaf("big", 10000)]
        children += (1...20).map { leaf("tiny\($0)", 100) }
        let root = dir("root", children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)
        let area = tiles.reduce(0.0) { $0 + $1.frame.width * $1.frame.height }

        XCTAssertEqual(Double(area), Double(canvas.width * canvas.height), accuracy: 1.0)
    }

    func testNoBucketWhenAllChildrenAreLargeEnough() {
        let children = (1...3).map { leaf("file\($0)", 1000) }
        let root = dir("root", children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)
        XCTAssertEqual(tiles.count, 3)
        XCTAssertFalse(tiles.contains { if case .aggregate = $0.content { return true } else { return false } })
    }

    func testZeroSizedChildrenAreIgnored() {
        let root = dir("root", [leaf("real", 1000), leaf("empty", 0)])
        let tiles = TreemapLayout.layout(root: root, in: canvas)

        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].name, "real")
    }

    func testColorIndexFollowsLargestFirstRank() {
        // Deliberately out of order; the layout sorts largest-first and the
        // color index must be the post-sort rank so tiles and sidebar agree.
        let root = dir("root", [leaf("small", 1000), leaf("big", 5000), leaf("mid", 3000)])
        let tiles = TreemapLayout.layout(root: root, in: canvas)

        let indexByName = Dictionary(uniqueKeysWithValues: tiles.map { ($0.name, $0.colorIndex) })
        XCTAssertEqual(indexByName["big"], 0)
        XCTAssertEqual(indexByName["mid"], 1)
        XCTAssertEqual(indexByName["small"], 2)
    }

    func testAggregateTileGetsNegativeColorIndex() {
        var children = [leaf("big", 10000)]
        children += (1...20).map { leaf("tiny\($0)", 100) }
        let root = dir("root", children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)
        let aggregate = tiles.first { if case .aggregate = $0.content { return true } else { return false } }
        // Sentinel: the aggregate is drawn a fixed grey, not a sibling hue.
        XCTAssertEqual(aggregate?.colorIndex, -1)
    }
}
