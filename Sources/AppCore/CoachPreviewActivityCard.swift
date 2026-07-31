import SwiftUI

/// Today's activity totals as the coach would receive them.
///
/// When Apple Health isn't connected every row reads "Not shared" and a caption
/// says why, rather than the card vanishing — "nothing is shared from Health"
/// is a fact worth showing on a screen about what gets shared.
struct CoachPreviewActivityCard: View {
    let state: TodayState

    var body: some View {
        CardSection(title: "Today's activity") {
            VStack(spacing: 0) {
                CoachDataRow(label: "Date",
                             value: state.date.isEmpty ? nil : prettyDate(state.date))
                CoachDataRow(label: "Steps", value: connected
                             ? "\(formatted(state.steps)) of \(formatted(state.goalSteps))" : nil)
                CoachDataRow(label: "Active minutes", value: connected
                             ? "\(state.activeMinutes)" : nil)
                CoachDataRow(label: "Distance", value: connected
                             ? "\(miles(state.distanceMiles)) mi" : nil)
                CoachDataRow(label: "Energy burned", value: connected
                             ? "\(formatted(state.activeEnergyKcal)) kcal" : nil)
                CoachDataRow(label: "Since last movement", value: connected
                             ? movementLabel(state.minutesSinceLastMovement) : nil)
            }
            if !connected {
                Text("Apple Health isn't connected, so no activity data is shared.")
                    .font(Typography.caption).foregroundColor(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connected: Bool { state.healthKitConnected }
}
