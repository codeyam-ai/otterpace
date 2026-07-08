import Foundation

// MARK: - Movement reminders (local notifications)
//
// On-device "time to move" nudges via UNUserNotificationCenter. No backend, no
// account — purely local. Three independently-toggleable reminders, all in
// Buddy's gentle, never-shame voice:
//
//   • daily       — a calendar reminder at a time the user picks (repeats daily)
//   • goal        — an evening nudge worded to be step-goal-aware (repeats daily)
//   • inactivity  — fires N hours after the user's ACTUAL last movement. A
//                   HealthKit background-delivery observer re-arms it whenever new
//                   step/distance data lands, so it tracks real stillness (not how
//                   long the app has been closed) and reopening the app no longer
//                   silently resets the clock.
//
// Honest iOS limits: a *pre-scheduled* local notification can't read your live
// step count at fire time, so the goal nudge is a daily evening reminder whose
// copy handles the "maybe you already hit it" case. The inactivity nudge instead
// leans on HealthKit background delivery to re-arm itself against your real
// last-movement time, so it reflects genuine stillness rather than app-close time.
//
// Authorization is only ever requested when the user turns a reminder ON in
// Settings. Reminder prefs default OFF, so scenarios/previews never schedule
// anything or trigger a permission prompt.

/// The user's reminder preferences, persisted in `UserDefaults` (no account).
public struct ReminderSettings: Equatable {
    public var dailyEnabled: Bool
    public var dailyHour: Int
    public var dailyMinute: Int
    public var goalEnabled: Bool
    public var inactivityEnabled: Bool
    public var inactivityHours: Int

    public static let defaultDailyHour = 18      // 6pm
    public static let goalHour = 19              // 7pm evening nudge
    public static let inactivityOptions = [2, 3, 4]
    public static let defaultInactivityHours = 3

    private enum Key {
        static let daily = "otterpaceRemindDaily"
        static let dailyHour = "otterpaceRemindDailyHour"
        static let dailyMinute = "otterpaceRemindDailyMinute"
        static let goal = "otterpaceRemindGoal"
        static let inactivity = "otterpaceRemindInactivity"
        static let inactivityHours = "otterpaceRemindInactivityHours"
    }

    public init(dailyEnabled: Bool = false, dailyHour: Int = defaultDailyHour, dailyMinute: Int = 0,
                goalEnabled: Bool = false, inactivityEnabled: Bool = false,
                inactivityHours: Int = defaultInactivityHours) {
        self.dailyEnabled = dailyEnabled
        self.dailyHour = dailyHour
        self.dailyMinute = dailyMinute
        self.goalEnabled = goalEnabled
        self.inactivityEnabled = inactivityEnabled
        self.inactivityHours = inactivityHours
    }

    public static func load(_ d: UserDefaults = .standard) -> ReminderSettings {
        let hour = d.object(forKey: Key.dailyHour) != nil ? d.integer(forKey: Key.dailyHour) : defaultDailyHour
        let inact = d.integer(forKey: Key.inactivityHours)
        return ReminderSettings(
            dailyEnabled: d.bool(forKey: Key.daily),
            dailyHour: hour,
            dailyMinute: d.integer(forKey: Key.dailyMinute),
            goalEnabled: d.bool(forKey: Key.goal),
            inactivityEnabled: d.bool(forKey: Key.inactivity),
            inactivityHours: inact > 0 ? inact : defaultInactivityHours
        )
    }

    public func save(_ d: UserDefaults = .standard) {
        d.set(dailyEnabled, forKey: Key.daily)
        d.set(dailyHour, forKey: Key.dailyHour)
        d.set(dailyMinute, forKey: Key.dailyMinute)
        d.set(goalEnabled, forKey: Key.goal)
        d.set(inactivityEnabled, forKey: Key.inactivity)
        d.set(inactivityHours, forKey: Key.inactivityHours)
    }

    public var anyEnabled: Bool { dailyEnabled || goalEnabled || inactivityEnabled }
}

/// Pure scheduling math for the real-inactivity nudge. Deliberately free of
/// HealthKit / UserNotifications types so it unit-tests in the macOS test build
/// without a device entitlement — the HealthKit glue that feeds it lives in
/// `MovementActivityMonitor` (iOS-only).
public enum InactivitySchedule {
    /// When the ideal fire time is already past (the user last moved long ago),
    /// fire this soon instead — an overdue nudge should still go out, and a UN
    /// time-interval trigger needs a strictly-positive delay.
    public static let pastDueBuffer: TimeInterval = 60

