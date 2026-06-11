import Foundation

enum ScanError: Error {
    case accessDenied(URL)
    case notADirectory(URL)
}

struct DirectoryScanner {
    nonisolated init() {}

    /// Paths to exclude when scanning a given root. Scanning "/" must skip
    /// other mounted disks and the APFS volume group mounts - /System/Volumes
    /// re-exposes the Data volume whose contents already appear at /Users,
    /// /Applications, etc. via firmlinks, so descending into it would count
    /// everything twice.
    nonisolated static func systemSkipPaths(forScanRoot url: URL) -> Set<String> {
        url.standardizedFileURL.path == "/" ? ["/Volumes", "/System/Volumes"] : []
    }

    func scan(
        url: URL,
        rootName: String? = nil,
        skipping skipPaths: Set<String> = [],
        progress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> FileNode {
        // Detached so the blocking filesystem walk stays off the cooperative
        // pool; cancellation is forwarded by hand since detachment severs it.
        let task = Task.detached(priority: .userInitiated) {
            var fileCount = 0
            let root = try Self.scanRecursive(url: url, skipPaths: skipPaths,
                                              fileCount: &fileCount, progress: progress)
            guard let rootName, rootName != root.name else { return root }
            // Volume roots scan as "/" - rebuild the top node under its
            // display name ("Macintosh HD") so breadcrumbs read naturally.
            let renamed = FileNode(url: root.url, name: rootName, isDirectory: root.isDirectory,
                                   isPackage: root.isPackage, ownSize: root.ownSize)
            renamed.totalSize = root.totalSize
            renamed.children = root.children
            for child in renamed.children { child.parent = renamed }
            return renamed
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func scanRecursive(
        url: URL,
        skipPaths: Set<String>,
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
            if fileCount % 100 == 0 {
                try Task.checkCancellation()
                progress?(fileCount)
            }
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
            if !skipPaths.isEmpty && skipPaths.contains(childURL.standardizedFileURL.path) {
                continue
            }
            guard let child = try? scanRecursive(url: childURL, skipPaths: skipPaths,
                                                 fileCount: &fileCount, progress: progress) else {
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
