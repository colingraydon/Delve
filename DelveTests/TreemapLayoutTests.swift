import XCTest
import CoreGraphics
@testable import Delve

final class TreemapLayoutTests: XCTestCase {
    let canvas = CGRect(x: 0, y: 0, width: 800, height: 600)

    // MARK: - Helpers

    private func makeNode(name: String, size: Int64, children: [FileNode] = []) -> FileNode {
        let node = FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name, isDirectory: !children.isEmpty, isPackage: false, ownSize: size)
        for child in children {
            child.parent = node
            node.children.append(child)
            node.totalSize += child.totalSize
        }
        return node
    }

    // MARK: - Tests

    func testSingleChildFillsCanvas() {
        let child = makeNode(name: "file.txt", size: 1000)
        let root = makeNode(name: "root", size: 0, children: [child])

        let tiles = TreemapLayout.layout(root: root, in: canvas)

        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].frame.width, canvas.width, accuracy: 1)
        XCTAssertEqual(tiles[0].frame.height, canvas.height, accuracy: 1)
    }

    func testTotalAreaEqualsCanvas() {
        let children = (1...5).map { makeNode(name: "file\($0).txt", size: Int64($0 * 100)) }
        let root = makeNode(name: "root", size: 0, children: children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)
        let totalArea = tiles.filter { $0.depth == 0 }.reduce(0.0) { $0 + $1.frame.width * $1.frame.height }
        let canvasArea = canvas.width * canvas.height

        XCTAssertEqual(Double(totalArea), Double(canvasArea), accuracy: 1.0)
    }

    func testNoOverlappingTilesAtSameDepth() {
        let children = (1...6).map { makeNode(name: "file\($0).txt", size: Int64($0 * 200)) }
        let root = makeNode(name: "root", size: 0, children: children)

        let tiles = TreemapLayout.layout(root: root, in: canvas).filter { $0.depth == 0 }

        for i in 0..<tiles.count {
            for j in (i + 1)..<tiles.count {
                let intersection = tiles[i].frame.intersection(tiles[j].frame)
                let area = intersection.width * intersection.height
                XCTAssertLessThan(area, 1.0, "Tiles \(i) and \(j) overlap")
            }
        }
    }

    func testSmallChildrenBelowFractionAreExcluded() {
        let big = makeNode(name: "big.txt", size: 10000)
        let tiny = makeNode(name: "tiny.txt", size: 1)
        let root = makeNode(name: "root", size: 0, children: [big, tiny])

        let tiles = TreemapLayout.layout(root: root, in: canvas)
        let names = tiles.map(\.node.name)

        XCTAssertTrue(names.contains("big.txt"))
        XCTAssertFalse(names.contains("tiny.txt"))
    }

    func testFilteredChildrenStillFillCanvas() {
        // One big child plus many tiny ones that fall below the 2% threshold.
        // The displayed tiles should still fill the entire canvas — the filtered
        // children's space gets redistributed, not left as a gap.
        var children = [makeNode(name: "big.txt", size: 10000)]
        children += (1...20).map { makeNode(name: "tiny\($0).txt", size: 100) }
        let root = makeNode(name: "root", size: 0, children: children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)
        let topLevel = tiles.filter { $0.depth == 0 }
        let totalArea = topLevel.reduce(0.0) { $0 + $1.frame.width * $1.frame.height }

        XCTAssertEqual(topLevel.count, 1) // only the big one survives the filter
        XCTAssertEqual(Double(totalArea), Double(canvas.width * canvas.height), accuracy: 1.0)
    }

    func testEmptyRootProducesNoTiles() {
        let root = makeNode(name: "root", size: 0)
        let tiles = TreemapLayout.layout(root: root, in: canvas)
        XCTAssertTrue(tiles.isEmpty)
    }

    func testDepthLimitIsRespected() {
        // Build a tree deeper than maxDepth
        var deepChild = makeNode(name: "leaf", size: 1000)
        for i in 0..<LayoutConstants.maxDepth + 2 {
            deepChild = makeNode(name: "dir\(i)", size: 0, children: [deepChild])
        }

        let tiles = TreemapLayout.layout(root: deepChild, in: canvas)
        let maxObservedDepth = tiles.map(\.depth).max() ?? 0

        XCTAssertLessThanOrEqual(maxObservedDepth, LayoutConstants.maxDepth)
    }

    func testTilesStayWithinCanvas() {
        let children = (1...8).map { makeNode(name: "file\($0).txt", size: Int64($0 * 150)) }
        let root = makeNode(name: "root", size: 0, children: children)

        let tiles = TreemapLayout.layout(root: root, in: canvas)

        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.frame.minX, canvas.minX - 1)
            XCTAssertGreaterThanOrEqual(tile.frame.minY, canvas.minY - 1)
            XCTAssertLessThanOrEqual(tile.frame.maxX, canvas.maxX + 1)
            XCTAssertLessThanOrEqual(tile.frame.maxY, canvas.maxY + 1)
        }
    }
}
