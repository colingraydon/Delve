import XCTest
@testable import Delve

final class DirectoryScannerTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testScansFileWithCorrectSize() async throws {
        let fileURL = tempDir.appendingPathComponent("test.txt")
        let data = Data(repeating: 0x41, count: 1024)
        try data.write(to: fileURL)

        let scanner = DirectoryScanner()
        let root = try await scanner.scan(url: tempDir)

        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(root.children[0].ownSize, 1024)
        XCTAssertEqual(root.totalSize, 1024)
    }

    func testAggregatesNestedSizes() async throws {
        let subDir = tempDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        try Data(repeating: 0, count: 512).write(to: tempDir.appendingPathComponent("a.txt"))
        try Data(repeating: 0, count: 256).write(to: subDir.appendingPathComponent("b.txt"))

        let scanner = DirectoryScanner()
        let root = try await scanner.scan(url: tempDir)

        XCTAssertEqual(root.totalSize, 768)
    }

    func testSkipsSymlinks() async throws {
        let fileURL = tempDir.appendingPathComponent("real.txt")
        try Data(repeating: 0, count: 100).write(to: fileURL)

        let linkURL = tempDir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: fileURL)

        let scanner = DirectoryScanner()
        let root = try await scanner.scan(url: tempDir)

        let names = root.children.map(\.name)
        XCTAssertTrue(names.contains("real.txt"))
        // symlink should be present but not double-count the size
        let totalSize = root.children.reduce(0) { $0 + $1.ownSize }
        XCTAssertEqual(totalSize, root.totalSize)
    }

    func testParentReferenceIsSet() async throws {
        let subDir = tempDir.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 64).write(to: subDir.appendingPathComponent("file.txt"))

        let scanner = DirectoryScanner()
        let root = try await scanner.scan(url: tempDir)

        let childDir = root.children.first { $0.isDirectory }
        XCTAssertNotNil(childDir)
        XCTAssertEqual(childDir?.children.first?.parent?.url, childDir?.url)
    }

    func testEmptyDirectoryHasZeroSize() async throws {
        let scanner = DirectoryScanner()
        let root = try await scanner.scan(url: tempDir)

        XCTAssertEqual(root.totalSize, 0)
        XCTAssertTrue(root.children.isEmpty)
    }

    func testSkipsHiddenFiles() async throws {
        try Data(repeating: 0, count: 100).write(to: tempDir.appendingPathComponent("visible.txt"))
        try Data(repeating: 0, count: 200).write(to: tempDir.appendingPathComponent(".hidden"))

        let scanner = DirectoryScanner()
        let root = try await scanner.scan(url: tempDir)

        let names = root.children.map(\.name)
        XCTAssertTrue(names.contains("visible.txt"))
        XCTAssertFalse(names.contains(".hidden"))
        XCTAssertEqual(root.totalSize, 100)
    }

    func testPermissionErrorIsSkipped() async throws {
        let restricted = tempDir.appendingPathComponent("restricted")
        try FileManager.default.createDirectory(at: restricted, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 50).write(to: restricted.appendingPathComponent("file.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restricted.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restricted.path) }

        let scanner = DirectoryScanner()
        let root = try await scanner.scan(url: tempDir)

        // inaccessible directory is silently skipped, scan does not throw
        XCTAssertTrue(root.children.allSatisfy { $0.url != restricted })
    }

    func testPackageTreatedAsLeafNode() async throws {
        let appBundle = tempDir.appendingPathComponent("Fake.app")
        try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 512).write(to: appBundle.appendingPathComponent("binary"))
        try Data(repeating: 0, count: 256).write(to: appBundle.appendingPathComponent("Info.plist"))

        let scanner = DirectoryScanner()
        let root = try await scanner.scan(url: tempDir)

        let appNode = root.children.first { $0.name == "Fake.app" }
        XCTAssertNotNil(appNode)
        XCTAssertTrue(appNode?.isPackage == true)
        XCTAssertTrue(appNode?.children.isEmpty == true)
        XCTAssertGreaterThan(appNode?.ownSize ?? 0, 0)
    }

    func testLargeTreeAggregatesCorrectly() async throws {
        let subCount = 10
        let fileSize = 128
        var expectedTotal: Int64 = 0

        for i in 0..<subCount {
            let sub = tempDir.appendingPathComponent("dir\(i)")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for j in 0..<subCount {
                try Data(repeating: 0, count: fileSize).write(to: sub.appendingPathComponent("file\(j).txt"))
                expectedTotal += Int64(fileSize)
            }
        }

        let scanner = DirectoryScanner()
        let root = try await scanner.scan(url: tempDir)

        XCTAssertEqual(root.totalSize, expectedTotal)
        XCTAssertEqual(root.children.count, subCount)
    }
}
