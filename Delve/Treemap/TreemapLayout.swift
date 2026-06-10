import CoreGraphics

struct LayoutConstants {
    static let minTileFraction: Double = 0.02
    static let minTileSize: CGFloat = 5
    static let maxDepth: Int = 3
}

struct TileRect {
    let node: FileNode
    let frame: CGRect
    let depth: Int
}

struct TreemapLayout {
    static func layout(root: FileNode, in rect: CGRect) -> [TileRect] {
        guard root.totalSize > 0 else { return [] }
        var results: [TileRect] = []
        layoutChildren(of: root, in: rect, depth: 0, results: &results)
        return results
    }

    private static func layoutChildren(
        of node: FileNode,
        in rect: CGRect,
        depth: Int,
        results: inout [TileRect]
    ) {
        guard depth < LayoutConstants.maxDepth else { return }

        let eligible = node.children.filter { child in
            guard node.totalSize > 0 else { return false }
            let fraction = Double(child.totalSize) / Double(node.totalSize)
            return fraction >= LayoutConstants.minTileFraction
        }

        guard !eligible.isEmpty else { return }

        // Normalize to the sum of *displayed* nodes so tiles fill the rect.
        // Filtered-out small children simply have their space redistributed.
        let eligibleSize = eligible.reduce(0) { $0 + $1.totalSize }
        let tiles = squarify(nodes: eligible, totalSize: eligibleSize, in: rect, depth: depth)

        for tile in tiles {
            guard tile.frame.width >= LayoutConstants.minTileSize,
                  tile.frame.height >= LayoutConstants.minTileSize else { continue }

            results.append(tile)

            if tile.node.isDirectory && !tile.node.children.isEmpty {
                layoutChildren(of: tile.node, in: tile.frame, depth: depth + 1, results: &results)
            }
        }
    }

    // Squarified treemap algorithm: lays out nodes as rectangles with
    // aspect ratios as close to square as possible.
    private static func squarify(nodes: [FileNode], totalSize: Int64, in rect: CGRect, depth: Int) -> [TileRect] {
        let sorted = nodes.sorted { $0.totalSize > $1.totalSize }
        var results: [TileRect] = []
        squarifyRow(nodes: sorted, totalSize: totalSize, rect: rect, depth: depth, results: &results)
        return results
    }

    private static func squarifyRow(
        nodes: [FileNode],
        totalSize: Int64,
        rect: CGRect,
        depth: Int,
        results: inout [TileRect]
    ) {
        guard !nodes.isEmpty, totalSize > 0, rect.width > 0, rect.height > 0 else { return }

        var row: [FileNode] = []
        var remaining = nodes

        while !remaining.isEmpty {
            let candidate = remaining[0]
            let newRow = row + [candidate]

            if row.isEmpty || worstAspectRatio(newRow, totalSize: totalSize, rect: rect) <=
                worstAspectRatio(row, totalSize: totalSize, rect: rect) {
                row.append(candidate)
                remaining.removeFirst()
            } else {
                break
            }
        }

        let leftoverRect = layoutRow(row, totalSize: totalSize, rect: rect, depth: depth, results: &results)

        if !remaining.isEmpty {
            let remainingSize = remaining.reduce(0) { $0 + $1.totalSize }
            squarifyRow(nodes: remaining, totalSize: remainingSize, rect: leftoverRect, depth: depth, results: &results)
        }
    }

    private static func layoutRow(
        _ row: [FileNode],
        totalSize: Int64,
        rect: CGRect,
        depth: Int,
        results: inout [TileRect]
    ) -> CGRect {
        let rowSize = row.reduce(0) { $0 + $1.totalSize }
        let rowFraction = Double(rowSize) / Double(totalSize)
        let isHorizontal = rect.width >= rect.height

        var offset: CGFloat = 0
        let rowLength: CGFloat = isHorizontal ? rect.width * CGFloat(rowFraction) : rect.height * CGFloat(rowFraction)
        let stripLength: CGFloat = isHorizontal ? rect.height : rect.width

        for node in row {
            let nodeFraction = Double(node.totalSize) / Double(rowSize)
            let nodeLength = stripLength * CGFloat(nodeFraction)

            let frame: CGRect
            if isHorizontal {
                frame = CGRect(x: rect.minX, y: rect.minY + offset, width: rowLength, height: nodeLength)
            } else {
                frame = CGRect(x: rect.minX + offset, y: rect.minY, width: nodeLength, height: rowLength)
            }
            offset += nodeLength

            results.append(TileRect(node: node, frame: frame, depth: depth))
        }

        let leftover: CGRect
        if isHorizontal {
            leftover = CGRect(
                x: rect.minX + rowLength,
                y: rect.minY,
                width: rect.width - rowLength,
                height: rect.height
            )
        } else {
            leftover = CGRect(
                x: rect.minX,
                y: rect.minY + rowLength,
                width: rect.width,
                height: rect.height - rowLength
            )
        }

        return leftover
    }

    private static func worstAspectRatio(_ row: [FileNode], totalSize: Int64, rect: CGRect) -> Double {
        guard !row.isEmpty, totalSize > 0 else { return .infinity }

        let rowSize = row.reduce(0) { $0 + $1.totalSize }
        let rowFraction = Double(rowSize) / Double(totalSize)
        let isHorizontal = rect.width >= rect.height
        let stripLength = Double(isHorizontal ? rect.height : rect.width)
        let rowThickness = Double(isHorizontal ? rect.width : rect.height) * rowFraction

        guard rowThickness > 0 else { return .infinity }

        return row.map { node -> Double in
            let nodeFraction = Double(node.totalSize) / Double(rowSize)
            let nodeLength = stripLength * nodeFraction
            let w = max(rowThickness, nodeLength)
            let h = min(rowThickness, nodeLength)
            return h > 0 ? w / h : .infinity
        }.max() ?? .infinity
    }
}
