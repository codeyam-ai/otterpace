import SwiftUI

// MARK: - Heatmap legend

/// The less → more key. Mirrors the ramp exactly so the card explains itself.
struct HeatmapLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("Less")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Palette.subtle)
            ForEach(0...ActivityHeatmap.maxLevel, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(HeatmapRamp.fill(level: level))
                    .frame(width: 11, height: 11)
            }
            Text("More")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Palette.subtle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color key, less to more activity")
    }
}
