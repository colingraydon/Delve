import Foundation

/// Formats byte counts as human-readable strings (e.g. "12.4 GB").
/// Reuse anywhere a file/folder size is displayed.
enum SizeFormatter {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
