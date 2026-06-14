import SwiftUI

struct TreemapView: View {
    let root: FileNode
    /// Bump to force a relayout after the tree mutates in place (e.g. trash).
    var revision: Int = 0

    /// Called when a directory tile is clicked, to drill into it.
    /// Stays a callback so this view remains a pure renderer with no nav state.
    var onDrillInto: (FileNode) -> Void = { _ in }
    /// Called when the user picks "Move to Trash" on a tile.
    var onTrash: (FileNode) -> Void = { _ in }

    @State private var tiles: [TileRect] = []
    @State private var hover: HoverState?
    @State private var zoom: ZoomTransition?
    @State private var zoomProgress: CGFloat = 1
    @State private var drag: DragState?
    /// What the current `tiles` were computed for, so we can tell a drill
    /// (animate) from a resize or rescan (don't).
    @State private var laidOutRoot: FileNode?
    @State private var laidOutSize: CGSize = .zero

    private struct HoverState {
        let tile: TileRect
        let location: CGPoint
    }

    private struct DragState {
        let node: FileNode
        let isProtected: Bool
        var location: CGPoint
    }

    private struct LayoutKey: Equatable {
        let size: CGSize
        let rootID: FileNode.ID
        let revision: Int
    }

    var body: some View {
        GeometryReader { geo in
            ZoomableTreemapCanvas(
                progress: zoomProgress,
                zoom: zoom,
                tiles: tiles,
                hoveredID: hover?.tile.id
            )
            .onChange(of: LayoutKey(size: geo.size, rootID: root.id, revision: revision), initial: true) {
                relayout(size: geo.size)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    if zoom == nil, drag == nil, let tile = hitTest(point) {
                        hover = HoverState(tile: tile, location: point)
                    } else {
                        hover = nil
                    }
                case .ended:
                    hover = nil
                }
            }
            .gesture(dragToTrashGesture(canvasSize: geo.size))
            .gesture(
                SpatialTapGesture().onEnded { event in
                    guard let tile = hitTest(event.location) else { return }
                    // Only directories drill in. Files and the aggregate tile
                    // are terminal - you're already viewing their folder.
                    if case .node(let node) = tile.content, node.isDirectory, !node.children.isEmpty {
                        onDrillInto(node)
                    }
                }
            )
            .contextMenu {
                if case .node(let node)? = hover?.tile.content {
                    tileMenu(for: node)
                }
            }
            .floatingTooltip(at: hover?.location) {
                if let tile = hover?.tile {
                    TooltipCard {
                        FileSummaryLabel(name: tile.name, size: tile.totalSize)
                    }
                }
            }
            .overlay {
                if let drag {
                    TrashDropZone(
                        active: trashZoneContains(drag.location, canvasSize: geo.size),
                        isProtected: drag.isProtected
                    )
                    .position(trashZoneCenter(canvasSize: geo.size))
                    .transition(.scale.combined(with: .opacity))

                    DragGhost(node: drag.node)
                        .position(x: drag.location.x, y: drag.location.y - 28)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Drag to trash

    private func dragToTrashGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if drag == nil {
                    // Pick up whatever real file/folder the drag started on.
                    // The aggregate tile has no single URL, so it stays put.
                    guard zoom == nil,
                          let tile = hitTest(value.startLocation),
                          case .node(let node) = tile.content else { return }
                    hover = nil
                    withAnimation(.spring(duration: 0.25)) {
                        drag = DragState(node: node,
                                         isProtected: TrashGuard.isProtected(node.url),
                                         location: value.location)
                    }
                } else {
                    drag?.location = value.location
                }
            }
            .onEnded { value in
                guard let drag else { return }
                withAnimation(.spring(duration: 0.25)) {
                    self.drag = nil
                }
                if !drag.isProtected, trashZoneContains(value.location, canvasSize: canvasSize) {
                    onTrash(drag.node)
                }
            }
    }

    private func trashZoneCenter(canvasSize: CGSize) -> CGPoint {
        CGPoint(x: canvasSize.width / 2, y: canvasSize.height - 64)
    }

    private func trashZoneContains(_ point: CGPoint, canvasSize: CGSize) -> Bool {
        let center = trashZoneCenter(canvasSize: canvasSize)
        return hypot(point.x - center.x, point.y - center.y) < 52
    }

    @ViewBuilder
    private func tileMenu(for node: FileNode) -> some View {
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        Divider()
        if TrashGuard.isProtected(node.url) {
            Button("Move to Trash") {}
                .disabled(true)
            Text("Protected - Delve won't trash system or personal folders")
        } else {
            Button("Move to Trash", role: .destructive) {
                onTrash(node)
            }
        }
    }

    // MARK: - Layout & zoom transitions

    private func relayout(size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let newTiles = TreemapLayout.layout(root: root, in: rect)
        hover = nil

        // Animate only when this is a pure navigation: same canvas, a tree we
        // were already showing, moving to an ancestor or descendant of it.
        if let oldRoot = laidOutRoot, oldRoot !== root, size == laidOutSize, !tiles.isEmpty,
           let transition = ZoomTransition.between(
               oldRoot: oldRoot, oldTiles: tiles,
               newRoot: root, newTiles: newTiles
           ) {
            zoom = transition
            tiles = newTiles
            zoomProgress = 0
            withAnimation(.smooth(duration: 0.5)) {
                zoomProgress = 1
            } completion: {
                zoom = nil
            }
        } else {
            zoom = nil
            zoomProgress = 1
            tiles = newTiles
        }

        laidOutRoot = root
        laidOutSize = size
    }

    /// Tiles are disjoint at a single level, so the first containing tile wins.
    private func hitTest(_ point: CGPoint) -> TileRect? {
        tiles.first { $0.frame.contains(point) }
    }
}

/// The drop target that appears while dragging a tile: a trash can that
/// lights up red when the drag is over it - or shows a lock for items the
/// TrashGuard protects.
private struct TrashDropZone: View {
    let active: Bool
    let isProtected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isProtected ? AnyShapeStyle(.gray.opacity(0.6))
                                      : AnyShapeStyle(.red.opacity(active ? 0.95 : 0.55)))
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
                Image(systemName: isProtected ? "lock.fill" : (active ? "trash.fill" : "trash"))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
            .scaleEffect(active && !isProtected ? 1.18 : 1)
            .animation(.spring(duration: 0.2), value: active)

