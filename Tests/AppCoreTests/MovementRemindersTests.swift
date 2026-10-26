import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class MovementRemindersTests: XCTestCase {

    // A fixed reference point so the pure fireDate math is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// `now` is 22:13 UTC — overnight quiet hours on a UTC CI runner, which would
    /// defer every fire date below. Pinned to Pacific, where it is mid-afternoon
    /// (14:13), so these tests measure the idle math and nothing else.
    private var afternoon: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    // MARK: InactivitySchedule.fireDate (pure)

    // Last movement 2h ago with a 3h setting → the nudge is due ~1h from now.
    func testFireDateFiresOneHourOut() {
        let fire = InactivitySchedule.fireDate(lastMovement: now.addingTimeInterval(-2 * 3600), hours: 3, now: now,
                                               calendar: afternoon)
        XCTAssertEqual(fire?.timeIntervalSince(now) ?? -1, 3600, accuracy: 1)
    }

    // Last movement just now with a 3h setting → pushed out the full ~3h.
    func testFireDateDefersWhenJustMoved() {
        let fire = InactivitySchedule.fireDate(lastMovement: now, hours: 3, now: now, calendar: afternoon)
        XCTAssertEqual(fire?.timeIntervalSince(now) ?? -1, 3 * 3600, accuracy: 1)
    }

    // Last movement 5h ago with a 3h setting is overdue → clamps to fire promptly.
    func testFireDatePastDueClampsToBuffer() {
        let fire = InactivitySchedule.fireDate(lastMovement: now.addingTimeInterval(-5 * 3600), hours: 3, now: now,
                                               calendar: afternoon)
        XCTAssertEqual(fire?.timeIntervalSince(now) ?? -1, InactivitySchedule.pastDueBuffer, accuracy: 1)
    }

    // No known movement → nothing to schedule.
    func testFireDateNilWhenNoMovement() {
        XCTAssertNil(InactivitySchedule.fireDate(lastMovement: nil, hours: 3, now: now))
    }

    // A non-positive hours setting is floored to 1h so it can never fire in the past.
    func testFireDateClampsNonPositiveHours() {
        let fire = InactivitySchedule.fireDate(lastMovement: now, hours: 0, now: now, calendar: afternoon)
        XCTAssertEqual(fire?.timeIntervalSince(now) ?? -1, 3600, accuracy: 1)
    }

    // MARK: Quiet hours + time-of-day copy (pure)

    /// A pinned calendar so the hour math doesn't depend on the machine's zone.
    private var nyCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func ny(day: Int = 15, hour: Int, minute: Int = 0) -> Date {
        nyCalendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute))!
    }

    // Would fire at 11:30pm → held until 8:00 the next morning.
    func testFireDateLateEveningDefersToNextMorning() {
        let fire = InactivitySchedule.fireDate(lastMovement: ny(hour: 20, minute: 30), hours: 3,
                                               now: ny(hour: 20, minute: 30), calendar: nyCalendar)
        XCTAssertEqual(fire, ny(day: 16, hour: 8))
    }

    // Still since 9:30pm, phone picked up at 6:45am: past due, but the 60s clamp
    // lands in quiet hours → held until 8:00 that same morning.
    func testFireDatePastDueBeforeMorningDefersToEight() {
        let fire = InactivitySchedule.fireDate(lastMovement: ny(day: 14, hour: 21, minute: 30), hours: 3,
                                               now: ny(hour: 6, minute: 45), calendar: nyCalendar)
        XCTAssertEqual(fire, ny(hour: 8))
    }

    // A daytime fire time is left exactly as computed.
    func testFireDateDaytimeIsUnchanged() {
        let fire = InactivitySchedule.fireDate(lastMovement: ny(hour: 11), hours: 3,
                                               now: ny(hour: 11), calendar: nyCalendar)
        XCTAssertEqual(fire, ny(hour: 14))
    }

    func testDaypartBoundaries() {
        let cases: [(Int, Int, NudgeDaypart)] = [
            (7, 59, .quiet), (8, 0, .morning), (10, 59, .morning), (11, 0, .daytime),
            (18, 59, .daytime), (19, 0, .evening), (20, 59, .evening), (21, 0, .quiet),
        ]
        for (hour, minute, expected) in cases {
            XCTAssertEqual(NudgeDaypart.at(ny(hour: hour, minute: minute), calendar: nyCalendar), expected,
                           "\(hour):\(minute)")
        }
    }

    func testInactivityCopyByDaypart() {
        let morning = ReminderCopy.inactivity(at: ny(hour: 8), calendar: nyCalendar)
        XCTAssertEqual(morning.title, "Good morning ☀️")
        XCTAssertEqual(morning.body, "Buddy's up and stretching. Whenever you're ready, an easy start to the day is plenty.")

        let daytime = ReminderCopy.inactivity(at: ny(hour: 14), calendar: nyCalendar)
        XCTAssertEqual(daytime.title, "Stretch your legs?")
        XCTAssertEqual(daytime.body, "It's been a little while since you moved. A couple of easy minutes is plenty.")

        let evening = ReminderCopy.inactivity(at: ny(hour: 20, minute: 15), calendar: nyCalendar)
        XCTAssertEqual(evening.title, "Winding down 🌙")
        XCTAssertEqual(evening.body, "Hope today was a good one. A gentle stretch before bed is a nice way to close it out, or just rest.")
    }

    // Sleep looks like stillness — the morning and evening copy must never say so.
    func testMorningAndEveningCopyNeverMentionElapsedTime() {
        for date in [ny(hour: 9), ny(hour: 19, minute: 30)] {
            XCTAssertFalse(ReminderCopy.inactivity(at: date, calendar: nyCalendar).body.contains("while since you moved"))
        }
    }

    // MARK: SeededHealthDataSource.lastMovementDate

    private func defaults(_ pairs: [String: Any]) -> UserDefaults {
        let d = UserDefaults(suiteName: "MovementTests.\(UUID().uuidString)")!
        for (k, v) in pairs { d.set(v, forKey: k) }
        return d
    }

    // rbLastMovementMinutesAgo places the last movement that many minutes back.
    func testSeededLastMovementFromExplicitKey() async {
        let src = SeededHealthDataSource(defaults: defaults(["rbLastMovementMinutesAgo": 45]))
        let date = await src.lastMovementDate()
        XCTAssertEqual(date?.timeIntervalSinceNow ?? 0, -45 * 60, accuracy: 2)
    }

    // Falls back to the existing rbMinutesSinceMovement when the explicit key is absent.
    func testSeededLastMovementFallsBackToMinutesSinceMovement() async {
        let src = SeededHealthDataSource(defaults: defaults(["rbMinutesSinceMovement": 90]))
        let date = await src.lastMovementDate()
        XCTAssertEqual(date?.timeIntervalSinceNow ?? 0, -90 * 60, accuracy: 2)
    }

    // Neither key seeded → no known movement, so nothing to key the nudge off.
    func testSeededLastMovementNilWhenUnseeded() async {
        let date = await SeededHealthDataSource(defaults: defaults([:])).lastMovementDate()
        XCTAssertNil(date)
    }

    // MARK: Model.rearmInactivity — the foreground/background re-arm

    // With the reminder on, re-arm computes an absolute fire date from REAL last
    // movement (not a blind cancel): moved 60m ago, 3h setting → armed ~2h out.
    @MainActor func testRearmComputesFireFromLastMovement() async {
        let d = defaults(["rbLastMovementMinutesAgo": 60, "rbConnected": true])
        let model = OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d), defaults: d)
        let spy = SpyScheduler()
        await model.rearmInactivity(spy, settings: ReminderSettings(inactivityEnabled: true, inactivityHours: 3), now: Date())
        XCTAssertEqual(spy.armCalls.count, 1)
        let fireAt = spy.armCalls.first!.fireAt
        XCTAssertNotNil(fireAt)
        // The seeded source keys off the real clock, so a run in the evening lands
        // in quiet hours — expect the same overnight deferral the model applies.
        let expected = NudgeDaypart.deferringQuietHours(Date().addingTimeInterval(2 * 3600))
        XCTAssertEqual(fireAt!.timeIntervalSince(expected), 0, accuracy: 5)
    }

    // Reminder off → re-arm clears any pending nudge (fireAt nil), never schedules.
    @MainActor func testRearmClearsWhenDisabled() async {
        let d = defaults(["rbLastMovementMinutesAgo": 60])
        let model = OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d), defaults: d)
        let spy = SpyScheduler()
        await model.rearmInactivity(spy, settings: ReminderSettings(inactivityEnabled: false), now: Date())
        XCTAssertEqual(spy.armCalls.count, 1)
        XCTAssertNil(spy.armCalls.first!.fireAt)
    }

    // MARK: GoalNudgeSchedule.fireDate (pure) — the fixed-7pm false positive

    /// `now` at a fixed wall-clock hour on a real date, so lead-time math is
    /// deterministic regardless of when the suite runs.
    private func at(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 15
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    // THE bug this replaces: at 14,000 of 10,000 steps the old fixed trigger
    // still fired. Now there is simply nothing to arm.
    func testGoalNotArmedOnceGoalIsMet() {
        XCTAssertNil(GoalNudgeSchedule.fireDate(steps: 14_000, goalSteps: 10_000, now: at(hour: 18, minute: 45)))
    }

    // Genuinely short, and 7pm is close enough that the step count can be
    // trusted → arm it for 7pm.
    func testGoalArmedWhenShortAndHourIsNear() {
        let fire = GoalNudgeSchedule.fireDate(steps: 3_100, goalSteps: 10_000, now: at(hour: 18, minute: 45))
        XCTAssertNotNil(fire)
        XCTAssertEqual(fire, at(hour: 19))
    }

    // Same shortfall at 9am: a step count read now says nothing about 7pm, so we
    // decline to arm and let the observer arm it nearer the hour. This is what
    // "verify at fire time" means in practice.
    func testGoalNotArmedTooFarAhead() {
        XCTAssertNil(GoalNudgeSchedule.fireDate(steps: 3_100, goalSteps: 10_000, now: at(hour: 9)))
    }

    // Past the hour → tomorrow's nudge is tomorrow's decision, never armed a day
    // ahead against today's data.
    func testGoalNotArmedAfterTheHourHasPassed() {
        XCTAssertNil(GoalNudgeSchedule.fireDate(steps: 3_100, goalSteps: 10_000, now: at(hour: 20)))
    }

    // No goal set → nothing to be "short of".
    func testGoalNotArmedWithoutAGoal() {
        XCTAssertNil(GoalNudgeSchedule.fireDate(steps: 0, goalSteps: 0, now: at(hour: 18, minute: 45)))
    }

    // MARK: Model.rearmGoal

    // Short of the goal near the hour → armed. Proves the model reads real step
    // data rather than scheduling blind.
    @MainActor func testRearmGoalArmsWhenShort() async {
        let d = defaults(["rbSteps": 3_100, "rbGoalSteps": 10_000, "rbConnected": true])
        let model = OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d), defaults: d)
        let spy = SpyScheduler()
        await model.rearmGoal(spy, settings: ReminderSettings(goalEnabled: true), now: at(hour: 18, minute: 45))
        XCTAssertEqual(spy.goalCalls.count, 1)
        XCTAssertEqual(spy.goalCalls.first!.fireAt, at(hour: 19))
    }

    // Goal already met → the model takes the nudge DOWN (nil), it doesn't just
    // skip scheduling. Cancelling is the half that makes re-evaluation matter.
    @MainActor func testRearmGoalCancelsOnceGoalIsMet() async {
        let d = defaults(["rbSteps": 11_240, "rbGoalSteps": 10_000, "rbConnected": true])
        let model = OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d), defaults: d)
        let spy = SpyScheduler()
        await model.rearmGoal(spy, settings: ReminderSettings(goalEnabled: true), now: at(hour: 18, minute: 45))
        XCTAssertEqual(spy.goalCalls.count, 1)
        XCTAssertNil(spy.goalCalls.first!.fireAt)
    }

    // Reminder off → clears, never schedules.
    @MainActor func testRearmGoalClearsWhenDisabled() async {
        let d = defaults(["rbSteps": 3_100, "rbGoalSteps": 10_000])
        let model = OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d), defaults: d)
        let spy = SpyScheduler()
        await model.rearmGoal(spy, settings: ReminderSettings(goalEnabled: false), now: at(hour: 18, minute: 45))
        XCTAssertEqual(spy.goalCalls.count, 1)
        XCTAssertNil(spy.goalCalls.first!.fireAt)
    }

    // MARK: de-dup hint for the server

    // Arming records the fire time so the heartbeat can tell the server this
    // device has the idle spell covered.
    @MainActor func testArmedInactivityISOReflectsTheArmedNudge() async {
        let d = defaults(["rbLastMovementMinutesAgo": 60, "rbConnected": true])
        let model = OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d), defaults: d)
        await model.rearmInactivity(SpyScheduler(),
                                    settings: ReminderSettings(inactivityEnabled: true, inactivityHours: 3),
                                    now: Date())
        XCTAssertNotNil(model.armedInactivityISO())
    }

    // Nothing armed → nil, which the server reads as "send yours".
    @MainActor func testArmedInactivityISONilWhenDisabled() async {
        let d = defaults(["rbLastMovementMinutesAgo": 60])
        let model = OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d), defaults: d)
        await model.rearmInactivity(SpyScheduler(), settings: ReminderSettings(inactivityEnabled: false), now: Date())
        XCTAssertNil(model.armedInactivityISO())
    }
}

