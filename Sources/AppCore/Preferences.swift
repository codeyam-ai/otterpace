import Foundation

// User-set preferences that persist locally (no account needed). Currently just
// the daily step goal, edited in Settings. Seeded scenarios still get their goal
// from `rbGoalSteps`; this is the production default + user override.
public enum UserPreferences {
    private static let goalKey = "otterpaceGoalSteps"
    public static let defaultGoal = 10000

    /// Preset goals offered in Settings.
    public static let goalOptions = [6000, 8000, 10000, 12000, 15000]

    /// Bounds + step for a custom goal. Kept here so the Custom editor and its
    /// tests share one source of truth instead of scattering magic numbers.
    public static let minGoal = 1000
    public static let maxGoal = 50000
    public static let goalIncrement = 500

    /// Clamp a goal into `minGoal…maxGoal`, then round to the nearest
    /// `goalIncrement`, so a custom value is always on-rail and in bounds.
    public static func clampGoal(_ value: Int) -> Int {
        let bounded = min(max(value, minGoal), maxGoal)
        let rounded = Int((Double(bounded) / Double(goalIncrement)).rounded()) * goalIncrement
        return min(max(rounded, minGoal), maxGoal)
    }

    /// Whether a goal is one of the quick presets (vs. a custom value).
    public static func isPreset(_ value: Int) -> Bool {
        goalOptions.contains(value)
    }

    public static func goalSteps(_ d: UserDefaults = .standard) -> Int {
        let v = d.integer(forKey: goalKey)
        return v > 0 ? v : defaultGoal
    }

    public static func setGoalSteps(_ value: Int, _ d: UserDefaults = .standard) {
        d.set(value, forKey: goalKey)
    }
}
