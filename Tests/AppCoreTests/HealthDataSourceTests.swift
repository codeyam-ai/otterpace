import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class HealthDataSourceTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "HealthDataSourceTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    // A launch with any rb* preference is treated as a seeded CodeYam scenario.
    func testScenarioSeededWhenRbKeyPresent() {
        let d = freshDefaults()
        d.set(true, forKey: "rbConnected")
        XCTAssertTrue(HealthSource.isScenarioSeeded(d))
    }

    // A launch with no rb* preferences is production (not seeded).
    func testNotSeededWhenNoRbKeys() {
        let d = freshDefaults()
        XCTAssertFalse(HealthSource.isScenarioSeeded(d))
    }

    // The seeded source reports authorized only once rbConnected is set.
    func testSeededAuthorizationReflectsConnected() {
        let d = freshDefaults()
        XCTAssertEqual(SeededHealthDataSource(defaults: d).authorizationState(), .notDetermined)
        d.set(true, forKey: "rbConnected")
        XCTAssertEqual(SeededHealthDataSource(defaults: d).authorizationState(), .authorized)
    }

    // Requesting authorization on the seeded source grants and marks connected.
    func testSeededRequestAuthorizationGrants() async {
        let d = freshDefaults()
        let state = await SeededHealthDataSource(defaults: d).requestAuthorization()
        XCTAssertEqual(state, .authorized)
        XCTAssertTrue(d.bool(forKey: "rbConnected"))
    }

    // The seeded source loads the seeded snapshot and marks it connected.
    func testSeededLoadTodayReturnsSeededState() async {
        let d = freshDefaults()
        d.set(7200, forKey: "rbSteps")
        d.set(10000, forKey: "rbGoalSteps")
        let state = await SeededHealthDataSource(defaults: d).loadToday()
        XCTAssertEqual(state.steps, 7200)
        XCTAssertTrue(state.healthKitConnected)
    }

    // A model built from a connected state reports authorized; an empty one does not.
    func testModelHealthAuthFromState() {
        XCTAssertEqual(OtterpaceModel(today: .empty).healthAuth, .notDetermined)
        let connected = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 100))
        XCTAssertEqual(connected.healthAuth, .authorized)
    }

    // connect() on a seeded source ends up authorized and loads the seeded steps.
    func testConnectWithSeededSourceAuthorizesAndLoads() async {
        let d = freshDefaults()
        d.set(5000, forKey: "rbSteps")
        let model = await MainActor.run { OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d)) }
        await MainActor.run { model.connect() }
        // connect() runs an async Task; poll briefly for the state to settle.
        for _ in 0..<50 {
            let done = await MainActor.run { model.healthAuth == .authorized && model.today.steps == 5000 }
            if done { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let authed = await MainActor.run { model.healthAuth }
        let steps = await MainActor.run { model.today.steps }
        XCTAssertEqual(authed, .authorized)
        XCTAssertEqual(steps, 5000)
    }
}
