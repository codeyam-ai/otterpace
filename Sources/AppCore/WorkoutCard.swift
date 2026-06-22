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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Palette.subtle)
                Text(String(format: "%.1f mi · %@", workout.distanceMiles, workout.pace))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.ink)
                Text("\(workout.durationMinutes) min · \(prettyDate(workout.date)) · \(workout.source)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.subtle)
            }
            Spacer()
        }
        .padding(16)
        .cardStyle()
    }
}
