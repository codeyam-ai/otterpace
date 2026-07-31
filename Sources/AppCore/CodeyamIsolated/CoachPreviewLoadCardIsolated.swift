import SwiftUI

// Isolation scaffold for CoachPreviewLoadCard. The populated state deliberately
// includes a week whose mileage came from walking, which reads "0 runs" — that
// pairing is what the coach receives, so it is shown rather than smoothed.
//
// CODEYAM_ISOLATE_COMPONENT=CoachPreviewLoadCard selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct CoachPreviewLoadCardIsolated: View {
    let scenario: String

    var body: some View {
        CoachPreviewFixtures.chrome(
            Group {
                switch scenario {
            case "Empty":
                CoachPreviewLoadCard(loadHistory: [])
            default:
                CoachPreviewLoadCard(loadHistory: CoachPreviewFixtures.loadHistory)
                }
            }
        )
    }
}
