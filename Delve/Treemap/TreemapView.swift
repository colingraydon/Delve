import SwiftUI

struct TreemapView: View {
    let root: FileNode

    /// Called when a directory tile is clicked, to drill into it.
    /// Stays a callback so this view remains a pure renderer with no nav state.
    var onDrillInto: (FileNode) -> Void = { _ in }

    // Layout is memoized via `.task(id:)` so it only recomputes when the size
    // or the tree changes — not on every hover move.
    @State private var tiles: [TileRect] = []
    @State private var hover: HoverState?

    private struct HoverState {
        let tile: TileRect
        let location: CGPoint
    }

    private struct LayoutKey: Hashable {
        let size: CGSize
        let rootID: FileNode.ID
    }

    var body: some View {
        GeometryReader { geo in
            let hoveredID = hover?.tile.id

            Canvas { context, _ in
                for tile in tiles {
                    draw(tile: tile, isHovered: tile.id == hoveredID, in: &context)
                }
            }
            .task(id: LayoutKey(size: geo.size, rootID: root.id)) {
                tiles = TreemapLayout.layout(root: root, in: CGRect(origin: .zero, size: geo.size))
                hover = nil
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    if let tile = hitTest(point) {
                        hover = HoverState(tile: tile, location: point)
                    } else {
                        hover = nil
                    }
                case .ended:
                    hover = nil
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { event in
                    guard let tile = hitTest(event.location) else { return }
                    // Only directories drill in. Files and the aggregate tile
                    // are terminal — you're already viewing their folder.
                    if case .node(let node) = tile.content, node.isDirectory, !node.children.isEmpty {
                        onDrillInto(node)
                    }
                }
            )
            .floatingTooltip(at: hover?.location) {
                if let tile = hover?.tile {
                    TooltipCard {
                        FileSummaryLabel(name: tile.name, size: tile.totalSize)
                    }
                }
            }
        }
    }

    /// Tiles are disjoint at a single level, so the first containing tile wins.
    private func hitTest(_ point: CGPoint) -> TileRect? {
        tiles.first { $0.frame.contains(point) }
    }

    private func draw(tile: TileRect, isHovered: Bool, in context: inout GraphicsContext) {
        let frame = tile.frame.insetBy(dx: TreemapStyle.inset, dy: TreemapStyle.inset)
        guard frame.width >= LayoutConstants.minTileSize, frame.height >= LayoutConstants.minTileSize else { return }

        let path = Path(roundedRect: frame, cornerRadius: TreemapStyle.cornerRadius)
        context.fill(path, with: .color(TreemapStyle.fill(for: tile)))

        if isHovered {
            context.fill(path, with: .color(TreemapStyle.hoverOverlay))
            context.stroke(path, with: .color(TreemapStyle.hoverBorder), lineWidth: TreemapStyle.hoverBorderWidth)
        } else {
            context.stroke(path, with: .color(TreemapStyle.borderColor), lineWidth: TreemapStyle.borderWidth)
        }

        drawDirectoryChevron(for: tile, in: frame, context: &context)
        drawLabel(for: tile, in: frame, context: &context)
    }

    /// A small chevron in the corner of directory tiles signals "click to drill in".
    private func drawDirectoryChevron(for tile: TileRect, in frame: CGRect, context: inout GraphicsContext) {
        guard tile.isDirectory, frame.width >= 30, frame.height >= 26 else { return }
        let chevron = Text(Image(systemName: "chevron.right"))
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(TreemapStyle.labelColor.opacity(0.65))
        context.draw(context.resolve(chevron), at: CGPoint(x: frame.maxX - 10, y: frame.minY + 11))
    }

