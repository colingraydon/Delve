import SwiftUI

/// A navigable treemap: breadcrumb on top, treemap below. Owns the navigation
/// state (which node is currently "zoomed into") and re-roots the map when a
/// directory is clicked or a breadcrumb is tapped.
struct DiskMapView: View {
    let root: FileNode

    @State private var currentNode: FileNode

    init(root: FileNode) {
        self.root = root
        _currentNode = State(initialValue: root)
    }

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(path: currentNode.pathFromRoot) { node in
                currentNode = node
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            TreemapView(root: currentNode) { node in
                currentNode = node
            }
        }
        // Reset to the new root if the underlying tree is replaced (e.g. a rescan).
        .onChange(of: root.id) {
            currentNode = root
        }
    }
}

#if DEBUG
#Preview {
    DiskMapView(root: FileNode.previewTree())
        .frame(width: 800, height: 600)
}
#endif
