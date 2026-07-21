import Foundation

// Pure presentation helpers shared by the Today dashboard components. Kept free
// of SwiftUI so they're straightforward to unit-test.

/// Group a whole number with locale thousands separators, e.g. 11240 -> "11,240".
func formatted(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

/// Render a mileage value: a whole number drops the decimal ("8"), otherwise one
/// decimal place ("8.4"). Shared by the coach copy and the activity-week rollups
/// so the two never drift apart.
func miles(_ d: Double) -> String {
    d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
}

/// Compact "time since last movement" label: "now", "45m", "1h", "1h32m".
func movementLabel(_ minutes: Int) -> String {
    if minutes <= 0 { return "now" }
    if minutes < 60 { return "\(minutes)m" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h)h" : "\(h)h\(m)m"
}

/// Caption shown under the step count in the goal ring. Stays warm and
/// celebratory once the goal is met — with extra cheer when it's been passed —
/// and otherwise frames the goal the user is working toward.
func stepGoalCaption(reached: Bool, exceeded: Bool, goal: Int) -> String {
    if exceeded { return "Goal crushed! 🎉" }
    if reached { return "goal hit! 🎉" }
    return "of \(formatted(goal))"
}

/// Spoken VoiceOver summary for the step-goal ring. Never shame-based, always
/// whole numbers; mirrors the three visual states of `stepGoalCaption`.
func stepGoalAccessibilityValue(steps: Int, goal: Int, remaining: Int, reached: Bool, exceeded: Bool) -> String {
    if exceeded { return "\(formatted(steps)) steps. You crushed your goal of \(formatted(goal))." }
    if reached { return "\(formatted(steps)) steps. Goal of \(formatted(goal)) reached." }
    return "\(formatted(steps)) of \(formatted(goal)) steps. \(formatted(remaining)) to go."
}

/// Clamp a goal-progress fraction to the range the step ring can actually draw.
/// A circle's trim can't render more than a full turn, so anything at or above
/// 1.0 (the goal met or crushed) maps to a complete ring; a tiny floor keeps the
/// rounded leading cap visible at 0%. Drives both the arc length and the
/// gradient span so color and length always agree.
func stepRingFill(_ progress: Double) -> Double {
    min(1.0, max(0.001, progress))
}

/// The Activity History week-header rollup: "14.7 mi · 3 runs · 3 rest", with a
/// "so far" qualifier while the week is still in progress. That suffix is the
/// user-visible signal that the smaller numbers describe a week still being
/// lived rather than a finished week that went badly, so it lives here as pure
/// logic instead of only being observable through a screenshot.
func weekRollup(miles m: Double, runCount: Int, restDays: Int, daysElapsed: Int) -> String {
    let base = "\(miles(m)) mi · \(runCount) \(runCount == 1 ? "run" : "runs") · \(restDays) rest"
    return daysElapsed < 7 ? base + " so far" : base
}

/// Spoken VoiceOver form of `weekRollup`, with words instead of separators and
/// the elapsed-day count stated outright so a screen-reader user gets the same
/// "this week isn't over" context the visual "so far" conveys.
func weekRollupSpoken(miles m: Double, runCount: Int, restDays: Int, daysElapsed: Int) -> String {
    let base = "\(miles(m)) miles, \(runCount) \(runCount == 1 ? "run" : "runs"), \(restDays) rest \(restDays == 1 ? "day" : "days")"
    return daysElapsed < 7 ? base + " so far, \(daysElapsed) of 7 days elapsed" : base
}

/// Render an ISO `yyyy-MM-dd` date as "EEE, MMM d" (e.g. "Mon, Jun 22").
/// Falls back to the raw string when it isn't a valid ISO date.
func prettyDate(_ iso: String) -> String {
    let inFmt = DateFormatter()
    inFmt.dateFormat = "yyyy-MM-dd"
    inFmt.locale = Locale(identifier: "en_US_POSIX")
    guard let d = inFmt.date(from: iso) else { return iso }
    let out = DateFormatter()
    out.dateFormat = "EEE, MMM d"
    out.locale = Locale(identifier: "en_US_POSIX")
    return out.string(from: d)
}
