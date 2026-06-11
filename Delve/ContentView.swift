import SwiftUI
import UniformTypeIdentifiers

/// The app's top-level flow: disk list → map. Scan progress shows inline in
/// the disk list, DaisyDisk-style. Owns the folder picker and the scan task.
struct ContentView: View {
    private enum Phase {
        case home
        case loaded(FileNode)
    }

    @State private var phase: Phase = .home
    @State private var volumes: [Volume] = Volume.mountedVolumes()
    @State private var scanStatus: ScanStatus?
    @State private var scanTask: Task<Void, Never>?
    @State private var scanError: String?
    @State private var showingPicker = false
    /// What's currently shown in the map, so Rescan can repeat it.
    @State private var loadedScan: (url: URL, name: String)?

    var body: some View {
        Group {
            switch phase {
            case .home:
                HomeView(
                    volumes: volumes,
                    scanStatus: scanStatus,
                    onScanVolume: { startScan(of: $0.url, named: $0.name) },
                    onScanFolder: { showingPicker = true },
                    onCancelScan: { scanTask?.cancel() }
                )
                .onAppear { volumes = Volume.mountedVolumes() }
            case .loaded(let root):
                DiskMapView(root: root)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 500)
        .toolbar {
            if case .loaded = phase {
                ToolbarItemGroup {
                    Button {
                        phase = .home
                    } label: {
                        Label("Disks", systemImage: "internaldrive")
                    }
                    .help("Back to the disk list")

                    Button {
                        if let scan = loadedScan { startScan(of: scan.url, named: scan.name) }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Scan again (⌘R)")
                }
            }
        }
        .navigationTitle(loadedScan.map { "Delve - \($0.name)" } ?? "Delve")
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                startScan(of: url, named: url.lastPathComponent)
            }
        }
        .alert("Scan Failed", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanError ?? "")
        }
    }

    private func startScan(of url: URL, named name: String) {
        scanTask?.cancel()
        phase = .home
        scanStatus = ScanStatus(url: url, name: name, fileCount: 0)

        scanTask = Task {
            do {
                let root = try await DirectoryScanner().scan(
                    url: url,
                    rootName: name,
                    skipping: DirectoryScanner.systemSkipPaths(forScanRoot: url)
                ) { count in
                    Task { @MainActor in scanStatus?.fileCount = count }
                }
                scanStatus = nil
                loadedScan = (url, name)
                phase = .loaded(root)
            } catch is CancellationError {
                scanStatus = nil
            } catch {
                scanStatus = nil
                scanError = error.localizedDescription
            }
        }
    }
}

#Preview {
    ContentView()
}
