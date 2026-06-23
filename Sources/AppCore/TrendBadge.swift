import SwiftUI

// Colored pill describing the week's training-load trend. Spiking reads amber
// (caution), recovering reads lilac, building reads green, steady reads blue.
struct TrendBadge: View {
    let trend: String

    private var color: Color {
        switch trend {
        case "spiking": return Palette.amber
        case "recovering": return Palette.lilac
        case "building": return Palette.go
        default: return Palette.sky
        }
    }

    var body: some View {
        Text(trend.capitalized)
            .font(Typography.captionStrong)
            .foregroundColor(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.16)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Training load trend: \(trend)")
    }
}
