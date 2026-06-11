import CoreGraphics

/// Describes an in-flight zoom between two adjacent treemap levels.
/// The "deeper" level is always drawn inside `focusRect` as it morphs;
/// the "parent" level is drawn behind it, scaled so the focused tile
/// tracks the morphing rect.
struct ZoomTransition {
    enum Direction {
        case inward   // parent → child: focus tile grows to fill the view
        case outward  // child → parent: the view shrinks back into its tile
    }

    let direction: Direction
    let parentTiles: [TileRect]
    let deeperTiles: [TileRect]
    /// The focused tile's frame within the parent layout.
    let focusRect: CGRect

    /// Builds a transition if `newRoot` is an ancestor or descendant of
    /// `oldRoot`; returns nil for unrelated changes (e.g. a rescan).
    static func between(
        oldRoot: FileNode, oldTiles: [TileRect],
        newRoot: FileNode, newTiles: [TileRect]
    ) -> ZoomTransition? {
        // Drilling in: the old root is an ancestor of the new one. Zoom into
        // the old tile of whichever child of oldRoot lies on the path down.
        if let child = childOf(oldRoot, onPathTo: newRoot),
           let focus = frame(of: child, in: oldTiles) {
            return ZoomTransition(direction: .inward, parentTiles: oldTiles,
                                  deeperTiles: newTiles, focusRect: focus)
        }
        // Drilling out: the new root is an ancestor of the old one. Shrink the
        // old view back into its tile within the new layout.
        if let child = childOf(newRoot, onPathTo: oldRoot),
           let focus = frame(of: child, in: newTiles) {
            return ZoomTransition(direction: .outward, parentTiles: newTiles,
                                  deeperTiles: oldTiles, focusRect: focus)
        }
        return nil
    }

    private static func childOf(_ ancestor: FileNode, onPathTo descendant: FileNode) -> FileNode? {
        var node = descendant
        while let parent = node.parent {
            if parent === ancestor { return node }
            node = parent
        }
        return nil
    }

    private static func frame(of node: FileNode, in tiles: [TileRect]) -> CGRect? {
        tiles.first { tile in
            if case .node(let n) = tile.content { return n === node }
            return false
        }?.frame
    }
}
