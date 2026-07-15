import SwiftUI

// The hero card pairing Buddy (with its mood chip) and the step-goal ring.
struct BuddySummaryCard: View {
    @ObservedObject var model: OtterpaceModel

    private var mood: BuddyMood {
        BuddyMood(raw: model.today.coach?.buddyMood ?? "ready")
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
