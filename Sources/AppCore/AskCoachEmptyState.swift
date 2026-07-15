import SwiftUI

// The Ask Coach first-open state: a friendly Buddy and a prompt inviting the
// user to ask, shown whenever the conversation has no messages yet.
struct AskCoachEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            BuddyView(mood: .ready, size: 96)
            Text("What should we do today?")
                .font(Typography.title2)
                .foregroundColor(Palette.ink)
            Text("Ask me about running, rest, hitting your step goal, or how training's going. I'll keep it practical and easy on your body.")
                .font(Typography.body)
                .foregroundColor(Palette.subtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
