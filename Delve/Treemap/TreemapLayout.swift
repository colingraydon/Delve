import CoreGraphics

enum LayoutConstants {
    /// Children smaller than this fraction of the parent are merged into a
    /// single "smaller items" tile instead of being shown individually.
    static let minTileFraction: Double = 0.02
    /// Tiles smaller than this (points, either dimension) are not drawn.
    static let minTileSize: CGFloat = 4
}

struct TileRect {
    enum Content {
        case node(FileNode)
        case aggregate(count: Int, totalSize: Int64)
    }

    let frame: CGRect
    let content: Content
    /// Rank among siblings (largest first), driving the sibling-distinct fill
    /// color. The aggregate bucket ignores it (it's drawn a fixed grey).
    let colorIndex: Int

    init(frame: CGRect, content: Content, colorIndex: Int = 0) {
        self.frame = frame
        self.content = content
        self.colorIndex = colorIndex
    }

    var totalSize: Int64 {
        switch content {
        case .node(let node): return node.totalSize
        case .aggregate(_, let size): return size
        }
    }

    var name: String {
        switch content {
        case .node(let node): return node.name
        case .aggregate(let count, _): return "\(count) smaller item\(count == 1 ? "" : "s")"
        }
    }

    var isDirectory: Bool {
        switch content {
        case .node(let node): return node.isDirectory
        case .aggregate: return false
        }
    }

    /// Stable identity for hover tracking. At most one aggregate exists per level.
    var id: AnyHashable {
        switch content {
        case .node(let node): return node.id
        case .aggregate: return "aggregate"
        }
    }
}

/// Squarified treemap layout, single level: lays out the direct children of a
/// node as tiles filling the rect, with aspect ratios kept close to square.
struct TreemapLayout {
    private struct Item {
        let size: Int64
        let content: TileRect.Content
        let colorIndex: Int
    }

    static func layout(root: FileNode, in rect: CGRect) -> [TileRect] {
        guard root.totalSize > 0, rect.width > 0, rect.height > 0 else { return [] }

        let threshold = Double(root.totalSize) * LayoutConstants.minTileFraction
        var big: [(size: Int64, content: TileRect.Content)] = []
        var smallCount = 0
        var smallTotal: Int64 = 0

        for child in root.children where child.totalSize > 0 {
            if Double(child.totalSize) >= threshold {
                big.append((child.totalSize, .node(child)))
            } else {
                smallCount += 1
                smallTotal += child.totalSize
            }
        }

        big.sort { $0.size > $1.size }

        // Color index is the post-sort rank, so the same item gets the same
        // hue here and in the sidebar (which sorts identically).
        var items = big.enumerated().map { index, item in
            Item(size: item.size, content: item.content, colorIndex: index)
        }
        if smallCount > 0 {
            items.append(Item(size: smallTotal,
                              content: .aggregate(count: smallCount, totalSize: smallTotal),
                              colorIndex: -1))
        }

        guard !items.isEmpty else { return [] }

        let total = items.reduce(0) { $0 + $1.size }
        var results: [TileRect] = []
        squarifyRow(items: items, totalSize: total, rect: rect, results: &results)
        return results
    }

    private static func squarifyRow(items: [Item], totalSize: Int64, rect: CGRect, results: inout [TileRect]) {
        guard !items.isEmpty, totalSize > 0, rect.width > 0, rect.height > 0 else { return }

        var row: [Item] = []
        var remaining = items

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

        let leftover = layoutRow(row, totalSize: totalSize, rect: rect, results: &results)

        if !remaining.isEmpty {
            let remainingSize = remaining.reduce(0) { $0 + $1.size }
            squarifyRow(items: remaining, totalSize: remainingSize, rect: leftover, results: &results)
        }
    }

    private static func layoutRow(_ row: [Item], totalSize: Int64, rect: CGRect, results: inout [TileRect]) -> CGRect {
        let rowSize = row.reduce(0) { $0 + $1.size }
        let rowFraction = Double(rowSize) / Double(totalSize)
        let isHorizontal = rect.width >= rect.height

        var offset: CGFloat = 0
        let rowLength = isHorizontal ? rect.width * CGFloat(rowFraction) : rect.height * CGFloat(rowFraction)
        let stripLength = isHorizontal ? rect.height : rect.width

        for item in row {
            let itemFraction = Double(item.size) / Double(rowSize)
            let itemLength = stripLength * CGFloat(itemFraction)
            let frame: CGRect
            if isHorizontal {
                frame = CGRect(x: rect.minX, y: rect.minY + offset, width: rowLength, height: itemLength)
            } else {
                frame = CGRect(x: rect.minX + offset, y: rect.minY, width: itemLength, height: rowLength)
            }
            offset += itemLength
            results.append(TileRect(frame: frame, content: item.content, colorIndex: item.colorIndex))
        }

        if isHorizontal {
            return CGRect(x: rect.minX + rowLength, y: rect.minY, width: rect.width - rowLength, height: rect.height)
        } else {
            return CGRect(x: rect.minX, y: rect.minY + rowLength, width: rect.width, height: rect.height - rowLength)
        }
    }

    private static func worstAspectRatio(_ row: [Item], totalSize: Int64, rect: CGRect) -> Double {
        guard !row.isEmpty, totalSize > 0 else { return .infinity }

        let rowSize = row.reduce(0) { $0 + $1.size }
        let rowFraction = Double(rowSize) / Double(totalSize)
        let isHorizontal = rect.width >= rect.height
        let stripLength = Double(isHorizontal ? rect.height : rect.width)
        let rowThickness = Double(isHorizontal ? rect.width : rect.height) * rowFraction

        guard rowThickness > 0 else { return .infinity }

        return row.map { item -> Double in
            let itemFraction = Double(item.size) / Double(rowSize)
            let itemLength = stripLength * itemFraction
            let w = max(rowThickness, itemLength)
            let h = min(rowThickness, itemLength)
            return h > 0 ? w / h : .infinity
        }.max() ?? .infinity
    }
}
