import Foundation

final class FileNode: Identifiable, @unchecked Sendable {
    nonisolated let id = UUID()
    nonisolated let url: URL
    nonisolated let name: String
    nonisolated let isDirectory: Bool
    nonisolated let isPackage: Bool
    nonisolated(unsafe) var ownSize: Int64
    nonisolated(unsafe) var totalSize: Int64
    nonisolated(unsafe) var children: [FileNode]
    nonisolated(unsafe) weak var parent: FileNode?

    nonisolated init(url: URL, name: String, isDirectory: Bool, isPackage: Bool, ownSize: Int64) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.ownSize = ownSize
        self.totalSize = ownSize
        self.children = []
    }
}
