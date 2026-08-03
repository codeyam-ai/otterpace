import SwiftUI

// The hero card pairing Buddy (with its mood chip) and the step-goal ring.
struct BuddySummaryCard: View {
    @ObservedObject var model: OtterpaceModel

    // Buddy's mood must come from the SAME recommendation the coach card is
    // showing. `CoachCard` falls back to the computed `CoachEngine.dailyNudge`
    // when a scenario hasn't pinned one; reading only `today.coach` here left
    // Buddy stuck on "ready" while the card advised rest — the mascot and the
    // advice visibly disagreeing on the same screen.
    private var mood: BuddyMood {
        BuddyMood(raw: (model.today.coach ?? CoachEngine.dailyNudge(for: model.today)).buddyMood)
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                BuddyView(mood: mood, size: 92)
                MoodChip(mood: mood)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Buddy the mascot, feeling \(mood.caption.lowercased())")
            StepRing(
                progress: model.goalProgress,
                steps: model.today.steps,
                goal: model.today.goalSteps,
                remaining: model.stepsRemaining,
                reached: model.goalReached,
                exceeded: model.goalExceeded
            )
            .frame(maxWidth: .infinity)
        }
        .padding(Layout.cardPadding)
        .cardStyle()
    }
}
