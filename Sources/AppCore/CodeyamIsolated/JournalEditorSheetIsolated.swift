import SwiftUI

// Isolation scaffold for JournalEditorSheet — the full editor, used for both a
// daily check-in and a post-run note. The two scenarios are the two entry
// points: a blank check-in (Save inert, nothing to record yet) and an existing
// post-run note reopened for editing (retitled, pre-filled, Delete offered).
//
// The sheet paints its own full-screen background, so no backdrop is added here.
struct JournalEditorSheetIsolated: View {
    let scenario: String

    private var existing: JournalEntry {
        JournalEntry(date: "2026-06-22", feel: 4, energy: .good, soreness: .mild, sleep: .okay,
                     note: "Legs were heavy the first mile, then it clicked. Held 10:15 without forcing it.",
                     workoutDate: "2026-06-22", workoutType: "run")
    }

    var body: some View {
        switch scenario {
        case "Post-Run Note":
            JournalEditorSheet(entry: existing, date: "2026-06-22",
                               workoutDate: "2026-06-22", workoutType: "run")
        default:
            JournalEditorSheet(entry: nil, date: "2026-06-22")
        }
    }
}
