import SwiftUI

// Isolation scaffold for CoachPreviewAboutYouCard. The empty state matters most:
// a user who skipped onboarding should see that nothing about their routine is
// being forwarded, stated outright.
//
// CODEYAM_ISOLATE_COMPONENT=CoachPreviewAboutYouCard selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct CoachPreviewAboutYouCardIsolated: View {
    let scenario: String

    var body: some View {
        CoachPreviewFixtures.chrome(
            Group {
                switch scenario {
            case "Not Shared":
                CoachPreviewAboutYouCard(profile: nil)
            default:
                CoachPreviewAboutYouCard(profile: CoachPreviewFixtures.profile)
                }
            }
        )
    }
}
