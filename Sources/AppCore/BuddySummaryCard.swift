import SwiftUI

// The hero card pairing Buddy (with its mood chip) and the step-goal ring.
struct BuddySummaryCard: View {
    @ObservedObject var model: RunBuddyModel

    private var mood: BuddyMood {
        BuddyMood(raw: model.today.coach?.buddyMood ?? "ready")
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                BuddyView(mood: mood, size: 92)
                MoodChip(mood: mood)
            }
            StepRing(
                progress: model.goalProgress,
                steps: model.today.steps,
                goal: model.today.goalSteps,
                remaining: model.stepsRemaining,
                reached: model.goalReached
            )
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .cardStyle()
    }
}
