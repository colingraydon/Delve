import SwiftUI

struct TreemapView: View {
    let root: FileNode

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
            let hoveredID = hover?.tile.node.id

            Canvas { context, _ in
                // Draw shallower tiles first so deeper (nested) tiles paint on top.
                for tile in tiles.sorted(by: { $0.depth < $1.depth }) {
                    draw(tile: tile, isHovered: tile.node.id == hoveredID, in: &context)
                }
            }
            .task(id: LayoutKey(size: geo.size, rootID: root.id)) {
                tiles = TreemapLayout.layout(root: root, in: CGRect(origin: .zero, size: geo.size))
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
            .floatingTooltip(at: hover?.location) {
                if let node = hover?.tile.node {
                    TooltipCard {
                        FileSummaryLabel(node: node)
                    }
                }
            }
        }
    }

    /// Returns the deepest (topmost-drawn) tile containing the point.
    private func hitTest(_ point: CGPoint) -> TileRect? {
        tiles
            .filter { $0.frame.contains(point) }
            .max { $0.depth < $1.depth }
    }

    private func draw(tile: TileRect, isHovered: Bool, in context: inout GraphicsContext) {
        let inset = TreemapStyle.inset(forDepth: tile.depth)
        let frame = tile.frame.insetBy(dx: inset, dy: inset)
        guard frame.width > 0, frame.height > 0 else { return }

        let path = Path(roundedRect: frame, cornerRadius: TreemapStyle.cornerRadius)

        context.fill(path, with: .color(TreemapStyle.color(forDepth: tile.depth)))

        if isHovered {
            context.fill(path, with: .color(TreemapStyle.hoverOverlay))
            context.stroke(path, with: .color(TreemapStyle.hoverBorder), lineWidth: TreemapStyle.hoverBorderWidth)
        } else {
            context.stroke(path, with: .color(TreemapStyle.borderColor), lineWidth: TreemapStyle.borderWidth)
        }

        drawLabel(for: tile, in: frame, context: &context)
    }

    private func drawLabel(for tile: TileRect, in frame: CGRect, context: inout GraphicsContext) {
        guard frame.width >= TreemapStyle.minLabelWidth,
              frame.height >= TreemapStyle.minLabelHeight else { return }

        let text = Text(tile.node.name)
            .font(.system(size: TreemapStyle.labelFontSize, weight: .medium))
            .foregroundColor(TreemapStyle.labelColor)

        let resolved = context.resolve(text)
        let textSize = resolved.measure(in: frame.size)

        // Only draw if the label actually fits inside the tile.
        guard textSize.width <= frame.width - TreemapStyle.labelPadding * 2 else { return }

        context.draw(
            resolved,
            at: CGPoint(x: frame.minX + TreemapStyle.labelPadding + textSize.width / 2,
                        y: frame.minY + TreemapStyle.labelPadding + textSize.height / 2)
        )
    }
}

// Visual styling — placeholder palette by depth for now.
// Swap `color(forDepth:)` for a file-type / size color provider later.
enum TreemapStyle {
    static let cornerRadius: CGFloat = 4
    static let borderWidth: CGFloat = 1
    static let borderColor = Color.black.opacity(0.25)
    static let hoverOverlay = Color.white.opacity(0.18)
    static let hoverBorder = Color.white.opacity(0.9)
    static let hoverBorderWidth: CGFloat = 2
    static let labelColor = Color.white.opacity(0.9)
    static let labelFontSize: CGFloat = 11
    static let labelPadding: CGFloat = 4
    static let minLabelWidth: CGFloat = 40
    static let minLabelHeight: CGFloat = 18

    private static let palette: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.75),
        Color(red: 0.25, green: 0.55, blue: 0.70),
        Color(red: 0.30, green: 0.62, blue: 0.60),
        Color(red: 0.35, green: 0.68, blue: 0.52)
    ]

    static func color(forDepth depth: Int) -> Color {
        palette[min(depth, palette.count - 1)]
    }

    static func inset(forDepth depth: Int) -> CGFloat {
        depth == 0 ? 1 : 2
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
            ]),
            leaf("disk_image.dmg", 2_000_000_000)
        ])
    }
}
#endif
