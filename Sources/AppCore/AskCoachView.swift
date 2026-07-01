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
    @ObservedObject var model: OtterpaceModel

    @State private var messages: [ChatMessage] = []
    @State private var draft: String = ""
    @State private var nextId: Int = 0
    @State private var showReview: Bool

    // The real-LLM coach + the user's BYO key store. The conversational chat is
    // gated on a connected key (see `chatUnlocked`); with none, the tab shows a
    // connect-key CTA instead of a fabricated answer.
    private let keyStore = CoachKeyStore()
    private let remote = RemoteCoach()
    private let onOpenSettings: () -> Void

    /// The chat is available when the user has connected a key, or when a scenario
    /// opts in via `rbCoachConnected` (so a populated conversation is capturable
    /// offline without a real key). Otherwise the tab shows the connect-key CTA.
    private var chatUnlocked: Bool {
        keyStore.isConnected || UserDefaults.standard.bool(forKey: "rbCoachConnected")
    }

    public init(model: OtterpaceModel, onOpenSettings: @escaping () -> Void = {}) {
        self.model = model
        self.onOpenSettings = onOpenSettings
        // Scenario hook: when `rbShowWeeklyReview` is seeded, present the recap
        // from the very first frame (initialized here, not in `.onAppear`) so a
        // launch-time capture lands on a fully-rendered screen, never mid-transition.
        _showReview = State(initialValue: UserDefaults.standard.bool(forKey: "rbShowWeeklyReview"))
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                AskCoachHeader(connected: chatUnlocked,
                               onWeeklyReview: { withAnimation(Motion.overlay) { showReview = true } })
                Divider().opacity(0.4)
                if !chatUnlocked {
                    AskCoachLockedState(onAddKey: onOpenSettings)
                } else if messages.isEmpty {
                    AskCoachEmptyState()
                } else {
                    ChatThread(messages: messages)
                }
                if chatUnlocked {
                    AskCoachInputBar(draft: $draft, onSend: send)
                }
            }
            .background(
                LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )

            // Weekly Review presents as a full-cover overlay (cross-platform; a
            // SwiftUI `fullScreenCover` is unavailable on macOS). No transition —
            // a launch-seeded capture must render fully on the first frame.
            if showReview {
                WeeklyReviewView(
                    review: WeeklyReviewEngine.generate(from: model.today),
                    onClose: { withAnimation(Motion.overlay) { showReview = false } }
                )
                .overlayTransition()
                .zIndex(1)
            }
        }
        .onAppear(perform: seedFromScenario)
    }

    // MARK: Behavior

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        draft = ""
        submit(question)
    }

    /// Interactive send. Uses the real AI coach when the user has connected a key;
    /// otherwise — and on any network/server failure — falls back to the
    /// deterministic mock so the chat always answers. Scenario seeding never comes
    /// through here (it calls `ask` directly), so captures stay network-free.
    private func submit(_ question: String) {
        append(ChatMessage(id: takeId(), role: .user, text: question))

        // Seeded/preview chat without a real key (rbCoachConnected): answer
        // deterministically offline so captures render without a network call.
        guard let apiKey = keyStore.key else {
            ask(question, appendUser: false)
            return
        }

        let placeholderId = takeId()
        append(ChatMessage(id: placeholderId, role: .coach, text: "Buddy is thinking…", mood: .ready))
        let context = model.today

        Task { @MainActor in
            let reply: CoachReply
            do {
                reply = try await remote.reply(to: question, context: context, apiKey: apiKey)
            } catch CoachError.invalidKey {
                reply = CoachReply(intent: .general,
                    text: "Your AI coach key was rejected. Reconnect it in Settings, then ask again.",
                    mood: .concerned)
            } catch {
                reply = CoachReply(intent: .general,
                    text: "I couldn't reach Buddy just now. Check your connection and try again.",
                    mood: .concerned)
            }
            replaceCoach(placeholderId, with: reply)
        }
    }

    /// Deterministic offline exchange. Used by scenario seeding and the seeded-
    /// preview send path (a connected scenario carrying no real key). `appendUser`
    /// is false when the caller already appended the question.
    private func ask(_ question: String, appendUser: Bool = true) {
        if appendUser {
            append(ChatMessage(id: takeId(), role: .user, text: question))
        }
        let reply = CoachEngine.reply(to: question, context: model.today)
        append(ChatMessage(id: takeId(), role: .coach, text: reply.text,
                           mood: reply.mood, safetyFlag: reply.safetyFlag))
    }

    /// Swap a "thinking…" placeholder for the finished coach reply.
    private func replaceCoach(_ id: Int, with reply: CoachReply) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text = reply.text
        messages[idx].mood = reply.mood
        messages[idx].safetyFlag = reply.safetyFlag
    }

    private func append(_ m: ChatMessage) { messages.append(m) }

    private func takeId() -> Int {
        defer { nextId += 1 }
        return nextId
    }

    /// Scenario hook: if `rbAskSeedQuestion` is seeded, replay it through the
    /// engine once so the captured frame shows a real exchange. (The Weekly
    /// Review's `rbShowWeeklyReview` hook is handled in `init` so it renders from
    /// the first frame — see `showReview`.)
    private func seedFromScenario() {
        guard messages.isEmpty, chatUnlocked else { return }
        let seeded = UserDefaults.standard.string(forKey: "rbAskSeedQuestion") ?? ""
        let q = seeded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        ask(q)
    }
}
