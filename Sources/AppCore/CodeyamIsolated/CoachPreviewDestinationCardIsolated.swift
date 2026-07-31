import SwiftUI

// Isolation scaffold for CoachPreviewDestinationCard. The two states say opposite
// things — "this is sent to OpenAI" versus "none of this is being sent anywhere" —
// so they are worth proving side by side rather than trusting one page capture.
//
// CODEYAM_ISOLATE_COMPONENT=CoachPreviewDestinationCard selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct CoachPreviewDestinationCardIsolated: View {
    let scenario: String

    var body: some View {
        CoachPreviewFixtures.chrome(
            Group {
                switch scenario {
            case "No Provider":
                CoachPreviewDestinationCard(activeProvider: nil)
            default:
                CoachPreviewDestinationCard(activeProvider: .openai)
                }
            }
        )
    }
}
