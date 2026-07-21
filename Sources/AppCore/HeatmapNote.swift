import SwiftUI

// A quiet explanatory line inside the Progress card, used when a metric can't be
// drawn yet — e.g. steps-vs-goal before any per-day step series has synced.
// Stating the reason plainly beats rendering a grid of zeroes that would imply
// the user never moved.
struct HeatmapNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(Palette.subtle)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Layout.sm)
    }
}
