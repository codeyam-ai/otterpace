import Foundation

// MARK: - Journal (optional, on-device)
//
// Lets a runner write down how it actually went. Two surfaces, one type: a
// post-run note bound to a workout (`workoutDate` set) and a standalone daily
// check-in (`workoutDate` nil). Modeling both as a single dated entry means one
// store, one persistence path, one coach payload — and it means "how did that
// run feel" and "how do I feel today" land on the same timeline instead of in
// two disjoint histories.
//
// Entries are entirely on-device — a JSON array in UserDefaults, the same
// pattern as `RaceStore` and `CoachProfileStore` — and carried on `TodayState`
// so they flow, with no new transport, into the on-device `CoachEngine`, the
// remote AI coach (`api/coach.ts`), and the `WeeklyReviewEngine`.
//
// Privacy: journal text is the most personal data in the app. It never syncs, it
// is never sent to analytics, and only a bounded recent slice
// (`Journal.coachSlice`) leaves the device on a connected-coach request.

/// How much energy the runner had. Each case carries a short human `label` used
/// in the coach payload and UI copy (same idiom as `WalkVolume`/`TrainingKind`).
public enum EnergyLevel: String, Codable, CaseIterable, Equatable {
    case low, okay, good

    public var label: String {
        switch self {
        case .low:  return "low"
        case .okay: return "okay"
        case .good: return "good"
        }
    }
}

/// How sore the runner was. `painful` is deliberately distinct from `sore` — the
/// coach treats it as a signal to back off, never as something to push through.
public enum SorenessLevel: String, Codable, CaseIterable, Equatable {
    case none, mild, sore, painful

    public var label: String {
        switch self {
        case .none:    return "not sore"
        case .mild:    return "a little sore"
        case .sore:    return "sore"
        case .painful: return "painful"
        }
    }

    /// True for the levels that should soften a recommendation when they repeat.
    public var isElevated: Bool { self == .sore || self == .painful }
}

/// How the runner slept.
public enum SleepQuality: String, Codable, CaseIterable, Equatable {
    case poor, okay, good

    public var label: String {
        switch self {
        case .poor: return "poor"
        case .okay: return "okay"
        case .good: return "good"
        }
    }
}

public struct JournalEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: String              // ISO yyyy-MM-dd, matching LatestWorkout.date
    public var feel: Int?                // 1...5, nil when not rated
    public var energy: EnergyLevel?
    public var soreness: SorenessLevel?
    public var sleep: SleepQuality?
    public var note: String?             // free text, always optional
    public var workoutDate: String?      // set => this is a post-run note
    public var workoutType: String?      // run | walk | ride, for the row's icon

    public init(id: UUID = UUID(),
                date: String,
                feel: Int? = nil,
                energy: EnergyLevel? = nil,
                soreness: SorenessLevel? = nil,
                sleep: SleepQuality? = nil,
                note: String? = nil,
                workoutDate: String? = nil,
                workoutType: String? = nil) {
        self.id = id
        self.date = date
        self.feel = feel.map { min(5, max(1, $0)) }
        self.energy = energy
        self.soreness = soreness
        self.sleep = sleep
        self.note = note
        self.workoutDate = workoutDate
        self.workoutType = workoutType
    }

    /// Tolerant decode, same rationale as `TodayState`: an entry persisted before
    /// a field existed must still decode instead of throwing on the missing key.
    /// Only `date` is load-bearing, and even it defaults rather than failing the
    /// whole array — one malformed entry should never cost the user their journal.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        feel = (try c.decodeIfPresent(Int.self, forKey: .feel)).map { min(5, max(1, $0)) }
        energy = try c.decodeIfPresent(EnergyLevel.self, forKey: .energy)
        soreness = try c.decodeIfPresent(SorenessLevel.self, forKey: .soreness)
        sleep = try c.decodeIfPresent(SleepQuality.self, forKey: .sleep)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        workoutDate = try c.decodeIfPresent(String.self, forKey: .workoutDate)
        workoutType = try c.decodeIfPresent(String.self, forKey: .workoutType)
    }

    /// True when this entry is attached to a workout (a post-run note) rather
    /// than being a standalone daily check-in.
    public var isPostRunNote: Bool { !(workoutDate ?? "").isEmpty }

    /// True when the runner recorded nothing at all — no rating, no chip, no
    /// text. Used to keep a blank editor save from creating a hollow row.
    public var isEmpty: Bool {
        feel == nil && energy == nil && soreness == nil && sleep == nil
            && (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The note trimmed of surrounding whitespace, or nil when it holds nothing.
    public var trimmedNote: String? {
        let t = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