// MARK: - MovementActivityMonitor + MovementReminderScheduler decisions
//
// Both classes are iOS-only glue; these exercise the decisions they delegate to,
// which build on macOS.
final class MovementReminderPlumbingTests: XCTestCase {

    private func at(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: hour, minute: minute))!
    }

    private var nyCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    // The observer runs when either data-driven nudge is on, and only then.
    func testMonitorObservesWhenEitherNudgeIsOn() {
        XCTAssertTrue(MovementActivityMonitor.observes(ReminderSettings(inactivityEnabled: true)))
        XCTAssertTrue(MovementActivityMonitor.observes(ReminderSettings(goalEnabled: true)))
        XCTAssertFalse(MovementActivityMonitor.observes(ReminderSettings(dailyEnabled: true)))
    }

    // A background wake re-arms the inactivity nudge from the real last movement,
    // and leaves the goal nudge alone when it's off.
    @MainActor func testMonitorRearmArmsInactivityFromLastMovement() async {
        let spy = SpyScheduler()
        await MovementActivityMonitor.rearm(ReminderSettings(inactivityEnabled: true, inactivityHours: 3),
                                            source: FakeHealthSource(lastMovement: at(hour: 12)),
                                            scheduler: spy, now: at(hour: 13))
        XCTAssertEqual(spy.armCalls.map(\.fireAt), [at(hour: 15)])
        XCTAssertTrue(spy.goalCalls.isEmpty)
    }

    // Short of the goal near 7pm → the goal nudge is armed for 7pm.
    @MainActor func testMonitorRearmArmsGoalWhenShort() async {
        let spy = SpyScheduler()
        await MovementActivityMonitor.rearm(ReminderSettings(goalEnabled: true),
                                            source: FakeHealthSource(steps: 3_100, goalSteps: 10_000),
                                            scheduler: spy, now: at(hour: 18, minute: 45))
        XCTAssertEqual(spy.goalCalls.map(\.fireAt), [at(hour: 19)])
        XCTAssertTrue(spy.armCalls.isEmpty)
    }

    // Goal already met → the wake takes any pending goal nudge down.
    @MainActor func testMonitorRearmCancelsGoalOnceMet() async {
        let spy = SpyScheduler()
        await MovementActivityMonitor.rearm(ReminderSettings(goalEnabled: true),
                                            source: FakeHealthSource(steps: 12_000, goalSteps: 10_000),
                                            scheduler: spy, now: at(hour: 18, minute: 45))
        XCTAssertEqual(spy.goalCalls.count, 1)
        XCTAssertNil(spy.goalCalls.first!.fireAt)
    }

    // The daily reminder repeats at the user's chosen time, and only when on.
    func testSchedulerDailyTimeOnlyWhenEnabled() {
        let on = ReminderSettings(dailyEnabled: true, dailyHour: 7, dailyMinute: 30)
        XCTAssertEqual(MovementReminderScheduler.dailyTime(on), DateComponents(hour: 7, minute: 30))
        XCTAssertNil(MovementReminderScheduler.dailyTime(ReminderSettings(dailyEnabled: false)))
    }

    // The inactivity request carries the time-of-day copy and the delay to fire.
    func testSchedulerInactivityRequestUsesDaypartCopy() {
        let fire = nyCalendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 8))!
        let request = MovementReminderScheduler.inactivityRequest(
            fireAt: fire, settings: ReminderSettings(inactivityEnabled: true),
            now: fire.addingTimeInterval(-3600), calendar: nyCalendar)
        XCTAssertEqual(request, OneShotReminder(title: ReminderCopy.inactivityMorningTitle,
                                                body: ReminderCopy.inactivityMorningBody, delay: 3600))
    }

    // The evening goal nudge is a one-shot with the goal copy.
    func testSchedulerGoalRequest() {
        let request = MovementReminderScheduler.goalRequest(
            fireAt: at(hour: 19), settings: ReminderSettings(goalEnabled: true), now: at(hour: 18, minute: 45))
        XCTAssertEqual(request, OneShotReminder(title: ReminderCopy.goalTitle, body: ReminderCopy.goalBody, delay: 900))
    }

    // Off, or no fire time (the nudge is no longer true) → nothing to schedule,
    // which the scheduler turns into "take the pending request down".
    func testSchedulerRequestsNilWhenOffOrNoFireTime() {
        let now = at(hour: 12)
        XCTAssertNil(MovementReminderScheduler.inactivityRequest(fireAt: now, settings: ReminderSettings(), now: now))
        XCTAssertNil(MovementReminderScheduler.inactivityRequest(fireAt: nil, settings: ReminderSettings(inactivityEnabled: true), now: now))
        XCTAssertNil(MovementReminderScheduler.goalRequest(fireAt: now, settings: ReminderSettings(), now: now))
        XCTAssertNil(MovementReminderScheduler.goalRequest(fireAt: nil, settings: ReminderSettings(goalEnabled: true), now: now))
    }

    // A just-past fire time still schedules (a trigger needs a positive delay).
    func testSchedulerDelayClampsPastFireTimes() {
        let now = at(hour: 12)
        XCTAssertEqual(MovementReminderScheduler.delay(until: now.addingTimeInterval(-30), now: now), 1)
        XCTAssertEqual(MovementReminderScheduler.delay(until: now.addingTimeInterval(120), now: now), 120)
    }
}

