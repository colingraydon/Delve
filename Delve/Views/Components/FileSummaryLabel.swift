import SwiftUI

/// Name + size pairing for a file node. Composed into the hover tooltip now,
/// and reusable in the detail panel / list rows later.
struct FileSummaryLabel: View {
    let node: FileNode

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(node.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(SizeFormatter.string(node.totalSize))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
