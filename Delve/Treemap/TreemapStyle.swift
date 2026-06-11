import SwiftUI

/// What kind of thing a tile represents, for coloring. Directories get the
/// azure family; files get a category color by extension.
enum TileCategory {
    case directory
    case package
    case video
    case image
    case audio
    case archive
    case code
    case document
    case other
    case aggregate

    static func of(_ tile: TileRect) -> TileCategory {
        switch tile.content {
        case .aggregate:
            return .aggregate
        case .node(let node):
            return of(node)
        }
    }

    static func of(_ node: FileNode) -> TileCategory {
        if node.isPackage { return .package }
        if node.isDirectory { return .directory }
        return of(extension: node.url.pathExtension.lowercased())
    }

    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "raw", "cr2", "nef", "psd", "svg", "webp"]
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "aiff", "aif", "alac", "mid"]
    private static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "iso", "pkg", "jar", "xip"]
    private static let codeExtensions: Set<String> = ["swift", "c", "cpp", "h", "hpp", "m", "mm", "java", "py", "js", "ts", "tsx", "go", "rs", "rb", "sh", "json", "xml", "yml", "yaml", "toml", "html", "css"]
    private static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "txt", "rtf", "md", "pages", "key", "ppt", "pptx", "xls", "xlsx", "csv", "numbers", "epub"]

    private static func of(extension ext: String) -> TileCategory {
        if videoExtensions.contains(ext) { return .video }
        if imageExtensions.contains(ext) { return .image }
        if audioExtensions.contains(ext) { return .audio }
        if archiveExtensions.contains(ext) { return .archive }
        if codeExtensions.contains(ext) { return .code }
        if documentExtensions.contains(ext) { return .document }
        return .other
    }
}

/// Visual styling for the treemap: tile colors, gradients, labels, hover.
enum TreemapStyle {
    static let inset: CGFloat = 1.5
    static let cornerRadius: CGFloat = 5
    static let borderWidth: CGFloat = 1
    static let borderColor = Color.black.opacity(0.28)

    static let hoverBorder = Color.white.opacity(0.95)
    static let hoverBorderWidth: CGFloat = 2
    static let hoverBrightnessBoost: Double = 0.12

    static let labelColor = Color.white.opacity(0.95)
    static let sizeLabelColor = Color.white.opacity(0.7)
    static let labelFontSize: CGFloat = 11
    static let sizeFontSize: CGFloat = 10
    static let labelPadding: CGFloat = 6
    static let minLabelWidth: CGFloat = 40
    static let minLabelHeight: CGFloat = 18
    static let minSizeLabelHeight: CGFloat = 42

    /// The dark backdrop behind the tiles; shows through tile gaps and during
    /// zoom transitions, so it doubles as the "grout" color.
    static let background = LinearGradient(
        colors: [
            Color(hue: 0.62, saturation: 0.30, brightness: 0.17),
            Color(hue: 0.65, saturation: 0.35, brightness: 0.11)
        ],
        startPoint: .top, endPoint: .bottom
    )

    private struct HSB {
        let hue: Double
        let saturation: Double
        let brightness: Double

        func color(brightnessDelta: Double = 0, saturationDelta: Double = 0) -> Color {
            Color(hue: hue,
                  saturation: max(0, min(1, saturation + saturationDelta)),
                  brightness: max(0, min(1, brightness + brightnessDelta)))
        }
    }

    private static func base(for tile: TileRect) -> HSB {
        base(for: TileCategory.of(tile), name: tile.name)
    }

    private static func base(for category: TileCategory, name: String) -> HSB {
        switch category {
        case .directory:
            // Slight per-name hue drift so adjacent folders read as distinct.
            let drift = Double(stableHash(name) % 64) / 64.0 * 0.07
            return HSB(hue: 0.55 + drift, saturation: 0.60, brightness: 0.62)
        case .package:   return HSB(hue: 0.97, saturation: 0.48, brightness: 0.72)
        case .video:     return HSB(hue: 0.75, saturation: 0.45, brightness: 0.70)
        case .image:     return HSB(hue: 0.36, saturation: 0.45, brightness: 0.60)
        case .audio:     return HSB(hue: 0.88, saturation: 0.42, brightness: 0.70)
        case .archive:   return HSB(hue: 0.10, saturation: 0.55, brightness: 0.72)
        case .code:      return HSB(hue: 0.46, saturation: 0.45, brightness: 0.58)
        case .document:  return HSB(hue: 0.58, saturation: 0.38, brightness: 0.72)
        case .other:     return HSB(hue: 0.60, saturation: 0.22, brightness: 0.52)
        case .aggregate: return HSB(hue: 0.62, saturation: 0.10, brightness: 0.42)
        }
    }

    /// The flat color a node renders as - for legend dots in the sidebar,
    /// kept in sync with tile fills by construction.
    static func legendColor(for node: FileNode) -> Color {
        base(for: TileCategory.of(node), name: node.name).color(brightnessDelta: 0.08)
    }

    static let aggregateLegendColor = HSB(hue: 0.62, saturation: 0.10, brightness: 0.42).color(brightnessDelta: 0.08)

    /// Vertical gradient shading for a tile, slightly lighter at the top for
    /// a hint of depth. Hover brightens the whole tile.
    static func shading(for tile: TileRect, in frame: CGRect, isHovered: Bool) -> GraphicsContext.Shading {
        let hsb = base(for: tile)
        let boost = isHovered ? hoverBrightnessBoost : 0
        return .linearGradient(
            Gradient(colors: [
                hsb.color(brightnessDelta: 0.09 + boost, saturationDelta: -0.05),
                hsb.color(brightnessDelta: boost)
            ]),
            startPoint: CGPoint(x: frame.midX, y: frame.minY),
            endPoint: CGPoint(x: frame.midX, y: frame.maxY)
        )
    }

    /// djb2 over the name - stable across launches, unlike `Hashable`.
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for scalar in string.unicodeScalars {
            hash = hash &* 33 &+ UInt64(scalar.value)
        }
        return hash
    }
}