/// A health source with fixed answers, for the monitor's re-arm decisions.
private struct FakeHealthSource: HealthDataSource {
    var lastMovement: Date? = nil
    var steps = 0
    var goalSteps = 10_000
    func authorizationState() -> HealthAuthState { .authorized }
    func requestAuthorization() async -> HealthAuthState { .authorized }
    func loadToday() async -> TodayState {
        var s = TodayState.empty
        s.steps = steps
        s.goalSteps = goalSteps
        return s
    }
    func lastMovementDate() async -> Date? { lastMovement }
}

/// A test double that records `armInactivity` calls so we can assert the fire date
/// the model computed without touching UNUserNotificationCenter.
private final class SpyScheduler: MovementReminderScheduling {
    var armCalls: [(fireAt: Date?, settings: ReminderSettings)] = []
    var goalCalls: [(fireAt: Date?, settings: ReminderSettings)] = []
    func requestAuthorization() async -> Bool { true }
    func isAuthorized() async -> Bool { true }
    func applyForeground(_ settings: ReminderSettings) {}
    func armGoal(fireAt: Date?, settings: ReminderSettings) { goalCalls.append((fireAt, settings)) }
    func armInactivity(fireAt: Date?, settings: ReminderSettings) { armCalls.append((fireAt, settings)) }
    func cancelAll() {}
}