            Text(isProtected ? "Protected" : "Move to Trash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.5)))
        }
    }
}

/// The chip that rides along under the cursor while dragging a tile.
private struct DragGhost: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(.secondary)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220)
                .fixedSize(horizontal: true, vertical: false)
            Text(SizeFormatter.string(node.totalSize))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }
}

/// The actual renderer. Conforms to `Animatable` so SwiftUI interpolates
/// `progress` per frame and the Canvas redraws each step of the zoom.
private struct ZoomableTreemapCanvas: View, Animatable {
    var progress: CGFloat
    let zoom: ZoomTransition?
    let tiles: [TileRect]
    let hoveredID: AnyHashable?

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let fullRect = CGRect(origin: .zero, size: size)
            if let zoom, progress < 1 {
                drawZoom(zoom, fullRect: fullRect, in: &context)
            } else {
                for tile in tiles {
                    draw(tile: tile, frame: tile.frame, isHovered: tile.id == hoveredID, in: &context)
                }
            }
        }
    }

    private func drawZoom(_ zoom: ZoomTransition, fullRect: CGRect, in context: inout GraphicsContext) {
        // The rect the deeper level occupies right now: a tile growing to fill
        // the view (inward) or the view shrinking back into a tile (outward).
        let morphRect: CGRect
        let deeperOpacity: Double
        switch zoom.direction {
        case .inward:
            morphRect = lerp(from: zoom.focusRect, to: fullRect, progress)
            deeperOpacity = Double(progress)
        case .outward:
            morphRect = lerp(from: fullRect, to: zoom.focusRect, progress)
            deeperOpacity = Double(1 - progress)
        }

        // Parent level, scaled so its focused tile tracks morphRect. The rest
        // of the level slides off-screen as the camera dives in (or back).
        for tile in zoom.parentTiles {
            let frame = remap(tile.frame, from: zoom.focusRect, to: morphRect)
            guard frame.intersects(fullRect) else { continue }
            draw(tile: tile, frame: frame, isHovered: false, in: &context)
        }

        // Deeper level, compressed into morphRect, cross-fading over the
        // focused tile it grows out of (or shrinks back into).
        context.drawLayer { layer in
            layer.opacity = deeperOpacity
            layer.clip(to: Path(roundedRect: morphRect.insetBy(dx: TreemapStyle.inset, dy: TreemapStyle.inset),
                                cornerRadius: TreemapStyle.cornerRadius))
            for tile in zoom.deeperTiles {
                let frame = remap(tile.frame, from: fullRect, to: morphRect)
                draw(tile: tile, frame: frame, isHovered: false, in: &layer)
            }
        }
    }

    private func lerp(from: CGRect, to: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (to.minX - from.minX) * t,
            y: from.minY + (to.minY - from.minY) * t,
            width: from.width + (to.width - from.width) * t,
            height: from.height + (to.height - from.height) * t
        )
    }

    /// Maps `rect` through the affine transform that takes `from` onto `to`.
    private func remap(_ rect: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return rect }
        let sx = to.width / from.width
        let sy = to.height / from.height
        return CGRect(
            x: to.minX + (rect.minX - from.minX) * sx,
            y: to.minY + (rect.minY - from.minY) * sy,
            width: rect.width * sx,
            height: rect.height * sy
        )
    }

    // MARK: - Tile drawing

    private func draw(tile: TileRect, frame rawFrame: CGRect, isHovered: Bool, in context: inout GraphicsContext) {
        let frame = rawFrame.insetBy(dx: TreemapStyle.inset, dy: TreemapStyle.inset)
        guard frame.width >= LayoutConstants.minTileSize, frame.height >= LayoutConstants.minTileSize else { return }

        let path = Path(roundedRect: frame, cornerRadius: TreemapStyle.cornerRadius)
        context.fill(path, with: TreemapStyle.shading(for: tile, in: frame, isHovered: isHovered))

        if isHovered {
            context.stroke(path, with: .color(TreemapStyle.hoverBorder), lineWidth: TreemapStyle.hoverBorderWidth)
        } else {
            context.stroke(path, with: .color(TreemapStyle.borderColor), lineWidth: TreemapStyle.borderWidth)
        }

        drawDirectoryChevron(for: tile, in: frame, context: &context)
        drawLabel(for: tile, in: frame, context: &context)
    }

    /// Fades labels in as a tile approaches the size where they fit, instead
    /// of popping - matters mid-zoom, when frames cross thresholds every frame.
    private func labelFade(_ frame: CGRect, minWidth: CGFloat, minHeight: CGFloat) -> Double {
        let wFade = min(1, max(0, (frame.width - minWidth) / 24))
        let hFade = min(1, max(0, (frame.height - minHeight) / 12))
        return Double(wFade * hFade)
    }

    /// A small chevron in the corner of directory tiles signals "click to drill in".
    private func drawDirectoryChevron(for tile: TileRect, in frame: CGRect, context: inout GraphicsContext) {
        let fade = labelFade(frame, minWidth: 30, minHeight: 26)
        guard tile.isDirectory, fade > 0 else { return }
        let chevron = Text(Image(systemName: "chevron.right"))
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(TreemapStyle.labelColor.opacity(0.65 * fade))
        context.draw(context.resolve(chevron), at: CGPoint(x: frame.maxX - 10, y: frame.minY + 11))
    }

    private func drawLabel(for tile: TileRect, in frame: CGRect, context: inout GraphicsContext) {
        let fade = labelFade(frame, minWidth: TreemapStyle.minLabelWidth, minHeight: TreemapStyle.minLabelHeight)
        guard fade > 0 else { return }

        // Leave room for the chevron on directory tiles.
        let maxWidth = frame.width - TreemapStyle.labelPadding * 2 - (tile.isDirectory ? 14 : 0)
        guard let (resolvedName, nameSize) = fittedText(
            tile.name,
            font: .system(size: TreemapStyle.labelFontSize, weight: .medium),
            color: TreemapStyle.labelColor.opacity(fade),
            maxWidth: maxWidth,
            context: context
        ) else { return }

        let nameY = frame.minY + TreemapStyle.labelPadding + nameSize.height / 2
        context.draw(resolvedName, at: CGPoint(x: frame.minX + TreemapStyle.labelPadding, y: nameY), anchor: .leading)

        // On taller tiles, show the size beneath the name so big tiles aren't empty.
        let sizeFade = labelFade(frame, minWidth: TreemapStyle.minLabelWidth, minHeight: TreemapStyle.minSizeLabelHeight)
        guard sizeFade > 0 else { return }
        guard let (resolvedSize, sizeSize) = fittedText(
            SizeFormatter.string(tile.totalSize),
            font: .system(size: TreemapStyle.sizeFontSize),
            color: TreemapStyle.sizeLabelColor.opacity(sizeFade),
            maxWidth: maxWidth,
            context: context
        ) else { return }

        context.draw(
            resolvedSize,
            at: CGPoint(x: frame.minX + TreemapStyle.labelPadding,
                        y: nameY + nameSize.height / 2 + sizeSize.height / 2 + 2),
            anchor: .leading
        )
    }

    /// Resolves text for drawing, measured at its true single-line width
    /// (measuring against the tile's size lets the text *wrap* and falsely
    /// pass a width check - the cause of labels spilling across tiles).
    /// Truncates with an ellipsis when the full string doesn't fit; returns
    /// nil when even a few characters won't.
    private func fittedText(
        _ string: String,
        font: Font,
        color: Color,
        maxWidth: CGFloat,
        context: GraphicsContext
    ) -> (GraphicsContext.ResolvedText, CGSize)? {
        guard maxWidth > 10 else { return nil }
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        func resolve(_ s: String) -> (GraphicsContext.ResolvedText, CGSize) {
            let resolved = context.resolve(Text(s).font(font).foregroundColor(color))
            return (resolved, resolved.measure(in: unbounded))
        }

        let full = resolve(string)
        if full.1.width <= maxWidth { return full }

        // Binary-search the longest prefix that fits with an ellipsis.
        let chars = Array(string)
        var low = 1
        var high = chars.count - 1
        var best: (GraphicsContext.ResolvedText, CGSize)?
        while low <= high {
            let mid = (low + high) / 2
            let candidate = resolve(String(chars[0..<mid]) + "\u{2026}")
            if candidate.1.width <= maxWidth {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        // Fewer than ~4 visible characters reads as noise; drop the label.
        return high >= 3 ? best : nil
    }
}

#if DEBUG
#Preview {
    TreemapView(root: FileNode.previewTree())
        .background(TreemapStyle.background)
        .frame(width: 800, height: 600)
}

extension FileNode {
    /// A fake tree for previews and visual testing - no scanner required.
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
