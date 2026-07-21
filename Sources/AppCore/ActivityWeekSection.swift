import SwiftUI

// One week in the Activity History: a header row with the week label and its
// training-load rollup (miles · runs · rest days), followed by the week's
// workouts rendered as the shared WorkoutCard rows.
struct ActivityWeekSection: View {
    let group: WeekGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.ink)
                Spacer()
                Text(rollup)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.subtle)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(group.title). \(spokenRollup)")

            // Positional identity: two genuinely identical workouts in the same
            // week (same date/distance/duration/source) would collide on any
            // content-derived id and SwiftUI would drop a row, so key on the
            // index within this already-sorted, static week list instead.
            ForEach(Array(group.workouts.enumerated()), id: \.offset) { _, workout in
                WorkoutCard(workout: workout)
            }
        }
    }

    private var rollup: String {
        weekRollup(miles: group.totalMiles, runCount: group.runCount,
                   restDays: group.restDays, daysElapsed: group.daysElapsed)
    }

    private var spokenRollup: String {
        weekRollupSpoken(miles: group.totalMiles, runCount: group.runCount,
                         restDays: group.restDays, daysElapsed: group.daysElapsed)
    }
}
