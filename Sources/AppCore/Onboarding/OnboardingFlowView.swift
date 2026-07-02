import SwiftUI

// MARK: - First-run personalized onboarding flow
//
// A brief, movement-first setup shown once on first launch (and replayable from
// Settings) before the Sign-in screen. It opens with a three-page swipeable intro
// carousel (Meet Buddy) and then continues into a short, personalized sequence:
//   1. Set your daily step goal        (reuses UserPreferences presets + clampGoal)
//   2. Walking habits — how much / when (CoachProfile.walkVolume / walkTime)
//   3. Other training                  (CoachProfile.otherTraining)
//   4. Add AI coaching (optional)      (reuses CoachKeyStore, same as Settings)
//
// EVERY personalization step is individually skippable and leaves a safe default:
// skipping the goal keeps UserPreferences.defaultGoal, skipping a profile question
// stores nothing for that field, and skipping the key prompt leaves the built-in
// coach in place. Answers persist on-device (UserPreferences + CoachProfile) as
// the user advances, and thread into the coach context via TodayState.
//
// Reuses the app's mascot (`PuffyBuddy`), theme (`Palette`/`Typography`), and the
// gradient capsule button from `ConnectHero`. Presented by `ContentView` as a
// top-of-`ZStack` overlay, the same way Settings/Sign-in are gated.
struct OnboardingFlowView: View {
    var onFinish: () -> Void
    private let defaults: UserDefaults

    // Overall step index across the whole flow: 0..<OnboardingState.stepCount.
    // The first `introPageCount` indices are the swipeable carousel; the rest are
    // the personalization steps.
    @State private var page: Int

    // Personalization drafts, initialized from seeded/stored state so a replay or a
    // scenario capture reflects the user's existing choices on entry.
    @State private var goalDraft: Int
    @State private var walkVolume: WalkVolume?
    @State private var walkTime: WalkTime?
    @State private var otherTraining: [TrainingKind]
    @State private var keyDraft: String = ""
    @State private var keyConnected: Bool

    private let coachKeys = CoachKeyStore()

    init(onFinish: @escaping () -> Void = {},
         startPage: Int = 0,
         defaults: UserDefaults = .standard) {
        self.onFinish = onFinish
        self.defaults = defaults
        _page = State(initialValue: min(max(0, startPage), OnboardingState.stepCount - 1))

        // Seed the drafts: goal from UserPreferences, profile from CoachProfile
        // (rbCoachProfileJSON in scenarios). A scenario capture can pin the goal
        // step to a specific preset via rbGoalSteps (the same key the Today model
        // reads), and force the connected confirmation via rbCoachConnected.
        let seededGoal = defaults.integer(forKey: "rbGoalSteps")
        _goalDraft = State(initialValue: seededGoal > 0 ? seededGoal : UserPreferences.goalSteps(defaults))
        let profile = OnboardingFlowView.seededProfile(defaults)
        _walkVolume = State(initialValue: profile.walkVolume)
        _walkTime = State(initialValue: profile.walkTime)
        _otherTraining = State(initialValue: profile.otherTraining)
        _keyConnected = State(initialValue: CoachKeyStore().isConnected
                              || defaults.bool(forKey: "rbCoachConnected"))
    }

    /// The profile to prefill the steps with. A scenario capture can pin the
    /// walking-habits / other-training steps via `rbCoachProfileJSON` (the same key
    /// the Today model reads); otherwise fall back to the stored on-device profile
    /// (so a replay reflects the user's earlier answers).
    private static func seededProfile(_ d: UserDefaults) -> CoachProfile {
        if let json = d.string(forKey: "rbCoachProfileJSON"), !json.isEmpty,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(CoachProfile.self, from: data) {
            return decoded
        }
        return CoachProfileStore.load(d)
    }

    // MARK: Intro carousel content

