import SwiftUI

// MARK: - Ask Coach chat screen
//
// A chat-style surface where the user types a fitness question and Buddy replies
// with a practical, injury-aware answer from `CoachEngine`. Mock mode: replies
// are curated by intent from the day's `TodayState`, so they're deterministic
// and safe to capture as scenarios.
//
// This view is pure composition — header, thread (or empty state), and input
// bar each live in their own component file. It owns only the conversation
// state and the send/seed behavior.
//
// Seeding: a scenario can seed `rbAskSeedQuestion` to pre-run one question
// through the engine at launch, so a populated conversation renders in the
// screenshot. With no seed (production / empty-chat scenario) the screen opens
// to Buddy's friendly prompt and an empty thread.

/// One line in the conversation. Coach lines carry the Buddy mood + safety flag
/// so the bubble can tint and shield-mark itself.
public struct ChatMessage: Identifiable, Equatable {
    public enum Role: Equatable { case user, coach }

    public let id: Int
    public var role: Role
    public var text: String
    public var mood: BuddyMood
    public var safetyFlag: Bool

    public init(id: Int, role: Role, text: String, mood: BuddyMood = .ready, safetyFlag: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.mood = mood
        self.safetyFlag = safetyFlag
    }
}

public struct AskCoachView: View {
    @ObservedObject var model: RunBuddyModel

    @State private var messages: [ChatMessage] = []
    @State private var draft: String = ""
    @State private var nextId: Int = 0

    public init(model: RunBuddyModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            AskCoachHeader()
            Divider().opacity(0.4)
            if messages.isEmpty {
                AskCoachEmptyState()
            } else {
                ChatThread(messages: messages)
            }
            AskCoachInputBar(draft: $draft, onSend: send)
        }
        .background(
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear(perform: seedFromScenario)
    }

    // MARK: Behavior

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        draft = ""
        ask(question)
    }

    /// Append the user's question and Buddy's curated reply.
    private func ask(_ question: String) {
        append(ChatMessage(id: takeId(), role: .user, text: question))
        let reply = CoachEngine.reply(to: question, context: model.today)
        append(ChatMessage(id: takeId(), role: .coach, text: reply.text,
                           mood: reply.mood, safetyFlag: reply.safetyFlag))
    }

    private func append(_ m: ChatMessage) { messages.append(m) }

    private func takeId() -> Int {
        defer { nextId += 1 }
        return nextId
    }

    /// Scenario hook: if `rbAskSeedQuestion` is seeded, replay it through the
    /// engine once so the captured frame shows a real exchange.
    private func seedFromScenario() {
        guard messages.isEmpty else { return }
        let seeded = UserDefaults.standard.string(forKey: "rbAskSeedQuestion") ?? ""
        let q = seeded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        ask(q)
    }
}
