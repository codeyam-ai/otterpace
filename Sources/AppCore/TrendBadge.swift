import SwiftUI

// Colored pill describing the week's training-load trend. Spiking reads amber
// (caution), recovering reads lilac, building reads green, steady reads blue, and
// "insufficient" (not enough history to judge yet) reads a neutral, honest
// "Baseline" in subtle gray rather than a confident verdict.
struct TrendBadge: View {
    let trend: String

    private var color: Color {
        switch trend {
        case "spiking": return Palette.amber
        case "recovering": return Palette.lilac
        case "building": return Palette.go
        case "insufficient": return Palette.subtle
        default: return Palette.sky
        }
    }

    /// The pill's short label. "insufficient" is shown as "Baseline" — honest and
    /// readable, where the raw enum value would be clunky.
    private var label: String {
        trend == "insufficient" ? "Baseline" : trend.capitalized
    }

    /// The spoken trend for VoiceOver — the friendlier phrase for "insufficient".
    private var spokenTrend: String {
        trend == "insufficient" ? "still gathering your baseline" : trend
    }

    var body: some View {
        Text(label)
            .font(Typography.captionStrong)
            .foregroundColor(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.16)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Training load trend: \(spokenTrend)")
    }
}
