import Foundation

// MARK: - Refresh policy (battery-light background refresh)
//
// "Should we re-read the user's data right now?" — the one throttle every
// automatic refresh asks first. The user's constraint, verbatim: "be cautious
// about it - don't overdo it and tax phone battery." So every automatic path
// (returning to the app, a HealthKit background wake, the rare iOS background
// refresh) goes through these minimum intervals. Pull-to-refresh is the user
// asking explicitly and bypasses them.
//
// Pure and free of HealthKit / BackgroundTasks types, so it unit-tests in the
// macOS build like `ActivityFreshness`.
public enum RefreshPolicy {

    /// What is asking to refresh. Intervals differ by cost: a foreground Health
    /// read is cheap and the user is looking; a background read spends a wake the
    /// OS budgets; Strava is a remote, rate-limited API.
    public enum Kind: Equatable {
        case foreground
        case background
        case strava
    }

    public static let foregroundInterval: TimeInterval = 15 * 60
    public static let backgroundInterval: TimeInterval = 3600
    public static let stravaInterval: TimeInterval = 3 * 3600

    /// How long iOS should wait before offering the next background refresh.
    /// iOS treats this as a floor and applies its own budget on top.
    public static let backgroundTaskSpacing: TimeInterval = 4 * 3600

    public static func minimumInterval(for kind: Kind) -> TimeInterval {
        switch kind {
        case .foreground: return foregroundInterval
        case .background: return backgroundInterval
        case .strava:     return stravaInterval
        }
    }

    /// True when enough time has passed since `lastRefreshed` for `kind` to run.
    /// Never refreshed (`nil`) is always due. A `lastRefreshed` in the future
    /// (clock change) counts as just now, so a skewed clock can't force a refresh
    /// storm.
    public static func shouldRefresh(_ kind: Kind, lastRefreshed: Date?, now: Date = Date()) -> Bool {
        guard let lastRefreshed else { return true }
        let age = max(0, now.timeIntervalSince(lastRefreshed))
        return age >= minimumInterval(for: kind)
    }

    /// Whether a Health read can be trusted to replace the cached picture.
    ///
    /// HealthKit is unreadable while the phone is locked, and a failed read comes
    /// back as an all-zero day: no steps, no workouts, no per-day history. In the
    /// background that shape means "unknown", not "you did nothing" — so it must
    /// not overwrite the cache or be sent as a heartbeat (`ActivityFreshness`:
    /// when freshness is unknown, stay quiet). In the foreground HealthKit is
    /// readable, so any read is trusted.
    public static func isUsableRead(_ state: TodayState, for kind: Kind) -> Bool {
        guard kind == .background else { return true }
        return state.steps > 0 || !state.workouts.isEmpty || !state.dailySteps.isEmpty
    }

    /// Whether a Strava import should replace the runs already on screen. An empty
    /// list (not connected, or a quiet account) never wipes the cached runs, and an
    /// unchanged list isn't "fresh" — so it doesn't trigger a recompose or heartbeat.
    public static func isNewStravaImport(_ incoming: [LatestWorkout], current: [LatestWorkout]) -> Bool {
        !incoming.isEmpty && incoming != current
    }

    /// Whether a cached snapshot is newer than what this model last composed — i.e.
    /// the background-launch path (its own model instance) refreshed the cache since.
    /// A model that has never composed adopts any cache.
    public static func shouldAdoptCache(cachedAt: Date, lastComposedAt: Date?) -> Bool {
        cachedAt > (lastComposedAt ?? .distantPast)
    }
}

/// When each automatic refresh last obtained fresh data, persisted so the
/// throttle holds across launches and between the app's foreground model and the
/// background-launch path. One key per source, in the model's own UserDefaults.
public enum RefreshStamps {
    static let healthKey = "otterpaceLastHealthRefreshAt"
    static let stravaKey = "otterpaceLastStravaRefreshAt"

    public static func lastHealth(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: healthKey) as? Date
    }

    public static func lastStrava(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: stravaKey) as? Date
    }

    public static func markHealth(_ at: Date, _ defaults: UserDefaults = .standard) {
        defaults.set(at, forKey: healthKey)
    }

    public static func markStrava(_ at: Date, _ defaults: UserDefaults = .standard) {
        defaults.set(at, forKey: stravaKey)
    }
}
