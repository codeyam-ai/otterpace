import SwiftUI

// Isolation scaffold for CoachPreviewActivityCard. With Health denied every row
// must fall back to "Not shared" AND explain why — a card that simply vanished
// would leave the reader unable to tell withheld from forgotten.
//
// CODEYAM_ISOLATE_COMPONENT=CoachPreviewActivityCard selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct CoachPreviewActivityCardIsolated: View {
    let scenario: String

    var body: some View {
        CoachPreviewFixtures.chrome(
            Group {
                switch scenario {
            case "Health Denied":
                CoachPreviewActivityCard(state: CoachPreviewFixtures.deniedState)
            default:
                CoachPreviewActivityCard(state: CoachPreviewFixtures.richState)
                }
            }
        )
    }
}
