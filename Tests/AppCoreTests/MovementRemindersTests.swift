import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class MovementRemindersTests: XCTestCase {

    // A fixed reference point so the pure fireDate math is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: InactivitySchedule.fireDate (pure)

    // Last movement 2h ago with a 3h setting → the nudge is due ~1h from now.
    func testFireDateFiresOneHourOut() {
        let fire = InactivitySchedule.fireDate(lastMovement: now.addingTimeInterval(-2 * 3600), hours: 3, now: now)
        XCTAssertEqual(fire?.timeIntervalSince(now) ?? -1, 3600, accuracy: 1)
    }

    // Last movement just now with a 3h setting → pushed out the full ~3h.
    func testFireDateDefersWhenJustMoved() {
        let fire = InactivitySchedule.fireDate(lastMovement: now, hours: 3, now: now)
        XCTAssertEqual(fire?.timeIntervalSince(now) ?? -1, 3 * 3600, accuracy: 1)
    }

    // Last movement 5h ago with a 3h setting is overdue → clamps to fire promptly.
    func testFireDatePastDueClampsToBuffer() {
        let fire = InactivitySchedule.fireDate(lastMovement: now.addingTimeInterval(-5 * 3600), hours: 3, now: now)
        XCTAssertEqual(fire?.timeIntervalSince(now) ?? -1, InactivitySchedule.pastDueBuffer, accuracy: 1)
    }

    // No known movement → nothing to schedule.
    func testFireDateNilWhenNoMovement() {
        XCTAssertNil(InactivitySchedule.fireDate(lastMovement: nil, hours: 3, now: now))
    }

    // A non-positive hours setting is floored to 1h so it can never fire in the past.
    func testFireDateClampsNonPositiveHours() {
        let fire = InactivitySchedule.fireDate(lastMovement: now, hours: 0, now: now)
        XCTAssertEqual(fire?.timeIntervalSince(now) ?? -1, 3600, accuracy: 1)
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
        XCTAssertEqual(fireAt!.timeIntervalSinceNow, 2 * 3600, accuracy: 5)
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
}

/// A test double that records `armInactivity` calls so we can assert the fire date
/// the model computed without touching UNUserNotificationCenter.
private final class SpyScheduler: MovementReminderScheduling {
    var armCalls: [(fireAt: Date?, settings: ReminderSettings)] = []
    func requestAuthorization() async -> Bool { true }
    func isAuthorized() async -> Bool { true }
    func applyForeground(_ settings: ReminderSettings) {}
    func armInactivity(fireAt: Date?, settings: ReminderSettings) { armCalls.append((fireAt, settings)) }
    func cancelAll() {}
}
