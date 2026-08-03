import SwiftUI

// Isolation scaffold for JournalChipRow.
//
// All three rows are shown together because the component's job is to make three
// different enums read as one family. Soreness carries the longest labels ("a
// little sore") and is the row most likely to overflow, so it is the layout canary.
//
// Each state carries a caption naming it. A component this small sits in a
// mostly-empty frame, so two states can differ by a few hundred pixels out of a
// full screen — indistinguishable both to a reviewer skimming the gallery and to
// the seeded-capture collision check. The caption makes the state explicit.

struct JournalChipRowIsolated: View {
    let scenario: String

    private var nothingSelected: Bool { scenario == "Nothing Selected" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SCENARIO — \(scenario)")
                .font(Typography.caption2)
                .foregroundColor(Palette.subtle)
            Text(nothingSelected
                 ? "Nothing chosen — every field is optional."
                 : "One chip chosen per row; tapping it again clears it.")
                .font(Typography.callout).foregroundColor(Palette.subtle)
            JournalChipRow(title: "Energy", options: EnergyLevel.allCases,
                           label: { $0.label }, tint: Palette.go,
                           selection: nothingSelected ? nil : EnergyLevel.good,
                           onSelect: { _ in })
            JournalChipRow(title: "Soreness", options: SorenessLevel.allCases,
                           label: { $0.label }, tint: Palette.amber,
                           selection: nothingSelected ? nil : SorenessLevel.mild,
                           onSelect: { _ in })
            JournalChipRow(title: "Sleep", options: SleepQuality.allCases,
                           label: { $0.label }, tint: Palette.lilac,
                           selection: nothingSelected ? nil : SleepQuality.okay,
                           onSelect: { _ in })
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
