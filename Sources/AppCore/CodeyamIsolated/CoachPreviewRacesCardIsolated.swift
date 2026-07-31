import SwiftUI

// Isolation scaffold for CoachPreviewRacesCard.
//
// CODEYAM_ISOLATE_COMPONENT=CoachPreviewRacesCard selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct CoachPreviewRacesCardIsolated: View {
    let scenario: String

    var body: some View {
        CoachPreviewFixtures.chrome(
            Group {
                switch scenario {
            case "Empty":
                CoachPreviewRacesCard(races: [])
            default:
                CoachPreviewRacesCard(races: CoachPreviewFixtures.races)
                }
            }
        )
    }
}
