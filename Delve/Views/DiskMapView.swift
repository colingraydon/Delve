import SwiftUI

/// A navigable treemap with a DaisyDisk-style sidebar: breadcrumbs on top,
/// map on the left, the current folder's contents listed on the right. Owns
/// the navigation state and the move-to-trash flow (a 5-second countdown
/// with Undo before anything is actually trashed).
struct DiskMapView: View {
    let root: FileNode

    @State private var currentNode: FileNode
    /// Bumped after in-place tree mutations (trash) to force a relayout.
    @State private var revision = 0
    @State private var pendingTrash: PendingTrash?
    @State private var trashTask: Task<Void, Never>?
    @State private var trashError: String?

    init(root: FileNode) {
        self.root = root
        _currentNode = State(initialValue: root)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                mapArea
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                SidebarView(node: currentNode, revision: revision) { node in
                    currentNode = node
                }
                .frame(minWidth: 220, idealWidth: 270, maxWidth: 380, maxHeight: .infinity)
            }
        }
        // Reset to the new root if the underlying tree is replaced (e.g. a rescan).
        .onChange(of: root.id) {
            cancelPendingTrash()
            currentNode = root
        }
        // Leaving the map (back to disks) abandons the countdown: not deleting
        // is the safe interpretation of an interrupted timer.
        .onDisappear {
            cancelPendingTrash()
        }
        .alert("Couldn't Move to Trash", isPresented: Binding(
            get: { trashError != nil },
            set: { if !$0 { trashError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(trashError ?? "")
        }
    }

    private var mapArea: some View {
        ZStack(alignment: .bottom) {
            TreemapStyle.background

            TreemapView(root: currentNode, revision: revision) { node in
                currentNode = node
            } onTrash: { node in
                requestTrash(node)
            }
            .padding(14)

            if let pendingTrash {
                TrashCountdownToast(pending: pendingTrash, onUndo: cancelPendingTrash)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                if let parent = currentNode.parent {
                    currentNode = parent
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(currentNode.parent == nil)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("Enclosing folder (⌘↑)")

            BreadcrumbView(path: currentNode.pathFromRoot) { node in
                currentNode = node
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Move to Trash (with countdown)

    private func requestTrash(_ node: FileNode) {
        // One pending deletion at a time: starting a second one commits the
        // first immediately rather than silently dropping it.
        if let earlier = pendingTrash {
            trashTask?.cancel()
            commit(earlier)
        }
        // Re-check at the moment of action; the context menu also disables these.
        guard !TrashGuard.isProtected(node.url) else {
            trashError = "\u{201C}\(node.name)\u{201D} is a protected system or personal folder."
            return
        }
        let pending = PendingTrash(node: node, start: .now, deadline: .now.addingTimeInterval(5))
        withAnimation(.spring(duration: 0.3)) {
            pendingTrash = pending
        }
        trashTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            commit(pending)
        }
    }

    private func cancelPendingTrash() {
        trashTask?.cancel()
        trashTask = nil
        withAnimation(.spring(duration: 0.3)) {
            pendingTrash = nil
        }
    }

    private func commit(_ pending: PendingTrash) {
        withAnimation(.spring(duration: 0.3)) {
            pendingTrash = nil
        }
        let node = pending.node
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            // If the view is somehow inside the deleted subtree, climb out first.
            if currentNode.pathFromRoot.contains(where: { $0 === node }) {
                currentNode = node.parent ?? root
            }
            node.removeFromParent()
            revision += 1
        } catch {
            trashError = error.localizedDescription
        }
    }
}

private struct PendingTrash {
    let node: FileNode
    let start: Date
    let deadline: Date
}

/// The countdown banner: a draining 5-second bar, the seconds remaining, and
/// a prominent Undo. The deletion only happens once the bar empties.
private struct TrashCountdownToast: View {
    let pending: PendingTrash
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash.fill")
                .font(.title3)
                .foregroundStyle(.red)

            // Drawn with TimelineView instead of ProgressView(timerInterval:):
            // the system bar re-anchors on its one-second ticks and visibly
            // jumps; recomputing the fraction per frame stays smooth.
            TimelineView(.animation) { timeline in
                let total = pending.deadline.timeIntervalSince(pending.start)
                let remaining = max(0, pending.deadline.timeIntervalSince(timeline.date))

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Moving \u{201C}\(pending.node.name)\u{201D} to Trash")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule()
                                    .fill(.red)
                                    .frame(width: geo.size.width * (total > 0 ? remaining / total : 0))
                            }
                        }
                        .frame(width: 240, height: 5)
                    }

                    Text("\(Int(remaining.rounded(.up)))s")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 30)
                }
            }

            Button("Undo", action: onUndo)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
    }
}

/// DaisyDisk-style legend: the current folder's children, biggest first, with
/// dots matching their tile colors. Directories drill in on click.
private struct SidebarView: View {
    let node: FileNode
    let revision: Int
    let onSelect: (FileNode) -> Void

    private var children: [FileNode] {
        node.children
            .filter { $0.totalSize > 0 }
            .sorted { $0.totalSize > $1.totalSize }
    }

    private var freeSpace: Int64? {
        guard let values = try? node.url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let available = values.volumeAvailableCapacity else { return nil }
        return Int64(available)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(SizeFormatter.string(node.totalSize))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    // Same largest-first order as the treemap layout, so a
                    // row's color dot matches its tile by sibling rank.
                    ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                        SidebarRow(node: child, colorIndex: index, onSelect: onSelect)
                    }
                }
                .padding(8)
            }

            if let freeSpace {
                Divider()
                HStack {
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 8, height: 8)
                    Text("free space")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(SizeFormatter.string(freeSpace))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

private struct SidebarRow: View {
    let node: FileNode
    let colorIndex: Int
    let onSelect: (FileNode) -> Void

    @State private var hovering = false

    private var isDrillable: Bool {
        node.isDirectory && !node.children.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(TreemapStyle.legendColor(index: colorIndex))
                .frame(width: 8, height: 8)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(SizeFormatter.string(node.totalSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(hovering && isDrillable ? 0.08 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .onTapGesture {
            if isDrillable { onSelect(node) }
        }
    }
}

#if DEBUG
#Preview {
    DiskMapView(root: FileNode.previewTree())
        .preferredColorScheme(.dark)
        .frame(width: 1000, height: 640)
}
#endif
