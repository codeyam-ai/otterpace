import SwiftUI

// One week in the Activity History: a header row with the week label and its
// training-load rollup (miles · runs · rest days), followed by the week's
// workouts rendered as the shared WorkoutCard rows.
struct ActivityWeekSection: View {
    let group: WeekGroup
    /// This week's journal entries, newest-first. Defaulted so the isolated
    /// component scenarios and any other caller keep compiling unchanged.
    var journal: [JournalEntry] = []

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

            // Positional identity: two genuinely identical rows in the same week
            // would collide on any content-derived id and SwiftUI would drop
            // one, so key on the index within this already-sorted, static list.
            ForEach(Array(timeline.enumerated()), id: \.offset) { _, item in
                switch item {
                case .workout(let workout, let note):
                    // A post-run note renders INSIDE its workout's card rather
                    // than as a separate row — the note is about that run, and
                    // splitting them would say the same thing twice.
                    WorkoutCard(workout: workout, note: note)
                case .checkIn(let entry):
                    JournalEntryRow(entry: entry)
                }
            }
        }
    }

    /// One week's rows, newest-first: each workout carrying its own post-run
    /// note, and each standalone check-in slotted in on its own date.
    private enum TimelineItem {
        case workout(LatestWorkout, JournalEntry?)
        case checkIn(JournalEntry)

        var date: String {
            switch self {
            case .workout(let w, _): return w.date
            case .checkIn(let e):    return e.date
            }
        }
    }

    private var timeline: [TimelineItem] {
        let workoutRows = group.workouts.map {
            TimelineItem.workout($0, Journal.entry(forWorkoutOn: $0.date, in: journal))
        }
        let checkInRows = journal.filter { !$0.isPostRunNote }.map { TimelineItem.checkIn($0) }
        // Stable: workouts keep their existing intra-week ordering, and a
        // check-in sorts to the same date band rather than to the top.
        return (workoutRows + checkInRows).sorted { $0.date > $1.date }
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
