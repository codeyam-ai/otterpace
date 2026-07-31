import SwiftUI

// Isolation scaffold for CoachDataRow — the row primitive every preview card is
// built from. The pair below is the whole point of the component: a shared value
// and a withheld one must be visibly different, and "Not shared" must read as an
// intentional statement rather than a missing value.
//
// CODEYAM_ISOLATE_COMPONENT=CoachDataRow selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct CoachDataRowIsolated: View {
    let scenario: String

    var body: some View {
        CoachPreviewFixtures.chrome(
            Group {
                switch scenario {
            case "Not Shared":
                VStack(spacing: 0) {
                    CoachDataRow(label: "Steps", value: nil)
                    CoachDataRow(label: "Active minutes", value: nil)
                    CoachDataRow(label: "Distance", value: nil)
                }
            default:
                VStack(spacing: 0) {
                    CoachDataRow(label: "Steps", value: "6,420 of 10,000")
                    CoachDataRow(label: "Active minutes", value: "42")
                    CoachDataRow(label: "Distance", value: "2.8 mi")
                }
                }
            }
        )
    }
}
