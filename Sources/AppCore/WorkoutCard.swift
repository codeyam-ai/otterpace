import SwiftUI

// The most-recent run/walk/ride, summarized: distance and pace headline plus
// duration, date, and source (HealthKit or Strava).
struct WorkoutCard: View {
    let workout: LatestWorkout

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.go.opacity(0.16)).frame(width: 48, height: 48)
                Image(systemName: workout.type == "ride" ? "bicycle" : "figure.run")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Palette.go)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Latest \(workout.type)")
                    .font(Typography.captionStrong)
                    .foregroundColor(Palette.subtle)
                Text(String(format: "%.1f mi · %@", workout.distanceMiles, workout.pace))
                    .font(Typography.headline)
                    .foregroundColor(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(workout.durationMinutes) min · \(prettyDate(workout.date)) · \(workout.source)")
                    .font(Typography.caption)
                    .foregroundColor(Palette.subtle)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(16)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(format: "Latest %@, %.1f miles at %@, %d minutes, %@, from %@",
                   workout.type, workout.distanceMiles, workout.pace,
                   workout.durationMinutes, prettyDate(workout.date), workout.source)
        )
    }
}
