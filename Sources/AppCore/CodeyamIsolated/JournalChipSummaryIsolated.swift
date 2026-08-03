import SwiftUI

// Isolation scaffold for JournalChipSummary.
//
// The partial and none cases are the point: the strip shows ONLY what the runner
// recorded, and renders nothing at all when they recorded no chips, so an entry
// that is just a rating and a note leaves no empty band behind.
//
// Each state carries a caption naming it. A component this small sits in a
// mostly-empty frame, so two states can differ by a few hundred pixels out of a
// full screen — indistinguishable both to a reviewer skimming the gallery and to
// the seeded-capture collision check. The caption makes the state explicit.

struct JournalChipSummaryIsolated: View {
    let scenario: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCENARIO — \(scenario)")
                .font(Typography.caption2)
                .foregroundColor(Palette.subtle)
            switch scenario {
            case "Partial":
                Text("Only soreness recorded — energy and sleep are omitted, not blanked.")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
                JournalChipSummary(entry: JournalEntry(date: "2026-06-22", feel: 3, soreness: .sore))
            case "Nothing Recorded":
                // Shown against a reference strip: the point is the CONTRAST —
                // an entry with chips renders a band, an entry without renders
                // nothing rather than an empty placeholder. A lone blank frame
                // could not demonstrate that.
                Text("With chips recorded:")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
                JournalChipSummary(entry: JournalEntry(date: "2026-06-22", feel: 4, energy: .good,
                                                       soreness: .mild, sleep: .okay))
                Divider().padding(.vertical, 4)
                Text("With none recorded — no band, no placeholder:")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
                JournalChipSummary(entry: JournalEntry(date: "2026-06-22", feel: 3, note: "just a line"))
            default:
                Text("All three chips recorded.")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
                JournalChipSummary(entry: JournalEntry(date: "2026-06-22", feel: 4, energy: .good,
                                                       soreness: .mild, sleep: .okay))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