    /// The `Date` the inactivity nudge should fire: `hours` after the user's last
    /// movement. Returns `nil` when there's no movement to key off (nothing to
    /// schedule). A time already in the past clamps to `now + pastDueBuffer` so an
    /// overdue nudge fires promptly rather than being dropped.
    public static func fireDate(lastMovement: Date?, hours: Int, now: Date = Date()) -> Date? {
        guard let last = lastMovement else { return nil }
        let candidate = last.addingTimeInterval(TimeInterval(max(1, hours) * 3600))
        return candidate > now ? candidate : now.addingTimeInterval(pastDueBuffer)
    }
}

/// Copy for each reminder, kept here so it's testable and consistent in Buddy's
/// never-shame voice.
public enum ReminderCopy {
    public static let dailyTitle = "Time to move 🐾"
    public static let dailyBody = "A short walk keeps things ticking over. Buddy's ready whenever you are — no rush."
    public static let goalTitle = "Evening check-in"
    public static let goalBody = "If you haven't reached your step goal yet, a relaxed walk gets you there. Already done? Nice — consider this a wave from Buddy."
    public static let inactivityTitle = "Stretch your legs?"
    public static let inactivityBody = "It's been a little while since you moved. A couple of easy minutes is plenty."
}

/// Schedules/cancels the local notifications. The real implementation talks to
/// UNUserNotificationCenter on iOS; everywhere else (macOS test builds) it's a
/// no-op so `AppCore` still compiles and unit-tests without a notification entitlement.
public protocol MovementReminderScheduling {
    /// Ask the user for notification permission. Returns whether it's granted.
    func requestAuthorization() async -> Bool
    /// Current permission state, without prompting.
    func isAuthorized() async -> Bool
    /// App became active: (re)schedule the daily + goal reminders. It deliberately
    /// does NOT touch the inactivity reminder — opening the app is not movement, so
    /// the "have you moved" clock must not reset here (see `armInactivity`).
    func applyForeground(_ settings: ReminderSettings)
    /// Arm (or clear) the inactivity reminder at an absolute fire date. `fireAt`
    /// comes from `InactivitySchedule.fireDate` off the user's real last movement;
    /// a `nil` `fireAt` (or the reminder disabled) removes any pending request.
    func armInactivity(fireAt: Date?, settings: ReminderSettings)
    /// Remove every Otterpace reminder (used when the user turns everything off).
    func cancelAll()
}

public enum ReminderID {
    public static let daily = "otterpace.reminder.daily"
    public static let goal = "otterpace.reminder.goal"
    public static let inactivity = "otterpace.reminder.inactivity"
    public static let all = [daily, goal, inactivity]
}

#if os(iOS)
import UserNotifications

/// Production scheduler backed by `UNUserNotificationCenter`.
public struct MovementReminderScheduler: MovementReminderScheduling {
    public init() {}

    private var center: UNUserNotificationCenter { .current() }

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    public func applyForeground(_ settings: ReminderSettings) {
        // NOTE: the inactivity reminder is intentionally left alone here — opening
        // the app is not movement, so it must not reset the clock. It's re-armed
        // from the real last-movement time via `armInactivity` (see the monitor).
        if settings.dailyEnabled {
            var when = DateComponents()
            when.hour = settings.dailyHour
            when.minute = settings.dailyMinute
            schedule(id: ReminderID.daily, title: ReminderCopy.dailyTitle, body: ReminderCopy.dailyBody,
                     trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [ReminderID.daily])
        }

        if settings.goalEnabled {
            var when = DateComponents()
            when.hour = ReminderSettings.goalHour
            when.minute = 0
            schedule(id: ReminderID.goal, title: ReminderCopy.goalTitle, body: ReminderCopy.goalBody,
                     trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [ReminderID.goal])
        }
    }

    public func armInactivity(fireAt: Date?, settings: ReminderSettings) {
        guard settings.inactivityEnabled, let fireAt = fireAt else {
            center.removePendingNotificationRequests(withIdentifiers: [ReminderID.inactivity])
            return
        }
        // Absolute fire time → a positive delay for the trigger (clamped so a
        // just-past date still schedules rather than throwing).
        let interval = max(1, fireAt.timeIntervalSinceNow)
        schedule(id: ReminderID.inactivity, title: ReminderCopy.inactivityTitle, body: ReminderCopy.inactivityBody,
                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    }

    public func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: ReminderID.all)
    }

    private func schedule(id: String, title: String, body: String, trigger: UNNotificationTrigger) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
#else
/// No-op scheduler for non-iOS builds (macOS unit tests) — no notification
/// entitlement, nothing to schedule.
public struct MovementReminderScheduler: MovementReminderScheduling {
    public init() {}
    public func requestAuthorization() async -> Bool { false }
    public func isAuthorized() async -> Bool { false }
    public func applyForeground(_ settings: ReminderSettings) {}
    public func armInactivity(fireAt: Date?, settings: ReminderSettings) {}
    public func cancelAll() {}
}
#endif
