import Foundation

// MARK: - Activity freshness (the one question every nudge asks first)
//
// "How old is our picture of this user, and is it fresh enough to act on?"
//
// Every false-positive nudge this app has shipped came from acting on a stale
// picture: a 7pm calendar trigger that couldn't read your steps, a server cron
// deciding from a heartbeat the app hadn't sent since morning. Both spoke with
// confidence about data they didn't have.
//
// The rule here is one line: **when freshness is unknown, stay quiet.** A nudge
// that doesn't fire is a missed encouragement. A nudge that fires wrongly teaches
// the user the app is dumb, and that lesson is permanent — they turn
// notifications off and never turn them back on.
//
// Note the deliberate contrast with `localHourIn`'s UTC fallback in
// `api/_lib/nudge.ts`: an unknown *timezone* is a rollout gap, where suppressing
// would silently disable the feature for everyone on an older client. An unknown
// *freshness* is not a gap — it is a real signal that we don't know enough to
// speak. So timezone degrades, and freshness suppresses.
//
// Pure and free of HealthKit / UserNotifications types, so it unit-tests in the
// macOS build like `InactivitySchedule` does.
public enum ActivityFreshness {

    /// Which nudge is asking. Thresholds differ because the nudges make
    /// different claims, and a bolder claim needs fresher data.
    public enum Nudge: Equatable {
        /// "You're short of your step goal" — a specific claim about a number
        /// that changes minute to minute.
        case goal
        /// "It's been a while since you moved" — inherently about a long gap, so
        /// it tolerates a much older picture.
        case inactivity
    }

    /// A goal nudge names your step count, so it needs a recent read. This
    /// doubles as the maximum LEAD TIME for arming the goal nudge: a step count
    /// read now says nothing about your steps nine hours from now, so we refuse
    /// to arm that far ahead and let the movement observer arm it nearer the
    /// hour instead. That is what "verify at fire time" actually means here.
    public static let goalMaxAge: TimeInterval = 30 * 60

    /// An inactivity nudge only claims a gap exists, so a several-hour-old
    /// picture still supports it. Mirrored server-side as the heartbeat
    /// staleness bound in `api/_lib/nudge.ts`, so device and server agree on
    /// what "too old to act on" means.
    public static let inactivityMaxAge: TimeInterval = 6 * 3600

    public static func maxAge(for nudge: Nudge) -> TimeInterval {
        switch nudge {
        case .goal:       return goalMaxAge
        case .inactivity: return inactivityMaxAge
        }
    }

    /// How old our picture is, or nil when there is no picture at all. Clamped at
    /// zero so a clock skew that puts the observation slightly in the future
    /// reads as "just now" rather than as a negative age that trivially passes
    /// every threshold.
    public static func age(observedAt: Date?, now: Date = Date()) -> TimeInterval? {
        guard let observedAt else { return nil }
        return max(0, now.timeIntervalSince(observedAt))
    }

    /// True when the picture is recent enough for `nudge` to speak. Unknown
    /// (`observedAt == nil`) is never fresh.
    public static func isFresh(observedAt: Date?, for nudge: Nudge, now: Date = Date()) -> Bool {
        guard let age = age(observedAt: observedAt, now: now) else { return false }
        return age <= maxAge(for: nudge)
    }

    /// The question callers actually ask. Inverse of `isFresh`, named so the
    /// call site reads as the safety decision it is.
    public static func shouldSuppress(observedAt: Date?, for nudge: Nudge, now: Date = Date()) -> Bool {
        !isFresh(observedAt: observedAt, for: nudge, now: now)
    }

    /// The same decision, expressed over `TodayState.minutesSinceLastMovement` —
    /// the shape the UI already has on hand.
    ///
    /// Lives here rather than in the Settings view so the row that TELLS the user
    /// "Buddy won't nudge you right now" is computed from the identical rule the
    /// schedulers act on. If these were two separate expressions, Settings could
    /// promise silence while a nudge still went out.
    ///
    /// A negative value is treated as zero (just moved), matching `age`'s clamp.
    public static func isStale(minutesSinceLastMovement minutes: Int,
                               for nudge: Nudge,
                               now: Date = Date()) -> Bool {
        let observedAt = now.addingTimeInterval(-Double(max(0, minutes)) * 60)
        return shouldSuppress(observedAt: observedAt, for: nudge, now: now)
    }
}
