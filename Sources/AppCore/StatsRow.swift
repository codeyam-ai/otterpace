import SwiftUI

// The three at-a-glance metric tiles: active minutes, distance, and time since
// the user last moved.
struct StatsRow: View {
    let today: TodayState

    var body: some View {
        HStack(spacing: 12) {
            StatTile(
                icon: "flame.fill",
                tint: Palette.brand,
                value: "\(today.activeMinutes)",
                label: "active min"
            )
            StatTile(
                icon: "figure.walk",
                tint: Palette.go,
                value: String(format: "%.1f", today.distanceMiles),
                label: "miles"
            )
            StatTile(
                icon: "clock.fill",
                tint: Palette.sky,
                value: movementLabel(today.minutesSinceLastMovement),
                label: "since moving"
            )
        }
    }
}
