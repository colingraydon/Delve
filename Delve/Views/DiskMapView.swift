import SwiftUI

/// A navigable treemap with a DaisyDisk-style sidebar: breadcrumbs on top,
/// map on the left, the current folder's contents listed on the right. Owns
/// the navigation state and the trash "collector": tiles dragged onto the can
/// queue up in a bottom tray, then "Move All to Trash" runs a single 5-second
/// countdown (with Undo) before anything is actually trashed.
struct DiskMapView: View {
    let root: FileNode

    @State private var currentNode: FileNode
    /// Bumped after in-place tree mutations (trash) to force a relayout.
    @State private var revision = 0
    /// Items queued for deletion, newest last. Persists across navigation.
    @State private var staged: [FileNode] = []
    /// True while the 5-second batch countdown is running.
    @State private var committing = false
    @State private var commitStart: Date = .now
    @State private var commitDeadline: Date = .now
    @State private var trashTask: Task<Void, Never>?
    @State private var trashError: String?

    init(root: FileNode) {
        self.root = root
        _currentNode = State(initialValue: root)
    }

    private var stagedIDs: Set<FileNode.ID> { Set(staged.map(\.id)) }

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

            // The collector docks below the map instead of floating over it,
            // so it never covers what you're looking at.
            if !staged.isEmpty {
                Divider()
                TrashCollectorBar(
                    items: staged,
                    committing: committing,
                    start: commitStart,
                    deadline: commitDeadline,
                    onRemove: { unstage($0) },
                    onClear: { clearStaged() },
                    onMoveAll: { moveAllToTrash() },
                    onUndo: { cancelCommit() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Reset to the new root if the underlying tree is replaced (e.g. a rescan):
        // the queued node references belong to the old tree.
        .onChange(of: root.id) {
            cancelCommit()
            staged = []
            currentNode = root
        }
        // Leaving the map abandons an in-flight countdown: not deleting is the
        // safe reading of an interrupted timer.
        .onDisappear {
            cancelCommit()
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
        ZStack {
            TreemapStyle.background

            TreemapView(
                root: currentNode,
                revision: revision,
                onDrillInto: { currentNode = $0 },
                onStage: { stage($0) },
                stagedIDs: stagedIDs
            )
            .padding(14)
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

    // MARK: - Trash collector

    private func stage(_ node: FileNode) {
        // The drop zone already refuses protected items; re-check defensively.
        guard !TrashGuard.isProtected(node.url) else {
            trashError = "\u{201C}\(node.name)\u{201D} is a protected system or personal folder."
            return
        }
        guard !staged.contains(where: { $0 === node }) else { return }
        // Queuing a folder supersedes any of its already-queued descendants;
        // queuing something already inside a queued folder is a no-op.
        if isDescendant(node, ofAny: staged) { return }
        withAnimation(.spring(duration: 0.3)) {
            staged.removeAll { $0.isDescendant(of: node) }
            staged.append(node)
            // Adding to the queue mid-countdown calls it off, back to review.
            if committing { stopCountdown() }
        }
    }

    private func unstage(_ node: FileNode) {
        withAnimation(.spring(duration: 0.3)) {
            staged.removeAll { $0 === node }
            if committing { stopCountdown() }
        }
    }

    private func clearStaged() {
        cancelCommit()
        withAnimation(.spring(duration: 0.3)) { staged = [] }
    }

    private func moveAllToTrash() {
        guard !staged.isEmpty, !committing else { return }
        commitStart = .now
        commitDeadline = .now.addingTimeInterval(5)
        withAnimation(.spring(duration: 0.3)) { committing = true }
        trashTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            commitAll()
        }
    }

    private func stopCountdown() {
        trashTask?.cancel()
        trashTask = nil
        committing = false
    }

    /// Undo: cancel the countdown but keep the queue so it can be reviewed.
    private func cancelCommit() {
        withAnimation(.spring(duration: 0.3)) { stopCountdown() }
    }

    private func commitAll() {
        // Skip anything detached by an earlier deletion, or nested under another
        // queued item (its folder will take it along).
        let toTrash = staged.filter { attachedToTree($0) && !isDescendant($0, ofAny: staged) }
        var failures: [String] = []

        for node in toTrash {
            do {
                try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
                // If we're viewing inside a deleted subtree, climb out first.
                if currentNode.pathFromRoot.contains(where: { $0 === node }) {
                    currentNode = node.parent ?? root
                }
                node.removeFromParent()
            } catch {
                failures.append("\(node.name): \(error.localizedDescription)")
            }
        }

        revision += 1
        withAnimation(.spring(duration: 0.3)) {
            staged = []
            committing = false
        }
        trashTask = nil
        if !failures.isEmpty {
            trashError = "Some items couldn't be moved to the Trash:\n" + failures.joined(separator: "\n")
        }
    }

    // MARK: - Tree relationship helpers

    private func attachedToTree(_ node: FileNode) -> Bool {
        node === root || node.isDescendant(of: root)
    }

    private func isDescendant(_ node: FileNode, ofAny nodes: [FileNode]) -> Bool {
        nodes.contains { $0 !== node && node.isDescendant(of: $0) }
    }
}

/// The DaisyDisk-style collector: a slim bar docked under the map listing what's
/// queued for the trash as horizontal chips, with a single "Move All to Trash"
/// that runs the 5-second countdown (a draining bar + Undo while it runs).
private struct TrashCollectorBar: View {
    let items: [FileNode]
    let committing: Bool
    let start: Date
    let deadline: Date
    let onRemove: (FileNode) -> Void
    let onClear: () -> Void
    let onMoveAll: () -> Void
    let onUndo: () -> Void

    private var totalSize: Int64 { items.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        HStack(spacing: 12) {
            summary
            Divider().frame(height: 34)

            if committing {
                countdown
            } else {
                chips
                Spacer(minLength: 8)
                Button("Clear", action: onClear)
                Button("Move All to Trash", role: .destructive, action: onMoveAll)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                    .disabled(items.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(height: 60)
        .background(.regularMaterial)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 1) {
                Text("Trash Collector")
                    .font(.subheadline.weight(.semibold))
                Text("\(items.count) item\(items.count == 1 ? "" : "s")  ·  \(SizeFormatter.string(totalSize))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(.secondary)
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 150)
                            .fixedSize()
                        Text(SizeFormatter.string(item.totalSize))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button {
                            onRemove(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from collector")
                    }
                    .font(.callout)
                    .padding(.leading, 9)
                    .padding(.trailing, 6)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.10)))
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var countdown: some View {
        // Per-frame draining bar (a system ProgressView(timerInterval:) visibly
        // jumps on its one-second ticks).
        TimelineView(.animation) { timeline in
            let total = deadline.timeIntervalSince(start)
            let remaining = max(0, deadline.timeIntervalSince(timeline.date))
            HStack(spacing: 12) {
                Text("Moving \(items.count) item\(items.count == 1 ? "" : "s") to Trash")
                    .font(.callout.weight(.medium))
                    .fixedSize()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(.red)
                            .frame(width: geo.size.width * (total > 0 ? remaining / total : 0))
                    }
                }
                .frame(height: 6)

                Text("\(Int(remaining.rounded(.up)))s")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28)

                Button("Undo", action: onUndo)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("z", modifiers: .command)
            }
        }
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
