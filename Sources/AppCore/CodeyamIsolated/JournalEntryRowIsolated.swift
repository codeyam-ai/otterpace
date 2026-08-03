import SwiftUI

// Isolation scaffold for JournalEntryRow — one entry as it appears in Activity History.
//
// The two scenarios are the visual distinction the timeline depends on: a
// post-run note carries its workout's icon in green so it reads as "about that
// run", while a standalone check-in gets a quieter blue pencil. If those two stop
// being distinguishable at a glance, the interleaved history stops making sense.
struct JournalEntryRowIsolated: View {
    let scenario: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch scenario {
            case "Check-In":
                JournalEntryRow(entry: JournalEntry(date: "2026-06-20", feel: 3, energy: .okay,
                                                    soreness: .mild, sleep: .good))
            case "Both Kinds":
                JournalEntryRow(entry: JournalEntry(date: "2026-06-21", feel: 3, energy: .okay,
                                                    soreness: .sore, sleep: .poor,
                                                    note: "Slept badly, so I kept it short.",
                                                    workoutDate: "2026-06-21", workoutType: "run"))
                JournalEntryRow(entry: JournalEntry(date: "2026-06-20", feel: 3, energy: .okay,
                                                    soreness: .mild, sleep: .good))
            default:
                JournalEntryRow(entry: JournalEntry(date: "2026-06-21", feel: 3, energy: .okay,
                                                    soreness: .sore, sleep: .poor,
                                                    note: "Slept badly, so I kept it short. Calves are still tight from Saturday.",
                                                    workoutDate: "2026-06-21", workoutType: "run"))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
