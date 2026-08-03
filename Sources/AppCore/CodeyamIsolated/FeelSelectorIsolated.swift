import SwiftUI

// Isolation scaffold for FeelSelector.
//
// Unselected is the state a runner meets first, so the scale has to be legible
// and inviting with nothing chosen. The selected states check the two ends: a
// rough day must be tinted calm (lilac), never red or alarming, because a bad
// day is information rather than a failure — and a great day should feel warm.
//
// Each state carries a caption naming it. A component this small sits in a
// mostly-empty frame, so two states can differ by a few hundred pixels out of a
// full screen — indistinguishable both to a reviewer skimming the gallery and to
// the seeded-capture collision check. The caption makes the state explicit.

struct FeelSelectorIsolated: View {
    let scenario: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCENARIO — \(scenario)")
                .font(Typography.caption2)
                .foregroundColor(Palette.subtle)
            switch scenario {
            case "Rough Day Selected":
                FeelSelector(selection: 1, onSelect: { _ in })
                Text("A rough day reads calm, never alarming.")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
            case "Great Day Selected":
                FeelSelector(selection: 5, onSelect: { _ in })
                Text("The top of the scale reads warm.")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
            default:
                FeelSelector(selection: nil, onSelect: { _ in })
                Text("Nothing chosen yet — the state a runner meets first.")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bgTop.ignoresSafeArea())
    }
}
