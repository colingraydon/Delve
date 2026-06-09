import SwiftUI

/// A reusable floating card — a rounded, bordered, shadowed container that
/// wraps arbitrary content. Use for tooltips, hover details, small popovers.
struct TooltipCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .fixedSize()
    }
}

extension View {
    /// Floats `content` near a point given in this view's local coordinates.
    /// Pass `nil` for `point` to hide it. Reusable for any hover-driven overlay.
    ///
    /// Automatically flips to the other side of the cursor (and clamps) when it
    /// would overflow the container's right or bottom edge.
    func floatingTooltip<C: View>(
        at point: CGPoint?,
        gap: CGFloat = 12,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        overlay {
            GeometryReader { geo in
                if let point {
                    FloatingTooltip(point: point, gap: gap, containerSize: geo.size, content: content)
                }
            }
        }
    }
}

/// Positions tooltip content near a point, flipping/clamping to stay on screen.
private struct FloatingTooltip<C: View>: View {
    let point: CGPoint
    let gap: CGFloat
    let containerSize: CGSize
    @ViewBuilder var content: C

    @State private var size: CGSize = .zero

    var body: some View {
        // Flip to the left/top of the cursor if the default placement overflows.
        let overflowsRight = point.x + gap + size.width > containerSize.width
        let overflowsBottom = point.y + gap + size.height > containerSize.height
        let rawX = overflowsRight ? point.x - gap - size.width : point.x + gap
        let rawY = overflowsBottom ? point.y - gap - size.height : point.y + gap

        content
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: SizePreferenceKey.self, value: g.size)
                }
            )
            .onPreferenceChange(SizePreferenceKey.self) { size = $0 }
            .offset(
                x: clamp(rawX, min: 0, max: max(0, containerSize.width - size.width)),
                y: clamp(rawY, min: 0, max: max(0, containerSize.height - size.height))
            )
            .allowsHitTesting(false)
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
