import Foundation

// MARK: - Explain-this-element copy
//
// The plain-language answers to "what am I looking at?" for the Today dashboard's
// ambiguous elements. Pure and SwiftUI-free (same spirit as `Formatters.swift`) so
// the copy is unit-testable without rendering a view, and so one table owns every
// explanation instead of scattering strings through the section components.
//
// House style: no em dashes in user-facing strings (the convention applied across
// the app's copy), and never shame-based.

/// Scenario hook: which hint (if any) renders already expanded at launch.
///
/// A hint is a tap-to-reveal disclosure, and a simulator capture cannot tap. This
/// is the same trick `rbShowHistory` / `rbShowJournalEditor` use for the overlays:
/// seed the open state so the first frame renders it complete, never mid-animation.
public enum HintSeed {
    public static let key = "rbOpenHint"

    public static func isOpen(_ topic: HintTopic, _ d: UserDefaults = .standard) -> Bool {
        (d.string(forKey: key) ?? "") == topic.rawValue
    }
}

public enum HintTopic: String, CaseIterable {
    case buddyMood
    case stepRing
    case activeMinutes
    case distance
    case sinceMoving
    case coachCard
    case checkIn
    case weeklyLoad

    /// Short name of the thing being explained. Also builds the hint button's
    /// accessibility label ("Explain <title>").
    public var title: String {
        switch self {
        case .buddyMood:     return "Buddy's mood"
        case .stepRing:      return "your step ring"
        case .activeMinutes: return "active minutes"
        case .distance:      return "miles"
        case .sinceMoving:   return "time since you moved"
        case .coachCard:     return "Buddy's suggestion"
        case .checkIn:       return "the daily check in"
        case .weeklyLoad:    return "your weekly load"
        }
    }

    /// One or two sentences answering the literal question the element raises.
    public var body: String {
        switch self {
        case .buddyMood:
            return "Buddy's read on today. It changes with your steps, your latest run, and how hard your week has been. \"Ready\" means nothing is holding you back."
        case .stepRing:
            return "Your steps so far today against your daily goal. The ring fills as you move, and you can change the goal in Settings."
        case .activeMinutes:
            return "Minutes Apple Health scored as brisk movement today. It fills in through the day, so it starts at zero every morning."
        case .distance:
            return "Miles Apple Health recorded from walking and running today, including your workouts."
        case .sinceMoving:
            return "How long since Apple Health last recorded you moving. Useful for spotting a long sit."
        case .coachCard:
            return "Buddy's suggestion for today, based on your steps, your recent runs, and how much you have trained this week. Tap it to ask a follow up."
        case .checkIn:
            return "How today felt, in your own words. One tap logs it, and Buddy reads your recent check ins when it advises you."
        case .weeklyLoad:
            return "How much running you have done this week compared with the weeks before it. It is how Buddy spots a jump in mileage early."
        }
    }
}
