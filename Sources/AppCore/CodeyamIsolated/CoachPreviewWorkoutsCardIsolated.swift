import SwiftUI

// Isolation scaffold for CoachPreviewWorkoutsCard. The populated state also proves
// the source sentence ("Apple Health and Strava") that coachWorkoutSources builds.
//
// CODEYAM_ISOLATE_COMPONENT=CoachPreviewWorkoutsCard selects this struct in
// CodeyamIsolationHost.swift; CODEYAM_ISOLATE_SCENARIO picks the scenario below.
struct CoachPreviewWorkoutsCardIsolated: View {
    let scenario: String

    var body: some View {
        CoachPreviewFixtures.chrome(
            Group {
                switch scenario {
            case "Empty":
                CoachPreviewWorkoutsCard(workouts: [])
            default:
                CoachPreviewWorkoutsCard(workouts: CoachPreviewFixtures.workouts)
                }
            }
        )
    }
}
