import XCTest
import SwiftUI
@testable import Delve

final class TreemapStyleTests: XCTestCase {
    private func file(_ name: String) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name,
                 isDirectory: false, isPackage: false, ownSize: 1)
    }

    private func directory(_ name: String) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name,
                 isDirectory: true, isPackage: false, ownSize: 0)
    }

    func testCategoryByExtension() {
        XCTAssertEqual(TileCategory.of(file("clip.mp4")), .video)
        XCTAssertEqual(TileCategory.of(file("photo.JPG")), .image)
        XCTAssertEqual(TileCategory.of(file("song.mp3")), .audio)
        XCTAssertEqual(TileCategory.of(file("backup.zip")), .archive)
        XCTAssertEqual(TileCategory.of(file("main.swift")), .code)
        XCTAssertEqual(TileCategory.of(file("report.pdf")), .document)
        XCTAssertEqual(TileCategory.of(file("mystery.xyz")), .other)
        XCTAssertEqual(TileCategory.of(file("no_extension")), .other)
    }

    func testDirectoryAndPackageCategories() {
        XCTAssertEqual(TileCategory.of(directory("Documents")), .directory)

        let app = FileNode(url: URL(fileURLWithPath: "/Xcode.app"), name: "Xcode.app",
                           isDirectory: true, isPackage: true, ownSize: 1)
        XCTAssertEqual(TileCategory.of(app), .package)
    }

    func testTileCategoryMatchesNodeCategory() {
        let node = file("movie.mkv")
        let tile = TileRect(frame: .zero, content: .node(node))
        XCTAssertEqual(TileCategory.of(tile), TileCategory.of(node))
    }

    func testAggregateTileCategory() {
        let tile = TileRect(frame: .zero, content: .aggregate(count: 5, totalSize: 100))
        XCTAssertEqual(TileCategory.of(tile), .aggregate)
    }

    func testLegendColorIsStableForSameName() {
        XCTAssertEqual(
            TreemapStyle.legendColor(for: directory("Documents")),
            TreemapStyle.legendColor(for: directory("Documents"))
        )
    }

    func testLegendColorDriftsAcrossDirectoryNames() {
        XCTAssertNotEqual(
            TreemapStyle.legendColor(for: directory("Documents")),
            TreemapStyle.legendColor(for: directory("Movies"))
        )
    }

    func testLegendColorDiffersByCategory() {
        XCTAssertNotEqual(
            TreemapStyle.legendColor(for: file("clip.mp4")),
            TreemapStyle.legendColor(for: file("backup.zip"))
        )
    }

    func testShadingIsBuildableForEveryTileKind() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 80)
        let tiles = [
            TileRect(frame: frame, content: .node(file("clip.mp4"))),
            TileRect(frame: frame, content: .node(directory("Documents"))),
            TileRect(frame: frame, content: .aggregate(count: 2, totalSize: 10))
        ]
        // Shading construction walks the full palette path; this pins it
        // against crashes for every content kind, hovered or not.
        for tile in tiles {
            _ = TreemapStyle.shading(for: tile, in: frame, isHovered: false)
            _ = TreemapStyle.shading(for: tile, in: frame, isHovered: true)
        }
    }
}