    private struct IntroPage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let mood: BuddyMood
    }

    private static let intro: [IntroPage] = [
        IntroPage(title: "Meet Buddy",
                  body: "Hi, I'm Buddy! 🐾 Your friendly movement coach, here to cheer you on every day.",
                  mood: .ready),
        IntroPage(title: "Day-by-day coaching",
                  body: "I turn your steps and runs into gentle, day-by-day guidance, toward 10,000 steps a day, without overdoing it.",
                  mood: .jogging),
        IntroPage(title: "Ask me anything",
                  body: "Tap the Coach tab to ask about your training, and get a friendly weekly review of how you're trending.",
                  mood: .cheering),
    ]

    // MARK: Personalization steps

    private enum Step: Int, CaseIterable {
        case goal, walkHabits, otherTraining, aiKey

        /// Analytics-safe step name (no PII).
        var name: String {
            switch self {
            case .goal:          return "goal"
            case .walkHabits:    return "walk_habits"
            case .otherTraining: return "other_training"
            case .aiKey:         return "ai_key"
            }
        }
    }

    private var introCount: Int { OnboardingState.introPageCount }
    private var isIntro: Bool { page < introCount }
    private var currentStep: Step? { Step(rawValue: page - introCount) }
    private var isLastIntroPage: Bool { page == introCount - 1 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if isIntro {
                introView
            } else if let step = currentStep {
                stepView(step)
            }

            // Whole-tour skip lives on the intro pages (before any personalization).
            // Personalization steps carry their own per-step Skip control instead.
            if isIntro {
                Button("Skip", action: finish)
                    .font(Typography.caption)
                    .foregroundColor(Palette.subtle)
                    .padding(18)
                    .accessibilityLabel("Skip the welcome tour")
            }
        }
        .animation(Motion.overlay, value: page)
    }

    // MARK: Intro

    private var introView: some View {
        VStack(spacing: 0) {
            pager
            if isLastIntroPage {
                primaryButton("Continue") { advance() }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
    }

    // Paged carousel. PageTabViewStyle / index dots are iOS-only, so guard them;
    // the macOS test build still compiles with a plain TabView. Selection is a
    // clamped binding into the intro range so it never conflicts with the wider
    // `page` index used by the personalization steps.
    private var pager: some View {
        let selection = Binding<Int>(
            get: { min(page, introCount - 1) },
            set: { page = $0 }
        )
        let tabs = TabView(selection: selection) {
            ForEach(Array(Self.intro.enumerated()), id: \.offset) { idx, p in
                introPageView(p).tag(idx)
            }
        }
        #if os(iOS)
        return tabs
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        #else
        return tabs
        #endif
    }

    private func introPageView(_ p: IntroPage) -> some View {
        VStack(spacing: 22) {
            Spacer()
            PuffyBuddy(mood: p.mood, size: 140).accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(p.title)
                    .font(Typography.title)
                    .foregroundColor(Palette.ink)
                Text(p.body)
                    .font(Typography.callout)
                    .foregroundColor(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .padding(.horizontal, 28)
            }
            Spacer()
            Spacer()
        }
    }

    // MARK: Personalization steps

    @ViewBuilder private func stepView(_ step: Step) -> some View {
        switch step {
        case .goal:          goalStep
        case .walkHabits:    walkHabitsStep
        case .otherTraining: otherTrainingStep
        case .aiKey:         aiKeyStep
        }
    }

    private var goalStep: some View {
        stepScaffold(
            mood: .ready,
            title: "Your daily step goal",
            subtitle: "Pick a target that feels doable. You can change it anytime in Settings."
        ) {
            chipGroup(UserPreferences.goalOptions.map { option in
                ChipData(label: formatted(option), selected: goalDraft == option) {
                    goalDraft = option
                }
            })
        } primary: {
            primaryButton("Continue") {
                UserPreferences.setGoalSteps(UserPreferences.clampGoal(goalDraft), defaults)
                Analytics.shared.capture("onboarding_goal_set", ["goal": String(goalDraft)])
                advance()
            }
        } skip: {
            skipButton(step: .goal)
        }
    }

    private var walkHabitsStep: some View {
        stepScaffold(
            mood: .jogging,
            title: "Your walking habits",
            subtitle: "Buddy tailors coaching to how you already move. How much do you usually walk?"
        ) {
            VStack(alignment: .leading, spacing: 18) {
                chipGroup(WalkVolume.allCases.map { v in
                    ChipData(label: v.label.capitalizedFirst, selected: walkVolume == v) {
                        walkVolume = (walkVolume == v) ? nil : v
                    }
                })
                Text("When do you usually walk?")
                    .font(Typography.callout).foregroundColor(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                chipGroup(WalkTime.allCases.map { t in
                    ChipData(label: t.label.capitalizedFirst, selected: walkTime == t) {
                        walkTime = (walkTime == t) ? nil : t
                    }
                })
            }
        } primary: {
            primaryButton("Continue") {
                saveProfile()
                Analytics.shared.capture("onboarding_profile_saved", ["step": Step.walkHabits.name])
                advance()
            }
        } skip: {
            skipButton(step: .walkHabits)
        }
    }

    private var otherTrainingStep: some View {
        stepScaffold(
            mood: .cheering,
            title: "Any other training?",
            subtitle: "Pick anything you do alongside walking. This helps Buddy reason about your overall load."
        ) {
            chipGroup(TrainingKind.allCases.map { k in
                ChipData(label: k.label.capitalizedFirst, selected: otherTraining.contains(k)) {
                    if let i = otherTraining.firstIndex(of: k) {
                        otherTraining.remove(at: i)
                    } else {
                        otherTraining.append(k)
                    }
                }
            })
        } primary: {
            primaryButton("Continue") {
                saveProfile()
                Analytics.shared.capture("onboarding_profile_saved", ["step": Step.otherTraining.name])
                advance()
            }
        } skip: {
            skipButton(step: .otherTraining)
        }
    }

    private var aiKeyStep: some View {
        stepScaffold(
            mood: .ready,
            title: "Add AI coaching",
            subtitle: keyConnected
                ? "You're connected. Replies are generated by Claude, using your key."
                : "Connect your own Anthropic API key for real AI coaching. Without one, Buddy still coaches you with built-in guidance. Your key is stored only on this device."
        ) {
            if keyConnected {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundColor(Palette.brand)
                    Text("AI coach connected")
                        .font(Typography.callout).foregroundColor(Palette.ink)
                }
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField("sk-ant-…", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Anthropic API key")
                    if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "key")
                                Text("Get an API key")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(Typography.caption).foregroundColor(Palette.sky)
                        }
                        .accessibilityLabel("Get an Anthropic API key")
                    }
                }
            }
        } primary: {
            if keyConnected {
                primaryButton("Get started") { finish() }
            } else {
                let hasKey = !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                primaryButton(hasKey ? "Connect & finish" : "Get started",
                              enabled: true) {
                    if hasKey {
                        coachKeys.save(keyDraft)
                        Analytics.shared.capture("onboarding_key_connected")
                    }
                    finish()
                }
            }
        } skip: {
            // The final step's skip is a "not now" that finishes with the built-in coach.
            if !keyConnected {
                Button(action: {
                    Analytics.shared.capture("onboarding_step_skipped", ["step": Step.aiKey.name])
                    finish()
                }) {
                    Text("Skip for now — Buddy still coaches you")
                        .font(Typography.caption)
                        .foregroundColor(Palette.subtle)
                }
                .accessibilityLabel("Skip connecting a key for now")
            }
        }
    }

    // MARK: Step scaffold + shared controls

    /// Common layout for a personalization step: mascot, title, subtitle, the
    /// step's content, then a primary button and (optional) skip control. Wrapped
    /// in a ScrollView so large Dynamic Type sizes never clip.
    private func stepScaffold<Content: View, Primary: View, Skip: View>(
        mood: BuddyMood,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder skip: () -> Skip
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    PuffyBuddy(mood: mood, size: 96).accessibilityHidden(true)
                        .padding(.top, 44)
                    VStack(spacing: 10) {
                        Text(title)
                            .font(Typography.title)
                            .foregroundColor(Palette.ink)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(Typography.callout)
                            .foregroundColor(Palette.subtle)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 28)
                    content()
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            VStack(spacing: 12) {
                primary()
                skip()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func primaryButton(_ title: String, enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(enabled ? 1 : 0.5)
        }
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    private func skipButton(step: Step) -> some View {
        Button(action: {
            Analytics.shared.capture("onboarding_step_skipped", ["step": step.name])
            advance()
        }) {
            Text("Skip")
                .font(Typography.callout)
                .foregroundColor(Palette.subtle)
        }
        .accessibilityLabel("Skip this step")
    }

    /// A selectable pill. Selected pills fill with the brand gradient color.
    private func choiceChip(_ label: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typography.callout)
                .foregroundColor(selected ? .white : Palette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(selected ? Palette.brand : Color.white.opacity(0.7))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(selected ? Color.clear : Palette.subtle.opacity(0.3),
                                     lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// One selectable pill's data. Kept as a value so `chipGroup` can chunk chips
    /// into wrapping rows without the iOS 16 `Layout` protocol (macOS test build
    /// targets macOS 12).
    private struct ChipData: Identifiable {
        let id = UUID()
        let label: String
        let selected: Bool
        let action: () -> Void
    }

    /// Render chips in wrapping rows of up to `perRow`. A simple, deterministic
    /// substitute for a flow layout that compiles on every supported OS.
    private func chipGroup(_ chips: [ChipData], perRow: Int = 3) -> some View {
        let rows = stride(from: 0, to: chips.count, by: perRow).map { start in
            Array(chips[start..<min(start + perRow, chips.count)])
        }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row) { c in
                        choiceChip(c.label, selected: c.selected, action: c.action)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func advance() {
        if page < OnboardingState.stepCount - 1 {
            page += 1
        } else {
            finish()
        }
    }

    private func finish() { onFinish() }

    private func saveProfile() {
        CoachProfileStore.save(
            CoachProfile(walkVolume: walkVolume, walkTime: walkTime, otherTraining: otherTraining),
            defaults
        )
    }
}

// MARK: - Small helpers

private extension String {
    /// Capitalize only the first character (labels like "some days" -> "Some days").
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

