import Foundation

// MARK: - Snapshot cache (render the real dashboard on a cold launch)
//
// Without this, every cold launch started from `TodayState.empty` and showed the
// "Connect Apple Health" hero until the user tapped Connect again — Health access
// was still granted, the app just didn't remember it had data. The cache holds the
// last good HealthKit snapshot and the last Strava import, so launch renders the
// user's dashboard immediately and the live reads then replace it.
//
// A render cache only: live reads always win, it never leaves the device, and the
// model never touches it for a scenario-seeded store (captures must render exactly
// what they seed). Kept as one JSON key in the model's own UserDefaults, the same
// pattern as RaceStore/JournalStore.
public struct CachedSnapshot: Codable, Equatable {
    /// The last state `HealthDataSource.loadToday()` produced; nil => Health never read.
    public var health: TodayState?
    /// The last Strava import, newest-first; [] => not connected or nothing imported.
    public var strava: [LatestWorkout]
    public var refreshedAt: Date

    public init(health: TodayState?, strava: [LatestWorkout], refreshedAt: Date) {
        self.health = health
        self.strava = strava
        self.refreshedAt = refreshedAt
    }

    /// The cached Health snapshot as it should render on `today`. History carries
    /// over, but the day's running totals belong to the day they were read — on a
    /// new day they reset to zero rather than showing yesterday's steps as today's.
    public func healthState(asOf today: String) -> TodayState? {
        guard var state = health, state.date != today else { return health }
        state.date = today
        state.steps = 0
        state.activeMinutes = 0
        state.distanceMiles = 0
        state.activeEnergyKcal = 0
        state.minutesSinceLastMovement = 0
        return state
    }
}

public enum SnapshotCache {
    static let key = "otterpaceSnapshotCache"

    public static func load(_ defaults: UserDefaults = .standard) -> CachedSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedSnapshot.self, from: data)
    }

    public static func save(_ snapshot: CachedSnapshot, _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
