import SwiftUI

/// A clickable path trail (root › … › current). Each crumb jumps to that node.
/// Pure and reusable — give it a path and a selection callback.
struct BreadcrumbView: View {
    let path: [FileNode]
    let onSelect: (FileNode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    Button {
                        onSelect(node)
                    } label: {
                        Text(node.name)
                            .fontWeight(index == path.count - 1 ? .semibold : .regular)
                            .foregroundStyle(index == path.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)

                    if index < path.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
