import SwiftUI

/// The recent runs and walks included in the coach payload, newest first.
///
/// Names the sources (`coachWorkoutSources`) because "where did this come from"
/// is a different question from "what is it", and a Strava-imported run is data
/// the user connected a second service to share.
struct CoachPreviewWorkoutsCard: View {
    let workouts: [LatestWorkout]

    var body: some View {
        CardSection(title: "Recent runs and walks") {
            if workouts.isEmpty {
                Text("Not shared — no runs or walks recorded yet.")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(workouts.enumerated()), id: \.offset) { _, w in
                        CoachDataRow(
                            label: "\(w.type.capitalized) · \(prettyDate(w.date))",
                            value: "\(miles(w.distanceMiles)) mi · \(w.pace)"
                        )
                    }
                }
                Text("Each entry includes its source (\(coachWorkoutSources(workouts))).")
                    .font(Typography.caption).foregroundColor(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
