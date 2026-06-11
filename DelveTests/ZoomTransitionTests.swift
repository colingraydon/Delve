import XCTest
@testable import Delve

final class ZoomTransitionTests: XCTestCase {
    private var root: FileNode!
    private var folder: FileNode!
    private var grandchild: FileNode!
    private var rootTiles: [TileRect]!
    private var folderTiles: [TileRect]!
    private let folderFrame = CGRect(x: 10, y: 20, width: 300, height: 200)

    override func setUp() {
        func node(_ name: String, isDirectory: Bool = true) -> FileNode {
            FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name,
                     isDirectory: isDirectory, isPackage: false, ownSize: 0)
        }
        root = node("root")
        folder = node("folder")
        grandchild = node("grandchild")
        folder.parent = root
        root.children = [folder]
        grandchild.parent = folder
        folder.children = [grandchild]

        rootTiles = [TileRect(frame: folderFrame, content: .node(folder))]
        folderTiles = [TileRect(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                content: .node(grandchild))]
    }

    func testDrillInProducesInwardTransitionFocusedOnChildTile() {
        let transition = ZoomTransition.between(
            oldRoot: root, oldTiles: rootTiles,
            newRoot: folder, newTiles: folderTiles
        )

        XCTAssertEqual(transition?.direction, .inward)
        XCTAssertEqual(transition?.focusRect, folderFrame)
        XCTAssertEqual(transition?.parentTiles.count, rootTiles.count)
        XCTAssertEqual(transition?.deeperTiles.count, folderTiles.count)
    }

    func testDrillOutProducesOutwardTransitionFocusedOnChildTile() {
        let transition = ZoomTransition.between(
            oldRoot: folder, oldTiles: folderTiles,
            newRoot: root, newTiles: rootTiles
        )

        XCTAssertEqual(transition?.direction, .outward)
        XCTAssertEqual(transition?.focusRect, folderFrame)
        XCTAssertEqual(transition?.parentTiles.count, rootTiles.count)
        XCTAssertEqual(transition?.deeperTiles.count, folderTiles.count)
    }

    func testMultiLevelJumpFocusesOnIntermediateAncestorTile() {
        // Jumping root → grandchild zooms through the folder's tile.
        let transition = ZoomTransition.between(
            oldRoot: root, oldTiles: rootTiles,
            newRoot: grandchild, newTiles: []
        )

        XCTAssertEqual(transition?.direction, .inward)
        XCTAssertEqual(transition?.focusRect, folderFrame)
    }

    func testUnrelatedRootsProduceNoTransition() {
        let other = FileNode(url: URL(fileURLWithPath: "/other"), name: "other",
                             isDirectory: true, isPackage: false, ownSize: 0)

        XCTAssertNil(ZoomTransition.between(
            oldRoot: root, oldTiles: rootTiles,
            newRoot: other, newTiles: []
        ))
    }

    func testMissingFocusTileProducesNoTransition() {
        // The child lies on the path but has no tile in the parent layout
        // (e.g. it was folded into the "smaller items" bucket).
        let aggregateOnly = [TileRect(frame: folderFrame, content: .aggregate(count: 3, totalSize: 99))]

        XCTAssertNil(ZoomTransition.between(
            oldRoot: root, oldTiles: aggregateOnly,
            newRoot: folder, newTiles: folderTiles
        ))
    }
}
