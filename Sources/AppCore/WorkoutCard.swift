import SwiftUI

// The most-recent run/walk/ride, summarized: distance and pace headline plus
// duration, date, and source (HealthKit or Strava).
struct WorkoutCard: View {
    let workout: LatestWorkout
    /// The runner's own note about this workout, when they wrote one. Defaulted
    /// so every existing call site (Activity History's week rows, the isolated
    /// component scenarios) keeps compiling unchanged.
    var note: JournalEntry? = nil
    /// Offered only when there's no note yet AND a handler is supplied — the
    /// history rows are read-only and pass nothing.
    var onAddNote: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            summaryRow
            if let note = note, let text = note.trimmedNote {
                Text(text)
                    .font(Typography.callout)
                    .foregroundColor(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let onAddNote = onAddNote {
                Button(action: onAddNote) {
                    Text("How'd that \(workout.type) feel?")
                        .font(Typography.captionStrong)
                        .foregroundColor(Palette.brand)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a note about this \(workout.type)")
            }
        }
        .padding(Layout.cardPadding)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    private var summaryRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.go.opacity(0.16)).frame(width: 48, height: 48)
                Image(systemName: workout.type == "ride" ? "bicycle" : "figure.run")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Palette.go)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Latest \(workout.type)")
                    .cardSectionLabel()
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    /// The workout summary, with the runner's note appended when there is one —
    /// so a VoiceOver user hears what they wrote, not just the numbers.
    private var spokenSummary: String {
        let base = String(format: "Latest %@, %.1f miles at %@, %d minutes, %@, from %@",
                          workout.type, workout.distanceMiles, workout.pace,
                          workout.durationMinutes, prettyDate(workout.date), workout.source)
        guard let text = note?.trimmedNote else { return base }
        return base + ". Your note: \(text)"
    }
}
