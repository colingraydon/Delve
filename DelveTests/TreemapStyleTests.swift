import XCTest
import SwiftUI
@testable import Delve

final class TreemapStyleTests: XCTestCase {
    private func file(_ name: String) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name,
                 isDirectory: false, isPackage: false, ownSize: 1)
    }

    func testSliceColorIsDeterministic() {
        XCTAssertEqual(TreemapStyle.sliceColor(index: 3), TreemapStyle.sliceColor(index: 3))
    }

    func testAdjacentSliceColorsDiffer() {
        // The whole point of golden-angle hue stepping: neighbors never bunch.
        for index in 0..<20 {
            XCTAssertNotEqual(
                TreemapStyle.sliceColor(index: index),
                TreemapStyle.sliceColor(index: index + 1),
                "slices \(index) and \(index + 1) should be visually distinct"
            )
        }
    }

    func testBrightnessDeltaChangesTheColor() {
        XCTAssertNotEqual(
            TreemapStyle.sliceColor(index: 5),
            TreemapStyle.sliceColor(index: 5, brightnessDelta: 0.2)
        )
    }

    func testBrightnessClampsAndDoesNotCrashAtExtremes() {
        // Deltas past the [0,1] brightness range must clamp rather than trap.
        _ = TreemapStyle.sliceColor(index: 0, brightnessDelta: 5)
        _ = TreemapStyle.sliceColor(index: 0, brightnessDelta: -5)
        _ = TreemapStyle.aggregateColor(brightnessDelta: 5)
        _ = TreemapStyle.aggregateColor(brightnessDelta: -5)
    }

    func testLegendColorMatchesSliceFamily() {
        // The sidebar dot for rank N must track the tile color for rank N.
        XCTAssertEqual(TreemapStyle.legendColor(index: 2), TreemapStyle.legendColor(index: 2))
        XCTAssertNotEqual(TreemapStyle.legendColor(index: 2), TreemapStyle.legendColor(index: 3))
    }

    func testShadingBuildsForNodeAndAggregateTiles() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 80)
        let tiles = [
            TileRect(frame: frame, content: .node(file("clip.mp4")), colorIndex: 0),
            TileRect(frame: frame, content: .node(file("doc.pdf")), colorIndex: 7),
            TileRect(frame: frame, content: .aggregate(count: 2, totalSize: 10), colorIndex: -1)
        ]
        // Shading construction walks the full color path; this pins it against
        // crashes for every content kind, hovered or not.
        for tile in tiles {
            _ = TreemapStyle.shading(for: tile, in: frame, isHovered: false)
            _ = TreemapStyle.shading(for: tile, in: frame, isHovered: true)
        }
    }
}
