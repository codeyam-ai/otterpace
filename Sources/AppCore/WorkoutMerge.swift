import Foundation

// MARK: - Workout merge (Apple Health + Strava → one history)
//
// A runner who records on a watch usually lands the same run in BOTH Apple
// Health and Strava. Showing both would double their mileage; showing only one
// source drops every activity the other one has. So every load path composes the
// two lists through this one function.
//
// The rule: keep every Health workout, and add a Strava activity only when no
// Health workout already accounts for it. "Accounts for" means the same day, the
// same activity type, and a distance (or, for distance-less activities, a
// duration) within `tolerance`. Health wins a tie because it is the on-device
// source of truth; Strava fills the gaps.
//
// Each source is taken as-is — duplicates WITHIN one source are never collapsed,
// because two genuine runs on the same day are real and a seeded list must render
// exactly as seeded. Pure, so it unit-tests in the macOS build.
public enum WorkoutMerge {
    /// How close two activities' distance (or duration) must be to count as one.
    public static let tolerance = 0.1

    /// Health + Strava, newest-first, with Strava copies of Health workouts removed.
    public static func merge(health: [LatestWorkout], strava: [LatestWorkout]) -> [LatestWorkout] {
        var unmatched = health
        var extras: [LatestWorkout] = []
        for activity in strava {
            if let i = unmatched.firstIndex(where: { isSameActivity($0, activity) }) {
                unmatched.remove(at: i)   // one Health workout absorbs at most one Strava copy
            } else {
                extras.append(activity)
            }
        }
        // Stable newest-first: ISO dates sort lexically, and ties keep Health first.
        let combined = health + extras
        return combined.enumerated()
            .sorted { a, b in
                a.element.date != b.element.date ? a.element.date > b.element.date : a.offset < b.offset
            }
            .map(\.element)
    }

    /// `base` (the Health snapshot) with its history replaced by Health + Strava.
    /// With no Strava runs `base` comes back exactly as given — its weekly load is
    /// never recomputed, so a seeded scenario's hand-set numbers survive. Otherwise
    /// the merged list is rolled up the same way `HealthKitDataSource.loadToday()`
    /// does, so a Strava-only user gets a real Weekly Review recap and the coach
    /// sees the whole trajectory, not one source's half.
    public static func compose(_ base: TodayState, healthWorkouts: [LatestWorkout],
                               strava: [LatestWorkout]) -> TodayState {
        guard !strava.isEmpty else { return base }
        var state = base
        let merged = merge(health: healthWorkouts, strava: strava)
        state.workouts = merged
        state.latestWorkout = merged.first(where: { $0.type == "run" }) ?? merged.first
        state.weeklyLoad = ActivityHistory.weeklyLoad(
            from: merged, asOf: ActivityHistory.referenceDate(fromISO: state.date))
        state.loadHistory = ActivityHistory.loadHistory(from: merged)
        state.healthKitConnected = true
        return state
    }

    /// Whether two activities are the same outing recorded by two sources.
    static func isSameActivity(_ a: LatestWorkout, _ b: LatestWorkout) -> Bool {
        guard a.date == b.date, a.type == b.type else { return false }
        if a.distanceMiles > 0 || b.distanceMiles > 0 {
            return isClose(a.distanceMiles, b.distanceMiles)
        }
        return isClose(Double(a.durationMinutes), Double(b.durationMinutes))
    }

    private static func isClose(_ x: Double, _ y: Double) -> Bool {
        let larger = max(x, y)
        guard larger > 0 else { return true }
        return abs(x - y) / larger <= tolerance
    }
}
