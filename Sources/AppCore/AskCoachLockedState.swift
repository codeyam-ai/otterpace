import SwiftUI

// Shown in the Ask Coach tab when no AI key is connected. The Today insights and
// weekly review are always free; the conversational chat needs the user's own
// key, so this invites them to connect one in Settings rather than faking a reply.
//
// Below the CTA it shows the SAME starter questions the unlocked state offers, as
// non-tappable examples. An unconnected user still learns what a good question
// looks like, and because the chips are inert the screen never implies the app
// will answer one without a key.
struct AskCoachLockedState: View {
    var context: TodayState
    var onAddKey: () -> Void = {}

    private var suggestions: [StarterQuestion] {
        StarterQuestions.suggestions(for: context)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                BuddyView(mood: .ready, size: 96)
                Text("Chat with Buddy")
                    .font(Typography.title2)
                    .foregroundColor(Palette.ink)
                Text("Your Today insights and weekly review are always free. To chat with Buddy for conversational coaching, connect your own AI key.")
                    .font(Typography.body)
                    .foregroundColor(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                Button(action: onAddKey) {
                    Text("Connect your AI key")
                        .font(Typography.headline)
                        .foregroundColor(Palette.onAccent)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(Palette.brand))
                }
                .padding(.top, 4)
                .accessibilityLabel("Connect your AI key in Settings")

                VStack(alignment: .leading, spacing: Layout.sm) {
                    Text("Once you connect a key, you can ask things like")
                        .font(Typography.caption)
                        .foregroundColor(Palette.subtle)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    StarterQuestionChips(questions: suggestions)
                }
                .padding(.top, Layout.md)
                .padding(.horizontal, Layout.screenGutter)
            }
            .padding(.top, Layout.xl)
            .padding(.bottom, Layout.screenBottom)
            .frame(maxWidth: .infinity)
        }
    }
}
