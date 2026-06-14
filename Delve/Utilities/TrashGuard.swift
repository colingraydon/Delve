import Foundation

/// Decides whether a path is too sensitive to move to the Trash. The app's
/// whole point is deleting things, so this is the safety net: system
/// directories, the home folder and its standard subfolders, volume roots,
/// and media libraries are off limits. Contents *inside* protected folders
/// (e.g. ~/Library/Caches/Foo) are still deletable - only the folders
/// themselves are shielded.
enum TrashGuard {
    /// System paths protected along with everything inside them.
    private static let protectedTrees = [
        "/System", "/usr", "/bin", "/sbin", "/private", "/etc", "/var",
        "/opt", "/cores", "/dev", "/Library"
    ]

    /// Library packages that hold irreplaceable user data.
    private static let protectedPackageExtensions: Set<String> = [
        "photoslibrary", "musiclibrary", "tvlibrary", "aplibrary", "migratedphotolibrary"
    ]

    /// The user's real home directory. `NSHomeDirectory()` lies inside the
    /// sandbox (it points at the container), so ask the passwd database.
    static var realHomeDirectory: String {
        if let dir = getpwuid(getuid())?.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    static func isProtected(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path

        if path == "/" { return true }

        // Volume roots ("/Volumes/Backup") but not their contents.
        let components = path.split(separator: "/")
        if components.count <= 2 && components.first == "Volumes" { return true }

        for tree in protectedTrees where path == tree || path.hasPrefix(tree + "/") {
            return true
        }

        if protectedPackageExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        let home = realHomeDirectory
        if path == home { return true }

        // Standard top-level home folders - protect the folders themselves,
        // not what's in them.
        let standardHomeFolders = [
            "Desktop", "Documents", "Downloads", "Library", "Movies",
            "Music", "Pictures", "Public", "Applications"
        ]
        for folder in standardHomeFolders where path == home + "/" + folder {
            return true
        }
        // Everything under ~/Library except its grandchildren-and-deeper:
        // ~/Library/Caches itself stays, ~/Library/Caches/com.foo can go.
        let libraryPrefix = home + "/Library/"
        if path.hasPrefix(libraryPrefix) {
            let remainder = path.dropFirst(libraryPrefix.count)
            if !remainder.contains("/") { return true }
        }

        return false
    }
}
