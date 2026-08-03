import SwiftUI

// The three at-a-glance metric tiles: active minutes, distance, and time since
// the user last moved. The 3-up row reflows to a vertical stack at accessibility
// text sizes so the tiles never clip or truncate on large type / small screens.
//
// On a day Health has recorded nothing at all, the tiles read `—` with a "no data
// yet" line instead of three zeroes: on a fresh install a row of `0`s reads as a
// judgment, and `movementLabel(0)` would cheerfully claim you moved "now". A
// genuine zero-step morning still shows `0` — that IS the day's data.
struct StatsRow: View {
    let today: TodayState

    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasData: Bool {
        hasDayData(steps: today.steps,
                   activeMinutes: today.activeMinutes,
                   distanceMiles: today.distanceMiles,
                   minutesSinceLastMovement: today.minutesSinceLastMovement)
    }

    private var noDataCaption: String? { hasData ? nil : "no data yet" }

    private var tiles: [StatTile] {
        [
            StatTile(icon: "flame.fill", tint: Palette.brand,
                     value: statValue("\(today.activeMinutes)", hasData: hasData),
                     label: "active min",
                     hint: .activeMinutes,
                     subtitle: noDataCaption,
                     accessibilityText: hasData
                        ? "\(today.activeMinutes) active minutes"
                        : "No active minutes recorded yet"),
            StatTile(icon: "figure.walk", tint: Palette.go,
                     value: statValue(String(format: "%.1f", today.distanceMiles), hasData: hasData),
                     label: "miles",
                     hint: .distance,
                     subtitle: noDataCaption,
                     accessibilityText: hasData
                        ? "\(String(format: "%.1f", today.distanceMiles)) miles"
                        : "No distance recorded yet"),
            // "since moving" read as a fragment, so the tile now says who moved.
            StatTile(icon: "clock.fill", tint: Palette.sky,
                     value: movementDisplay(minutes: today.minutesSinceLastMovement, hasData: hasData),
                     label: "since you moved",
                     hint: .sinceMoving,
                     subtitle: noDataCaption,
                     accessibilityText: hasData
                        ? "\(movementLabel(today.minutesSinceLastMovement)) since you last moved"
                        : "No movement recorded yet"),
        ]
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) { ForEach(0..<tiles.count, id: \.self) { tiles[$0] } }
        } else {
            HStack(alignment: .top, spacing: 12) { ForEach(0..<tiles.count, id: \.self) { tiles[$0] } }
        }
    }
}
