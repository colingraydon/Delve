import SwiftUI

/// Visual styling for the treemap: tile colors, gradients, labels, hover.
///
/// Color is *sibling-distinct*, not type-based: each item at a level takes a
/// hue rotated from its neighbor by the golden-ratio conjugate, so adjacent
/// tiles always sit far apart on the wheel and a folder full of one file type
/// reads as a spectrum rather than a single blob. `colorIndex` is the tile's
/// rank among its siblings (largest first), so the biggest item anchors a
/// consistent hue and the same index yields the same color in the sidebar.
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

    /// 1/φ. Stepping the hue by this each index spreads colors so that no
    /// matter how many siblings there are, neighbors never bunch up.
    private static let goldenConjugate = 0.6180339887498949

    /// The fill color for the item ranked `index` among its siblings. The
    /// small `+0.03` offset anchors the biggest item at a warm red rather than
    /// dead-on primary red.
    static func sliceColor(index: Int, brightnessDelta: Double = 0) -> Color {
        let hue = (0.03 + Double(index) * goldenConjugate).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.60, brightness: clamp(0.80 + brightnessDelta))
    }

    /// The muted grey-blue of the "smaller items" bucket - deliberately
    /// desaturated so it recedes behind the vivid, individually-sized tiles.
    static func aggregateColor(brightnessDelta: Double = 0) -> Color {
        Color(hue: 0.62, saturation: 0.08, brightness: clamp(0.46 + brightnessDelta))
    }

    /// The flat color for a sidebar legend dot at a given sibling rank.
    static func legendColor(index: Int) -> Color {
        sliceColor(index: index, brightnessDelta: 0.04)
    }

    static let aggregateLegendColor = aggregateColor(brightnessDelta: 0.04)

    /// Vertical gradient shading for a tile, slightly lighter at the top for
    /// a hint of depth. Hover brightens the whole tile.
    static func shading(for tile: TileRect, in frame: CGRect, isHovered: Bool) -> GraphicsContext.Shading {
        let boost = isHovered ? hoverBrightnessBoost : 0
        let top: Color
        let bottom: Color
        switch tile.content {
        case .aggregate:
            top = aggregateColor(brightnessDelta: 0.06 + boost)
            bottom = aggregateColor(brightnessDelta: boost)
        case .node:
            top = sliceColor(index: tile.colorIndex, brightnessDelta: 0.08 + boost)
            bottom = sliceColor(index: tile.colorIndex, brightnessDelta: boost)
        }
        return .linearGradient(
            Gradient(colors: [top, bottom]),
            startPoint: CGPoint(x: frame.midX, y: frame.minY),
            endPoint: CGPoint(x: frame.midX, y: frame.maxY)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
