import SwiftUI

/// Name + size pairing. Composed into the hover tooltip now, and reusable in
/// the detail panel / list rows later. Takes raw name + bytes so it works for
/// both real nodes and aggregate ("N smaller items") tiles.
struct FileSummaryLabel: View {
    let name: String
    let size: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(SizeFormatter.string(size))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
