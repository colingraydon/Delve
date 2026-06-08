import Foundation

enum ScanError: Error {
    case accessDenied(URL)
    case notADirectory(URL)
}

struct DirectoryScanner {
    nonisolated init() {}

    func scan(url: URL, progress: (@Sendable (Int) -> Void)? = nil) async throws -> FileNode {
        try await Task.detached(priority: .userInitiated) {
            var fileCount = 0
            return try Self.scanRecursive(url: url, fileCount: &fileCount, progress: progress)
        }.value
    }

    private nonisolated static func scanRecursive(
        url: URL,
        fileCount: inout Int,
        progress: (@Sendable (Int) -> Void)?
    ) throws -> FileNode {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .fileSizeKey,
            .nameKey
        ]

        let values = try url.resourceValues(forKeys: resourceKeys)

        if values.isSymbolicLink == true {
            return FileNode(
                url: url,
                name: values.name ?? url.lastPathComponent,
                isDirectory: false,
                isPackage: false,
                ownSize: Int64(values.fileSize ?? 0)
            )
        }

        let isDirectory = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false
        let name = values.name ?? url.lastPathComponent

        // Treat packages (.app, .bundle, etc.) as leaf nodes
        if isPackage && isDirectory {
            let size = packageSize(at: url)
            return FileNode(url: url, name: name, isDirectory: true, isPackage: true, ownSize: size)
        }

        if !isDirectory {
            fileCount += 1
            if fileCount % 100 == 0 { progress?(fileCount) }
            return FileNode(
                url: url,
                name: name,
                isDirectory: false,
                isPackage: false,
                ownSize: Int64(values.fileSize ?? 0)
            )
        }

        let node = FileNode(url: url, name: name, isDirectory: true, isPackage: false, ownSize: 0)

        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        for childURL in contents {
            guard let child = try? scanRecursive(url: childURL, fileCount: &fileCount, progress: progress) else {
                continue
            }
            child.parent = node
            node.children.append(child)
            node.totalSize += child.totalSize
        }

        return node
    }

    private nonisolated static func packageSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