    private func drawLabel(for tile: TileRect, in frame: CGRect, context: inout GraphicsContext) {
        guard frame.width >= TreemapStyle.minLabelWidth,
              frame.height >= TreemapStyle.minLabelHeight else { return }

        let name = Text(tile.name)
            .font(.system(size: TreemapStyle.labelFontSize, weight: .medium))
            .foregroundColor(TreemapStyle.labelColor)
        let resolvedName = context.resolve(name)
        let nameSize = resolvedName.measure(in: frame.size)
        guard nameSize.width <= frame.width - TreemapStyle.labelPadding * 2 else { return }

        let nameY = frame.minY + TreemapStyle.labelPadding + nameSize.height / 2
        context.draw(resolvedName, at: CGPoint(x: frame.minX + TreemapStyle.labelPadding + nameSize.width / 2, y: nameY))

        // On taller tiles, show the size beneath the name so big tiles aren't empty.
        guard frame.height >= TreemapStyle.minSizeLabelHeight else { return }
        let sizeText = Text(SizeFormatter.string(tile.totalSize))
            .font(.system(size: TreemapStyle.sizeFontSize))
            .foregroundColor(TreemapStyle.sizeLabelColor)
        let resolvedSize = context.resolve(sizeText)
        let sizeSize = resolvedSize.measure(in: frame.size)
        guard sizeSize.width <= frame.width - TreemapStyle.labelPadding * 2 else { return }

        context.draw(
            resolvedSize,
            at: CGPoint(x: frame.minX + TreemapStyle.labelPadding + sizeSize.width / 2,
                        y: nameY + nameSize.height / 2 + sizeSize.height / 2 + 2)
        )
    }
}

// Visual styling. Folders get a slightly distinct shade and a chevron; the
// aggregate tile is muted. Full file-type coloring comes later.
enum TreemapStyle {
    static let inset: CGFloat = 2
    static let cornerRadius: CGFloat = 4
    static let borderWidth: CGFloat = 1
    static let borderColor = Color.black.opacity(0.25)

    static let hoverOverlay = Color.white.opacity(0.18)
    static let hoverBorder = Color.white.opacity(0.9)
    static let hoverBorderWidth: CGFloat = 2

    static let labelColor = Color.white.opacity(0.95)
    static let sizeLabelColor = Color.white.opacity(0.7)
    static let labelFontSize: CGFloat = 11
    static let sizeFontSize: CGFloat = 10
    static let labelPadding: CGFloat = 5
    static let minLabelWidth: CGFloat = 40
    static let minLabelHeight: CGFloat = 18
    static let minSizeLabelHeight: CGFloat = 40

    private static let fileFill = Color(red: 0.30, green: 0.50, blue: 0.68)
    private static let directoryFill = Color(red: 0.37, green: 0.57, blue: 0.75)
    private static let aggregateFill = Color(red: 0.40, green: 0.43, blue: 0.48)

    static func fill(for tile: TileRect) -> Color {
        switch tile.content {
        case .node(let node): return node.isDirectory ? directoryFill : fileFill
        case .aggregate: return aggregateFill
        }
    }
}

#if DEBUG
#Preview {
    TreemapView(root: FileNode.previewTree())
        .frame(width: 800, height: 600)
}

extension FileNode {
    /// A fake tree for previews and visual testing — no scanner required.
    static func previewTree() -> FileNode {
        func leaf(_ name: String, _ size: Int64) -> FileNode {
            FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name,
                     isDirectory: false, isPackage: false, ownSize: size)
        }
        func dir(_ name: String, _ children: [FileNode]) -> FileNode {
            let node = FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name,
                                isDirectory: true, isPackage: false, ownSize: 0)
            for child in children {
                child.parent = node
                node.children.append(child)
                node.totalSize += child.totalSize
            }
            return node
        }

        // A bunch of small files to demonstrate the "smaller items" bucket.
        let clutter = (1...18).map { leaf("note\($0).txt", 4_000_000) }

        return dir("root", [
            dir("Applications", [
                leaf("Xcode.app", 12_000_000_000),
                leaf("Photoshop.app", 4_000_000_000),
                leaf("Slack.app", 1_500_000_000)
            ]),
            dir("Movies", [
                leaf("vacation.mov", 8_000_000_000),
                leaf("project.mp4", 3_500_000_000)
            ]),
            dir("Documents", [
                leaf("thesis.pdf", 200_000_000),
                leaf("budget.xlsx", 50_000_000),
                dir("Code", [
                    leaf("repo1.zip", 800_000_000),
                    leaf("repo2.zip", 600_000_000)
                ])
            ] + clutter),
            leaf("disk_image.dmg", 2_000_000_000)
        ])
    }
}
#endif
