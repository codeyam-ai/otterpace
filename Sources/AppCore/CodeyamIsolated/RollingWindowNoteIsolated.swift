import SwiftUI

// Isolation scaffold for RollingWindowNote — codeyam renders this View standalone on the
// booted iOS simulator. CODEYAM_ISOLATE_COMPONENT=RollingWindowNote selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
//
// The two states worth seeing are the plural/singular split on "run day(s)" and
// the wide-value case, since this line sits in a fixed-width card row.
struct RollingWindowNoteIsolated: View {
    let scenario: String

    var body: some View {
        switch scenario {
        case "Single Run Day":
            // Exercises the singular "1 run day" branch.
            RollingWindowNote(miles: 3.1, daysRun: 1)
        case "Big Week":
            // Widest realistic values, to catch truncation in the card row.
            RollingWindowNote(miles: 42.8, daysRun: 7)
        default:
            // The Sat/Sun/Mon weekend the Monday reset would otherwise hide.
            RollingWindowNote(miles: 12.3, daysRun: 3)
        }
    }
}
