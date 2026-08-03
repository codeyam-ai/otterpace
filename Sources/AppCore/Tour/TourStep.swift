import Foundation

// MARK: - Today tour script
//
// The ordered steps of the Today spotlight tour, as pure data. Mirrors the
// `HintCopy` style so the copy is testable without rendering a view.
//
// This is deliberately NOT a new onboarding page. `OnboardingScenarioIndexTests`
// pins every `rbOnboardingPage` seed against the onboarding step order, so adding
// a step there would shift every later index and silently recapture the wrong
// screens. The tour ships as its own overlay with its own gate instead.

public enum TourStep: String, CaseIterable {
    case buddy
    case stats
    case coachCard
    case checkIn
    case history

    /// Short headline naming the highlighted element.
    public var title: String {
        switch self {
        case .buddy:     return "This is Buddy"
        case .stats:     return "Your day at a glance"
        case .coachCard: return "Today's suggestion"
        case .checkIn:   return "Tell Buddy how it felt"
        case .history:   return "Your history"
        }
    }

    /// One or two sentences on what the element is for.
    public var body: String {
        switch self {
        case .buddy:
            return "Buddy's mood reflects your day, and the ring shows your steps against your goal. Tap any ⓘ on this screen for a short explanation."
        case .stats:
            return "Active minutes, miles, and how long since you last moved. On a brand new install these read as a dash until Apple Health records something."
        case .coachCard:
            return "One practical suggestion for today, based on your steps and your recent training. Tap it to ask Buddy a follow up."
        case .checkIn:
            return "One tap logs how today felt. Buddy reads your recent check ins, so this is how it learns what a hard week looks like for you."
        case .history:
            return "Your past weeks: mileage, runs, and rest days. That's the tour. You can replay it any time from Settings."
        }
    }

    /// Stable identifier used to anchor the callout to the highlighted section.
    public var anchorID: String { rawValue }

    /// Label on the advance button. The final step commits rather than continues.
    public var advanceTitle: String {
        self == TourStep.allCases[TourStep.allCases.count - 1] ? "Got it" : "Next"
    }
}
