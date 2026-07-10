import Foundation

// MARK: - Onboarding persistence + launch gating
//
// Remembers whether the first-run welcome tour has been seen and decides whether
// to show it at launch. Mirrors the `UserPreferences` pattern: UserDefaults-backed
// with an injectable `defaults` so the launch decision is pure and unit-testable —
// not bolted onto `SessionStore` (this is unrelated to the Apple-credential
// lifecycle).
public enum OnboardingState {
    static let seenKey = "otterpaceOnboardingSeen"

    /// Number of swipeable intro pages in the welcome carousel (Meet Buddy /
    /// day-by-day coaching / ask me anything). The single source of truth shared
    /// with the view's pager.
    public static let introPageCount = 3

    /// Personalization steps that follow the intro carousel: set goal, walking
    /// habits, other training, training phase, add AI coaching. Each is
    /// individually skippable.
    public static let personalizationStepCount = 5

    /// Total steps in the personalized onboarding flow (intro pages +
    /// personalization steps). `startPage` clamps into `0..<stepCount` so a
    /// scenario can seed a capture on any intro page or personalization step.
    public static let stepCount = introPageCount + personalizationStepCount

    /// Back-compat alias: older call sites / tests referred to `pageCount` for the
    /// intro carousel length. Kept pointing at the intro carousel count.
    public static let pageCount = introPageCount

    public static func hasSeen(_ d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: seenKey)
    }

    public static func markSeen(_ d: UserDefaults = .standard) {
        d.set(true, forKey: seenKey)
    }

    /// Whether to show the welcome tour at launch. Pure + deterministic:
    ///   • `startScreen == "onboarding"` → always show (preview/replay opt-in,
    ///     regardless of `hasSeen`).
    ///   • already seen → don't show.
    ///   • scenario-seeded run → don't show (scenarios skip by default, matching
    ///     `SignInView`'s `seeded && !wantsSignInPreview`).
    ///   • otherwise (production first launch) → show.
    public static func shouldShow(defaults d: UserDefaults = .standard,
                                  seeded: Bool = HealthSource.isScenarioSeeded(),
                                  startScreen: String = "") -> Bool {
        if startScreen == "onboarding" { return true }
        if hasSeen(d) { return false }
        if seeded { return false }
        return true
    }

    /// Scenario hook: which step to start on (`rbOnboardingPage`), clamped to the
    /// valid range so a capture can target a specific intro page OR personalization
    /// step. Defaults to 0.
    public static func startPage(_ d: UserDefaults = .standard) -> Int {
        let raw = d.integer(forKey: "rbOnboardingPage")
        return min(max(0, raw), stepCount - 1)
    }
}
