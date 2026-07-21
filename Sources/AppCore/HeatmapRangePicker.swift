import SwiftUI

// The heatmap's visible-span selector — Week / Month / 3-Month. Secondary to the
// metric filter, so it reads as small capsules rather than competing with the
// segmented control above the grid.
struct HeatmapRangePicker: View {
    @Binding var range: HeatmapRange

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HeatmapRange.allCases, id: \.self) { r in
                Button {
                    range = r
                } label: {
                    Text(r.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(r == range ? Palette.onAccent : Palette.subtle)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(r == range ? Palette.brand : Palette.ink.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.label) range")
                .accessibilityAddTraits(r == range ? [.isSelected] : [])
            }
        }
    }
}
