import SwiftUI

/// The progress of an in-flight scan, displayed inline in the row that
/// started it (DaisyDisk-style) rather than on a separate screen.
struct ScanStatus {
    let url: URL
    let name: String
    var fileCount: Int
}

/// The landing screen: every mounted disk as a clickable row, plus a
/// "Scan Folder…" escape hatch. Pure - the parent owns scanning.
struct HomeView: View {
    let volumes: [Volume]
    let scanStatus: ScanStatus?
    let onScanVolume: (Volume) -> Void
    let onScanFolder: () -> Void
    let onCancelScan: () -> Void

    /// The active scan, if it isn't one of the listed volumes (a folder scan).
    private var folderScan: ScanStatus? {
        guard let scanStatus else { return nil }
        return volumes.contains { $0.url.path == scanStatus.url.path } ? nil : scanStatus
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3.topleft.filled")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("Delve")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(volumes) { volume in
                        VolumeRow(
                            volume: volume,
                            scanStatus: scanStatus?.url.path == volume.url.path ? scanStatus : nil,
                            scanDisabled: scanStatus != nil,
                            onScan: { onScanVolume(volume) },
                            onCancel: onCancelScan
                        )
                    }
                    if let folderScan {
                        FolderScanRow(status: folderScan, onCancel: onCancelScan)
                    }
                }
                .padding(.horizontal, 16)
            }

            Divider()
                .padding(.top, 8)

            HStack {
                Button("Scan Folder…", action: onScanFolder)
                    .disabled(scanStatus != nil)
                Spacer()
                Text("Items are only ever moved to the Trash - never erased.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct VolumeRow: View {
    let volume: Volume
    let scanStatus: ScanStatus?
    let scanDisabled: Bool
    let onScan: () -> Void
    let onCancel: () -> Void

    @State private var hovering = false

    private var subtitle: String {
        let kind = volume.isStartupDisk ? "startup disk"
            : volume.isRemovable ? "external drive" : "volume"
        return "\(SizeFormatter.string(volume.totalCapacity))  \(kind)"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: volume.isRemovable ? "externaldrive.fill" : "internaldrive.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(volume.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                CapacityBar(fraction: volume.usedFraction)
                    .frame(maxWidth: 280)
            }

            Spacer()

            if let scanStatus {
                VStack(alignment: .trailing, spacing: 5) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 170)
                    Text("scanning…  \(scanStatus.fileCount.formatted()) files")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button("Cancel", action: onCancel)
            } else {
                Text("\(SizeFormatter.string(volume.availableCapacity)) free")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0.4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(hovering && scanStatus == nil ? 0.08 : 0.04))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .onTapGesture {
            if scanStatus == nil && !scanDisabled { onScan() }
        }
    }
}

/// Row for an in-flight folder (non-volume) scan.
private struct FolderScanRow: View {
    let status: ScanStatus
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.name)
                    .font(.headline)
                Text(status.url.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 170)
                Text("scanning…  \(status.fileCount.formatted()) files")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: onCancel)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))
    }
}

/// A slim used-space bar, gradient-filled like the map's palette.
private struct CapacityBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
    }
}

#Preview {
    HomeView(
        volumes: [
            Volume(url: URL(fileURLWithPath: "/"), name: "Macintosh HD",
                   totalCapacity: 494_000_000_000, availableCapacity: 80_500_000_000),
            Volume(url: URL(fileURLWithPath: "/Volumes/Backup"), name: "Backup",
                   totalCapacity: 2_000_000_000_000, availableCapacity: 750_000_000_000, isRemovable: true)
        ],
        scanStatus: ScanStatus(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", fileCount: 1_234_567),
        onScanVolume: { _ in }, onScanFolder: {}, onCancelScan: {}
    )
    .preferredColorScheme(.dark)
    .frame(width: 760, height: 420)
}
