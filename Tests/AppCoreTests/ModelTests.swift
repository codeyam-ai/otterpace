import XCTest
@testable import AppCore

// XCTest, not swift-testing: the editor's runner parses the XCTest
// `--xunit-output` file, and swift-testing results do not reliably land there
// on Xcode 16.x / Swift 6.x. See README "## Testing" for the full rationale.
final class ModelTests: XCTestCase {
    // The production default is the empty, not-yet-connected day-one state, so a
    // fresh model with no seed shows the Connect hero rather than a zeroed dashboard.
    func testEmptyStateIsDisconnected() {
        let model = RunBuddyModel(today: .empty)
        XCTAssertFalse(model.today.healthKitConnected)
        XCTAssertEqual(model.today.goalSteps, 10000)
        XCTAssertEqual(model.goalProgress, 0)
    }

    // Goal progress is the steps/goal ratio, clamped to 1.0 even past the goal,
    // and `stepsRemaining` never goes negative — the ring and "to go" copy depend on this.
    func testGoalProgressClampsAndRemaining() {
        let partial = RunBuddyModel(today: TodayState(healthKitConnected: true, steps: 6420, goalSteps: 10000))
        XCTAssertEqual(partial.goalProgress, 0.642, accuracy: 0.0001)
        XCTAssertEqual(partial.stepsRemaining, 3580)
        XCTAssertFalse(partial.goalReached)

        let over = RunBuddyModel(today: TodayState(healthKitConnected: true, steps: 12500, goalSteps: 10000))
        XCTAssertEqual(over.goalProgress, 1.0)
        XCTAssertEqual(over.stepsRemaining, 0)
        XCTAssertTrue(over.goalReached)
    }

    // The seed contract: flat `rb*` preference keys (what a scenario's deviceState
    // writes at launch) are read back into a fully-populated TodayState, including
    // the coach group anchored by `rbCoachHeadline`.
    func testReadStateFromFlatDefaults() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests")!
        defaults.removePersistentDomain(forName: "runbuddy.tests")
        defaults.set(true, forKey: "rbConnected")
        defaults.set("2026-06-22", forKey: "rbDate")
        defaults.set(8200, forKey: "rbSteps")
        defaults.set(10000, forKey: "rbGoalSteps")
        defaults.set("cheering", forKey: "rbBuddyMood")
        defaults.set("Almost there", forKey: "rbCoachHeadline")
        defaults.set("A short walk seals the deal.", forKey: "rbCoachBody")
        defaults.set("walk", forKey: "rbCoachType")

        let state = RunBuddyModel.readState(defaults: defaults)
        XCTAssertTrue(state.healthKitConnected)
        XCTAssertEqual(state.steps, 8200)
        XCTAssertEqual(state.goalSteps, 10000)
        XCTAssertEqual(state.coach?.buddyMood, "cheering")
        XCTAssertEqual(state.coach?.headline, "Almost there")
        XCTAssertEqual(state.coach?.recommendationType, "walk")
        // No workout/load keys set => those groups stay absent.
        XCTAssertNil(state.latestWorkout)
        XCTAssertNil(state.weeklyLoad)
    }

    // With no keys seeded (production day one) the reader yields the empty,
    // disconnected state — goal defaults to 10k and the Connect hero shows.
    func testReadStateEmptyDefaultsToDisconnected() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests.empty")!
        defaults.removePersistentDomain(forName: "runbuddy.tests.empty")
        let state = RunBuddyModel.readState(defaults: defaults)
        XCTAssertFalse(state.healthKitConnected)
        XCTAssertEqual(state.goalSteps, 10000)
        XCTAssertNil(state.coach)
    }

    // Connecting Apple Health from the day-one hero flips the model into the dashboard.
    func testConnectFlipsState() {
        let model = RunBuddyModel(today: .empty)
        model.connect()
        XCTAssertTrue(model.today.healthKitConnected)
    }
}
