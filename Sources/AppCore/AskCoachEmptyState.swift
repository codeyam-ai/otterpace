import SwiftUI

// The Ask Coach first-open state, shown whenever the conversation has no messages
// yet. It replaces the old single static prompt with Buddy's scripted intro plus
// tappable starter questions, so a first-time user learns who they're talking to,
// what Buddy can actually see, and what a good question looks like.
//
// The intro turns render as coach `ChatBubble`s, which is honest: they are
// app-authored copy that never claims to be a generated reply.
struct AskCoachEmptyState: View {
    let context: TodayState
    let connected: Bool
    var onPick: (String) -> Void = { _ in }

    private var turns: [String] {
        CoachTutorial.openingTurns(for: context, connected: connected)
    }

    private var suggestions: [StarterQuestion] {
        StarterQuestions.suggestions(for: context)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.md) {
                ForEach(Array(turns.enumerated()), id: \.offset) { _, text in
                    ChatBubble(message: ChatMessage(id: 0, role: .coach, text: text, mood: .ready))
                }

                Text("Try asking")
                    .font(Typography.captionStrong)
                    .foregroundColor(Palette.subtle)
                    .padding(.top, Layout.xs)

                StarterQuestionChips(questions: suggestions, onPick: onPick)
            }
            .padding(.horizontal, Layout.screenGutter)
            .padding(.top, Layout.md)
            .padding(.bottom, Layout.screenBottom)
        }
        .frame(maxWidth: .infinity)
    }
}
