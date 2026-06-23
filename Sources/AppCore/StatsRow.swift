import SwiftUI

// The three at-a-glance metric tiles: active minutes, distance, and time since
// the user last moved. The 3-up row reflows to a vertical stack at accessibility
// text sizes so the tiles never clip or truncate on large type / small screens.
struct StatsRow: View {
    let today: TodayState

    @Environment(\.dynamicTypeSize) private var typeSize

    private var tiles: [StatTile] {
        [
            StatTile(icon: "flame.fill", tint: Palette.brand,
                     value: "\(today.activeMinutes)", label: "active min"),
            StatTile(icon: "figure.walk", tint: Palette.go,
                     value: String(format: "%.1f", today.distanceMiles), label: "miles"),
            StatTile(icon: "clock.fill", tint: Palette.sky,
                     value: movementLabel(today.minutesSinceLastMovement), label: "since moving"),
        ]
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) { ForEach(0..<tiles.count, id: \.self) { tiles[$0] } }
        } else {
            HStack(spacing: 12) { ForEach(0..<tiles.count, id: \.self) { tiles[$0] } }
        }
    }
}
