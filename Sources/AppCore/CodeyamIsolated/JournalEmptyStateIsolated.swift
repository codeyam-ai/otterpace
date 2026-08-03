import SwiftUI

// Isolation scaffold for JournalEmptyState — the invitation shown before anything
// has been written.
//
// Worth seeing in isolation precisely because of what must NOT be here: no
// streak, no missed-day count, no nudge to log more. "A line about today is
// enough" sets the bar at one line, and this capture is the standing check that
// nobody later adds pressure to it.
struct JournalEmptyStateIsolated: View {
    let scenario: String

    var body: some View {
        JournalEmptyState()
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Palette.bgTop.ignoresSafeArea())
    }
}
