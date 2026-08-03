import Foundation

// MARK: - Today tour persistence + launch gating
//
// Remembers whether the Today spotlight tour has been seen and decides whether to
// show it at launch. Modeled directly on `OnboardingState` so the two behave
// alike: UserDefaults-backed with injectable defaults, and a pure `shouldShow` so
// the launch decision is unit-testable rather than only observable in a capture.
public enum TourState {
    static let seenKey = "otterpaceTodayTourSeen"

    /// Number of steps in the tour. Single source of truth shared with the
    /// overlay's pager and with `startStep`'s clamp.
    public static var stepCount: Int { TourStep.allCases.count }

    public static func hasSeen(_ d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: seenKey)
    }

    public static func markSeen(_ d: UserDefaults = .standard) {
        d.set(true, forKey: seenKey)
    }

    /// Lets Settings offer a "show the tour again" action.
    public static func clearSeen(_ d: UserDefaults = .standard) {
        d.removeObject(forKey: seenKey)
    }

    /// Whether to show the Today tour at launch. Pure + deterministic:
    ///   • `startScreen == "tour"` → always show (preview/replay opt-in,
    ///     regardless of `hasSeen`).
    ///   • already seen → don't show.
    ///   • Health not connected → don't show, so the tour can never land on top
    ///     of the `ConnectHero` and point at cards that aren't rendered.
    ///   • scenario-seeded run → don't show (scenarios skip by default, matching
    ///     `OnboardingState.shouldShow`); a tour scenario opts in via
    ///     `rbStartScreen = "tour"`.
    ///   • otherwise (production first launch, Health connected) → show.
    public static func shouldShow(defaults d: UserDefaults = .standard,
                                  seeded: Bool = HealthSource.isScenarioSeeded(),
                                  startScreen: String = "",
                                  healthConnected: Bool = true) -> Bool {
        if startScreen == "tour" { return true }
        if hasSeen(d) { return false }
        if !healthConnected { return false }
        if seeded { return false }
        return true
    }

    /// Scenario hook: which step to start on (`rbTourStep`), clamped to the valid
    /// range so a capture can target any single step. Defaults to 0. Mirrors
    /// `OnboardingState.startPage`.
    public static func startStep(_ d: UserDefaults = .standard) -> Int {
        let raw = d.integer(forKey: "rbTourStep")
        return min(max(0, raw), stepCount - 1)
    }
}
