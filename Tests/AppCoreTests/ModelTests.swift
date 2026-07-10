import XCTest
@testable import AppCore

// XCTest, not swift-testing: the editor's runner parses the XCTest
// `--xunit-output` file, and swift-testing results do not reliably land there
// on Xcode 16.x / Swift 6.x. See README "## Testing" for the full rationale.
final class ModelTests: XCTestCase {
    // The production default is the empty, not-yet-connected day-one state, so a
    // fresh model with no seed shows the Connect hero rather than a zeroed dashboard.
    func testEmptyStateIsDisconnected() {
        let model = OtterpaceModel(today: .empty)
        XCTAssertFalse(model.today.healthKitConnected)
        XCTAssertEqual(model.today.goalSteps, 10000)
        XCTAssertEqual(model.goalProgress, 0)
    }

    // Goal progress is the steps/goal ratio, clamped to 1.0 even past the goal,
    // and `stepsRemaining` never goes negative — the ring and "to go" copy depend on this.
    func testGoalProgressClampsAndRemaining() {
        let partial = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 6420, goalSteps: 10000))
        XCTAssertEqual(partial.goalProgress, 0.642, accuracy: 0.0001)
        XCTAssertEqual(partial.stepsRemaining, 3580)
        XCTAssertFalse(partial.goalReached)

        let over = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 12500, goalSteps: 10000))
        XCTAssertEqual(over.goalProgress, 1.0)
        XCTAssertEqual(over.stepsRemaining, 0)
        XCTAssertTrue(over.goalReached)
    }

    // goalExceeded distinguishes "past the goal" from merely meeting it, so the
    // ring can swap "goal hit!" for the celebratory "Goal crushed!".
    func testGoalExceededOnlyWhenPastGoal() {
        // Below the goal: neither reached nor exceeded.
        let under = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 6420, goalSteps: 10000))
        XCTAssertFalse(under.goalReached)
        XCTAssertFalse(under.goalExceeded)

        // Exactly at the goal: reached but NOT exceeded.
        let exact = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 10000, goalSteps: 10000))
        XCTAssertTrue(exact.goalReached)
        XCTAssertFalse(exact.goalExceeded)

        // Past the goal: both reached and exceeded.
        let over = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 14200, goalSteps: 10000))
        XCTAssertTrue(over.goalReached)
        XCTAssertTrue(over.goalExceeded)

        // A zero goal can never be exceeded (guards against divide-by-zero framing).
        let zeroGoal = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 500, goalSteps: 0))
        XCTAssertFalse(zeroGoal.goalExceeded)
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

        let state = OtterpaceModel.readState(defaults: defaults)
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

    // A legacy scenario snapshot (encoded before `profile` existed) still decodes:
    // the optional field defaults to nil, so old scenario JSON and the Codable
    // contract are unaffected by the new personalization field.
    func testTodayStateDecodesLegacyJSONWithoutProfile() throws {
        let legacy = """
        {"healthKitConnected":true,"date":"2026-06-22","steps":8200,"goalSteps":10000,
         "activeMinutes":30,"distanceMiles":3.4,"activeEnergyKcal":210,
         "minutesSinceLastMovement":40,"workouts":[],"races":[]}
        """
        let state = try JSONDecoder().decode(TodayState.self, from: Data(legacy.utf8))
        XCTAssertEqual(state.steps, 8200)
        XCTAssertNil(state.profile)
    }

    // The onboarding personalization profile seeds into TodayState via
    // `rbCoachProfileJSON` (JSON under one key), mirroring how races seed. An
    // all-empty profile stays absent.
    func testReadStateDecodesSeededProfile() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests.profile")!
        defaults.removePersistentDomain(forName: "runbuddy.tests.profile")
        defaults.set(true, forKey: "rbConnected")
        defaults.set(#"{"walkVolume":"mostDays","walkTime":"mornings","otherTraining":["running"]}"#,
                     forKey: "rbCoachProfileJSON")

        let state = OtterpaceModel.readState(defaults: defaults)
        XCTAssertEqual(state.profile?.walkVolume, .mostDays)
        XCTAssertEqual(state.profile?.walkTime, .mornings)
        XCTAssertEqual(state.profile?.otherTraining, [.running])

        // An empty profile blob leaves TodayState.profile nil (back-compat).
        defaults.set(#"{"otherTraining":[]}"#, forKey: "rbCoachProfileJSON")
        XCTAssertNil(OtterpaceModel.readState(defaults: defaults).profile)
    }

    // The declared training phase seeds through rbCoachProfileJSON alongside the
    // other fields, so it reaches the coach context from launch.
    func testReadStateDecodesSeededTrainingPhase() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests.phase")!
        defaults.removePersistentDomain(forName: "runbuddy.tests.phase")
        defaults.set(true, forKey: "rbConnected")
        defaults.set(#"{"otherTraining":[],"trainingPhase":"building"}"#, forKey: "rbCoachProfileJSON")
        XCTAssertEqual(OtterpaceModel.readState(defaults: defaults).profile?.trainingPhase, .building)
    }

    // An explicit rbLoadHistoryJSON seeds the coach-facing weekly series verbatim,
    // newest week first.
    func testReadStateDecodesSeededLoadHistory() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests.loadhist")!
        defaults.removePersistentDomain(forName: "runbuddy.tests.loadhist")
        defaults.set(true, forKey: "rbConnected")
        defaults.set(#"[{"weekStartISO":"2026-06-22","miles":22.0,"daysRun":4},{"weekStartISO":"2026-06-15","miles":20.0,"daysRun":4}]"#,
                     forKey: "rbLoadHistoryJSON")
        let state = OtterpaceModel.readState(defaults: defaults)
        XCTAssertEqual(state.loadHistory.count, 2)
        XCTAssertEqual(state.loadHistory.first?.weekStartISO, "2026-06-22")
        XCTAssertEqual(state.loadHistory.first?.miles ?? 0, 22.0, accuracy: 0.001)
    }

    // With no explicit series but a seeded workout list, loadHistory is DERIVED
    // from the workouts, so a rich multi-week scenario gets a real trajectory.
    func testReadStateDerivesLoadHistoryFromWorkouts() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests.loadhist.derive")!
        defaults.removePersistentDomain(forName: "runbuddy.tests.loadhist.derive")
        defaults.set(true, forKey: "rbConnected")
        defaults.set(#"[{"type":"run","distanceMiles":5.0,"durationMinutes":50,"pace":"10:00/mi","date":"2026-06-22","source":"strava"},{"type":"run","distanceMiles":6.0,"durationMinutes":60,"pace":"10:00/mi","date":"2026-06-15","source":"strava"}]"#,
                     forKey: "rbWorkoutsJSON")
        XCTAssertEqual(OtterpaceModel.readState(defaults: defaults).loadHistory.count, 2)
    }

    // With neither key seeded, loadHistory is empty (not shared with the coach).
    func testReadStateLoadHistoryEmptyWhenUnseeded() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests.loadhist.empty")!
        defaults.removePersistentDomain(forName: "runbuddy.tests.loadhist.empty")
        XCTAssertTrue(OtterpaceModel.readState(defaults: defaults).loadHistory.isEmpty)
    }

    // A TodayState JSON written before loadHistory existed still decodes, with the
    // series defaulting to empty (tolerant decode).
    func testTodayStateDecodesLegacyJSONWithoutLoadHistory() throws {
        let legacy = """
        {"healthKitConnected":true,"date":"2026-06-22","steps":8200,"goalSteps":10000,
         "activeMinutes":30,"distanceMiles":3.4,"activeEnergyKcal":210,
         "minutesSinceLastMovement":40,"workouts":[],"races":[]}
        """
        let state = try JSONDecoder().decode(TodayState.self, from: Data(legacy.utf8))
        XCTAssertTrue(state.loadHistory.isEmpty)
        XCTAssertEqual(state.steps, 8200)
    }

    // With no keys seeded (production day one) the reader yields the empty,
    // disconnected state — goal defaults to 10k and the Connect hero shows.
    func testReadStateEmptyDefaultsToDisconnected() {
        let defaults = UserDefaults(suiteName: "runbuddy.tests.empty")!
        defaults.removePersistentDomain(forName: "runbuddy.tests.empty")
        let state = OtterpaceModel.readState(defaults: defaults)
        XCTAssertFalse(state.healthKitConnected)
        XCTAssertEqual(state.goalSteps, 10000)
        XCTAssertNil(state.coach)
    }

    // Connecting Apple Health from the day-one hero authorizes and loads the
    // dashboard. connect() requests authorization asynchronously (default seeded
    // source grants), so poll briefly for the state to settle.
    func testConnectFlipsState() async {
        let d = UserDefaults(suiteName: "ModelTests.\(UUID().uuidString)")!
        let model = await MainActor.run { OtterpaceModel(today: .empty, source: SeededHealthDataSource(defaults: d)) }
        await MainActor.run { model.connect() }
        for _ in 0..<50 {
            if await MainActor.run(body: { model.today.healthKitConnected }) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let connected = await MainActor.run { model.today.healthKitConnected }
        XCTAssertTrue(connected)
    }

    // Setting the daily step goal applies it to the dashboard immediately.
    @MainActor func testSetGoalStepsApplies() {
        let model = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 5000, goalSteps: 10000))
        model.setGoalSteps(12000)
        XCTAssertEqual(model.today.goalSteps, 12000)
        XCTAssertEqual(UserPreferences.goalSteps(), 12000)
    }

    // UserPreferences falls back to the default goal when nothing is set.
    func testGoalDefaults() {
        let d = UserDefaults(suiteName: "ModelTests.goal.\(UUID().uuidString)")!
        XCTAssertEqual(UserPreferences.goalSteps(d), UserPreferences.defaultGoal)
        UserPreferences.setGoalSteps(8000, d)
        XCTAssertEqual(UserPreferences.goalSteps(d), 8000)
    }

    // clampGoal pins out-of-range values to the bounds and rounds to the increment.
    func testClampGoalBoundsAndRounding() {
        XCTAssertEqual(UserPreferences.clampGoal(200), UserPreferences.minGoal)   // below min
        XCTAssertEqual(UserPreferences.clampGoal(99999), UserPreferences.maxGoal) // above max
        XCTAssertEqual(UserPreferences.clampGoal(9740), 9500) // rounds down to nearest 500
        XCTAssertEqual(UserPreferences.clampGoal(9300), 9500) // rounds up to nearest 500
        XCTAssertEqual(UserPreferences.clampGoal(9800), 10000) // rounds up to nearest 500
    }

    // isPreset distinguishes the quick presets from custom values.
    func testIsPresetMatchesOptions() {
        XCTAssertTrue(UserPreferences.isPreset(10000))
        XCTAssertFalse(UserPreferences.isPreset(9500))
    }

    // A non-preset custom goal persists and applies just like a preset.
    @MainActor func testSetCustomGoalPersistsAndApplies() {
        let model = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 5000, goalSteps: 10000))
        model.setGoalSteps(9500)
        XCTAssertEqual(model.today.goalSteps, 9500)
        XCTAssertEqual(UserPreferences.goalSteps(), 9500)
    }

    // MARK: Strava ingest → weekly load

    // Today's date in the same UTC yyyy-MM-dd form `ActivityHistory` groups by, so
    // an ingested workout lands in the current week regardless of when this runs.
    private func todayISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    // Importing Strava runs rolls them up into the weekly load, so a Strava-only
    // user gets a real recap instead of the empty "first week" prompt.
    @MainActor func testIngestStravaWorkoutsPopulatesWeeklyLoad() {
        let model = OtterpaceModel(today: .empty)
        XCTAssertNil(model.today.weeklyLoad)
        let runs = [
            LatestWorkout(type: "run", distanceMiles: 4.2, durationMinutes: 43,
                          pace: "10:15/mi", date: todayISO(), source: "strava"),
        ]
        model.ingestStravaWorkouts(runs)

        let load = model.today.weeklyLoad
        XCTAssertNotNil(load)
        XCTAssertGreaterThan(load?.weeklyMileage ?? 0, 0)
        XCTAssertGreaterThanOrEqual(load?.daysRunThisWeek ?? 0, 1)
        // The generated Weekly Review is no longer the empty first-week prompt.
        XCTAssertTrue(WeeklyReviewEngine.generate(from: model.today).hasActivity)
    }

    // Ingesting an empty workout list is a no-op — no weekly load is fabricated.
    @MainActor func testIngestEmptyWorkoutsLeavesWeeklyLoadNil() {
        let model = OtterpaceModel(today: .empty)
        model.ingestStravaWorkouts([])
        XCTAssertNil(model.today.weeklyLoad)
    }

    // Importing Strava runs also populates the multi-week loadHistory series the
    // coaches reason from, not just the single weekly-load flag.
    @MainActor func testIngestStravaWorkoutsPopulatesLoadHistory() {
        let model = OtterpaceModel(today: .empty)
        XCTAssertTrue(model.today.loadHistory.isEmpty)
        model.ingestStravaWorkouts([
            LatestWorkout(type: "run", distanceMiles: 4.2, durationMinutes: 43,
                          pace: "10:15/mi", date: todayISO(), source: "strava"),
        ])
        XCTAssertFalse(model.today.loadHistory.isEmpty)
    }

    // MARK: Training phase mutator

    // Setting the phase persists it through CoachProfileStore and applies it to the
    // dashboard immediately; clearing with nil removes it.
    @MainActor func testSetTrainingPhasePersistsAndApplies() {
        let d = UserDefaults(suiteName: "ModelTests.phase.\(UUID().uuidString)")!
        let model = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 5000, goalSteps: 10000), defaults: d)
        model.setTrainingPhase(.building)
        XCTAssertEqual(model.today.profile?.trainingPhase, .building)
        XCTAssertEqual(CoachProfileStore.load(d).trainingPhase, .building)

        model.setTrainingPhase(nil)
        XCTAssertNil(model.today.profile?.trainingPhase)
    }

    // Setting the phase preserves the profile's other fields (walk habits, other
    // training) rather than clobbering them.
    @MainActor func testSetTrainingPhasePreservesOtherProfileFields() {
        let d = UserDefaults(suiteName: "ModelTests.phase2.\(UUID().uuidString)")!
        var today = TodayState(healthKitConnected: true, steps: 5000, goalSteps: 10000)
        today.profile = CoachProfile(walkVolume: .mostDays, otherTraining: [.running])
        let model = OtterpaceModel(today: today, defaults: d)
        model.setTrainingPhase(.recovering)
        XCTAssertEqual(model.today.profile?.walkVolume, .mostDays)
        XCTAssertEqual(model.today.profile?.otherTraining, [.running])
        XCTAssertEqual(model.today.profile?.trainingPhase, .recovering)
    }
}
