import SwiftUI

// Isolation scaffold for CheckInCard — the journal's home on the Today dashboard.
// The pair below is the whole point of the component: an un-logged day must invite
// with the feel row live on the card (one tap starts an entry), and a logged day
// must read back what you said without ever implying you owe another one.
//
// CODEYAM_ISOLATE_COMPONENT=CheckInCard selects this struct in CodeyamIsolationHost.swift;
// CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct CheckInCardIsolated: View {
    let scenario: String

    private var logged: JournalEntry {
        JournalEntry(date: "2026-06-22", feel: 4, energy: .good, soreness: .mild, sleep: .okay,
                     note: "Legs were heavy the first mile, then it clicked.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch scenario {
            case "Logged":
                CheckInCard(entry: logged, onQuickFeel: { _ in }, onOpenEditor: {})
            default:
                CheckInCard(entry: nil, onQuickFeel: { _ in }, onOpenEditor: {})
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full-bleed opaque backdrop: a plain `.background` stays inside the safe
        // area, so the launch screen shows through the gaps and a capture picks up
        // a ghost splash behind the component.
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
