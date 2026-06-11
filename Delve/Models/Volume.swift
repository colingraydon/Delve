import Foundation

struct Volume: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    var isRemovable: Bool = false

    var isStartupDisk: Bool {
        url.path == "/"
    }

    var usedCapacity: Int64 {
        totalCapacity - availableCapacity
    }

    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    static func mountedVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsLocalKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: .skipHiddenVolumes
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true,
                  let name = values.volumeName,
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity
            else { return nil }

            return Volume(
                url: url,
                name: name,
                totalCapacity: Int64(total),
                availableCapacity: Int64(available),
                isRemovable: values.volumeIsRemovable ?? false
            )
        }
    }
}
