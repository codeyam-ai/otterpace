import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
//
// The rule under test is the one that keeps a nudge honest: when we can't tell
// how current our picture is, we say nothing. These are the cases that used to
// produce a confidently wrong notification.
final class ActivityFreshnessTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: age

    func testAgeIsNilWhenNothingObserved() {
        XCTAssertNil(ActivityFreshness.age(observedAt: nil, now: now))
    }

    func testAgeMeasuresBackwardsFromNow() {
        let age = ActivityFreshness.age(observedAt: now.addingTimeInterval(-600), now: now)
        XCTAssertEqual(age ?? -1, 600, accuracy: 1)
    }

    // A clock skew putting the observation slightly ahead of `now` must read as
    // "just now", not as a negative age that sails past every threshold.
    func testAgeClampsFutureObservationToZero() {
        let age = ActivityFreshness.age(observedAt: now.addingTimeInterval(300), now: now)
        XCTAssertEqual(age ?? -1, 0, accuracy: 0.001)
    }

    // MARK: the suppression rule

    // Unknown freshness is not "probably fine" — it's the signal to stay quiet.
    func testUnknownFreshnessSuppressesEveryNudge() {
        XCTAssertTrue(ActivityFreshness.shouldSuppress(observedAt: nil, for: .goal, now: now))
        XCTAssertTrue(ActivityFreshness.shouldSuppress(observedAt: nil, for: .inactivity, now: now))
    }

    // A goal nudge names your step count, so it needs a recent read.
    func testGoalNeedsAFreshPicture() {
        let fresh = now.addingTimeInterval(-10 * 60)   // 10m
        let stale = now.addingTimeInterval(-45 * 60)   // 45m
        XCTAssertFalse(ActivityFreshness.shouldSuppress(observedAt: fresh, for: .goal, now: now))
        XCTAssertTrue(ActivityFreshness.shouldSuppress(observedAt: stale, for: .goal, now: now))
    }

    // An inactivity nudge only claims a gap exists, so the same 45m picture that
    // is too stale for a goal nudge still supports it. The thresholds differ
    // because the claims differ.
    func testInactivityToleratesAnOlderPictureThanGoal() {
        let fortyFive = now.addingTimeInterval(-45 * 60)
        XCTAssertFalse(ActivityFreshness.shouldSuppress(observedAt: fortyFive, for: .inactivity, now: now))
        XCTAssertTrue(ActivityFreshness.shouldSuppress(observedAt: now.addingTimeInterval(-7 * 3600),
                                                       for: .inactivity, now: now))
    }

    // MARK: isStale(minutesSinceLastMovement:) — the shape the UI has on hand

    // What Settings shows must be the SAME rule the schedulers act on. If these
    // could disagree, the app could promise silence and still send a nudge.
    func testIsStaleMatchesTheSuppressionRule() {
        for minutes in [0, 5, 60, 359, 360, 361, 600] {
            let viaMinutes = ActivityFreshness.isStale(minutesSinceLastMovement: minutes,
                                                       for: .inactivity, now: now)
            let viaDate = ActivityFreshness.shouldSuppress(
                observedAt: now.addingTimeInterval(-Double(minutes) * 60),
                for: .inactivity, now: now)
            XCTAssertEqual(viaMinutes, viaDate, "disagreement at \(minutes) minutes")
        }
    }

    // Just-moved reads fresh; well past the 6h inactivity bound reads stale.
    func testIsStaleAcrossTheInactivityBound() {
        XCTAssertFalse(ActivityFreshness.isStale(minutesSinceLastMovement: 0, for: .inactivity, now: now))
        XCTAssertFalse(ActivityFreshness.isStale(minutesSinceLastMovement: 359, for: .inactivity, now: now))
        XCTAssertTrue(ActivityFreshness.isStale(minutesSinceLastMovement: 500, for: .inactivity, now: now))
    }

    // A negative minute count (clock skew upstream) must not read as wildly
    // fresh OR crash — it clamps to "just now", same as `age`.
    func testIsStaleClampsNegativeMinutes() {
        XCTAssertFalse(ActivityFreshness.isStale(minutesSinceLastMovement: -120, for: .inactivity, now: now))
    }

    // The goal nudge's tighter bound applies here too: 45m is fine for
    // inactivity but already too old to make a claim about your step count.
    func testIsStaleUsesThePerNudgeThreshold() {
        XCTAssertFalse(ActivityFreshness.isStale(minutesSinceLastMovement: 45, for: .inactivity, now: now))
        XCTAssertTrue(ActivityFreshness.isStale(minutesSinceLastMovement: 45, for: .goal, now: now))
    }

    // Exactly at the threshold still counts as fresh (<=, not <), so a value
    // landing precisely on the bound doesn't flip behavior unpredictably.
    func testThresholdBoundaryIsInclusive() {
        let atBound = now.addingTimeInterval(-ActivityFreshness.goalMaxAge)
        XCTAssertTrue(ActivityFreshness.isFresh(observedAt: atBound, for: .goal, now: now))
        let justPast = now.addingTimeInterval(-ActivityFreshness.goalMaxAge - 1)
        XCTAssertFalse(ActivityFreshness.isFresh(observedAt: justPast, for: .goal, now: now))
    }
}
