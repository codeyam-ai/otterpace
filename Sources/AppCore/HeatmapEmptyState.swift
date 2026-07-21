import SwiftUI

// The heatmap's day-one prompt, shown when nothing has been logged in the
// visible span. This stands in for the whole Activity History screen's empty
// state — the heatmap leads the screen, so showing both would stack two empty
// messages on top of each other.
struct HeatmapEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            BuddyView(mood: .ready, size: 72)
            Text("No movement logged yet")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(Palette.ink)
            Text("Log a walk or run and your first squares light up here.")
                .font(.system(size: 13))
                .foregroundColor(Palette.ink.opacity(0.82))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.sm)
        .accessibilityElement(children: .combine)
    }
}
