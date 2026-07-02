import Foundation

// MARK: - Coach personalization profile (optional, on-device)
//
// A lightweight profile collected during the personalized onboarding flow: how
// much and when the user usually walks, plus any other training they do. Every
// field is optional so a *skipped* onboarding step is representable as `nil` /
// empty. Stored as a single JSON blob in UserDefaults (same pattern as
// `RaceStore`) and carried on `TodayState`, so it flows — with no new transport —
// into the on-device `CoachEngine` and the remote AI coach (`api/coach.ts`). The
// daily step goal is intentionally NOT duplicated here; it stays the single
// source of truth in `UserPreferences`.
//
// Privacy: the profile leaves the device only on connected-coach requests (it
// rides inside the `TodayState` the app already ships to the backend) and is
// never sent to analytics.

/// How much the user usually walks. Each case carries a short human `label`
/// used in the coach payload / UI copy.
public enum WalkVolume: String, Codable, CaseIterable, Equatable {
    case rarely, someDays, mostDays, daily

    public var label: String {
        switch self {
        case .rarely:   return "rarely"
        case .someDays: return "some days"
        case .mostDays: return "most days"
        case .daily:    return "daily"
        }
    }
}

/// When the user usually walks.
public enum WalkTime: String, Codable, CaseIterable, Equatable {
    case mornings, midday, evenings, varies

    public var label: String {
        switch self {
        case .mornings: return "mornings"
        case .midday:   return "midday"
        case .evenings: return "evenings"
        case .varies:   return "varies"
        }
    }
}

/// Other training the user does alongside walking/running.
public enum TrainingKind: String, Codable, CaseIterable, Equatable {
    case running, strength, cycling, mobility, sports

    public var label: String {
        switch self {
        case .running:  return "running"
        case .strength: return "strength"
        case .cycling:  return "cycling"
        case .mobility: return "mobility"
        case .sports:   return "sports"
        }
    }
}

public struct CoachProfile: Codable, Equatable {
    public var walkVolume: WalkVolume?     // nil => not shared
    public var walkTime: WalkTime?         // nil => not shared
    public var otherTraining: [TrainingKind] // empty => none / not shared

    public init(walkVolume: WalkVolume? = nil,
                walkTime: WalkTime? = nil,
                otherTraining: [TrainingKind] = []) {
        self.walkVolume = walkVolume
        self.walkTime = walkTime
        self.otherTraining = otherTraining
    }

    /// True when the user shared nothing — used to keep an all-skipped profile
    /// out of the coach context (so existing scenarios and captures are
    /// unaffected).
    public var isEmpty: Bool {
        walkVolume == nil && walkTime == nil && otherTraining.isEmpty
    }
}

// MARK: - On-device store (single JSON key)

/// UserDefaults-backed store for the coach profile, following the `RaceStore`
/// shape (one JSON key, injectable `defaults`). `load` returns an empty profile
/// when nothing is stored so callers never deal with a decode failure.
public enum CoachProfileStore {
    static let key = "otterpaceCoachProfile"

    public static func load(_ d: UserDefaults = .standard) -> CoachProfile {
        guard let json = d.string(forKey: key), !json.isEmpty,
              let data = json.data(using: .utf8),
              let profile = try? JSONDecoder().decode(CoachProfile.self, from: data)
        else { return CoachProfile() }
        return profile
    }

    public static func save(_ profile: CoachProfile, _ d: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profile),
              let json = String(data: data, encoding: .utf8) else { return }
        d.set(json, forKey: key)
    }

    public static func clear(_ d: UserDefaults = .standard) {
        d.removeObject(forKey: key)
    }
}
