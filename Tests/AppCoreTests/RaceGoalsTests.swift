import XCTest
@testable import AppCore

// Pure-logic + persistence tests for race goals and the race-aware coaching
// branches. Deterministic against a fixed "today".
final class RaceGoalsTests: XCTestCase {

    private let today = "2026-06-24"

    private func race(_ name: String, _ date: String, miles: Double = 13.1) -> RaceGoal {
        RaceGoal(name: name, distanceMiles: miles, date: date, location: "Bend")
    }

    // MARK: helpers

    func testDaysUntil() {
        XCTAssertEqual(RaceGoal.daysUntil(date: "2026-07-01", asOf: today), 7)
        XCTAssertEqual(RaceGoal.daysUntil(date: "2026-06-24", asOf: today), 0)
        XCTAssertEqual(RaceGoal.daysUntil(date: "2026-06-20", asOf: today), -4)
        XCTAssertNil(RaceGoal.daysUntil(date: "not-a-date", asOf: today))
    }

    func testUpcomingAndNext() {
        let races = [race("Past", "2026-06-01"), race("Far", "2026-09-01"), race("Soon", "2026-06-29")]
        let upcoming = RaceGoal.upcoming(in: races, asOf: today)
        XCTAssertEqual(upcoming.map { $0.name }, ["Soon", "Far"])   // past excluded, soonest first
        XCTAssertEqual(RaceGoal.next(in: races, asOf: today)?.name, "Soon")
        XCTAssertNil(RaceGoal.next(in: [race("Past", "2026-06-01")], asOf: today))
    }

    func testHasUpcoming() {
        // The Today "add a race" banner gate: true only when a race is on/after today.
        XCTAssertFalse(RaceGoal.hasUpcoming(in: [], asOf: today))                              // no races
        XCTAssertFalse(RaceGoal.hasUpcoming(in: [race("Past", "2026-06-01")], asOf: today))    // past-only → banner returns
        XCTAssertTrue(RaceGoal.hasUpcoming(in: [race("Today", today)], asOf: today))           // race day counts
        XCTAssertTrue(RaceGoal.hasUpcoming(in: [race("Soon", "2026-06-29")], asOf: today))     // future
        XCTAssertTrue(RaceGoal.hasUpcoming(in: [race("Past", "2026-06-01"), race("Soon", "2026-06-29")], asOf: today))  // mixed
    }

    func testDistancePresetsAndClamp() {
        XCTAssertEqual(RaceDistance.preset(forMiles: 13.1), .half)
        XCTAssertEqual(RaceDistance.preset(forMiles: 26.2), .marathon)
        XCTAssertEqual(RaceDistance.preset(forMiles: 5.0), .custom)     // not a preset
        XCTAssertEqual(RaceDistance.clampMiles(0.2), RaceDistance.minMiles)
        XCTAssertEqual(RaceDistance.clampMiles(500), RaceDistance.maxMiles)
        XCTAssertEqual(RaceDistance.clampMiles(8.04), 8.0, accuracy: 0.001)  // rounded to .1
    }

    func testMilesFromUnit() {
        // km → miles at full precision (1 mi = 1.609344 km) so the km value round-trips.
        XCTAssertEqual(RaceDistance.miles(from: 5, unit: .kilometers), 5 / 1.609344, accuracy: 0.0001)  // 5K
        XCTAssertEqual(RaceDistance.miles(from: 15, unit: .kilometers), 15 / 1.609344, accuracy: 0.0001)
        // miles typed pass through, rounded to 0.1.
        XCTAssertEqual(RaceDistance.miles(from: 13.1, unit: .miles), 13.1, accuracy: 0.001)
        // clamp bounds apply regardless of unit.
        XCTAssertEqual(RaceDistance.miles(from: 0.1, unit: .miles), RaceDistance.minMiles)
        XCTAssertEqual(RaceDistance.miles(from: 500, unit: .kilometers), RaceDistance.maxMiles)
    }

    func testKmRaceRoundTripsInDisplay() {
        // A 15 km race stored as full-precision miles displays back as exactly "15 km".
        let miles = RaceDistance.miles(from: 15, unit: .kilometers)
        let race = RaceGoal(name: "Trail 15K", distanceMiles: miles, date: "2026-10-01", unit: .kilometers)
        XCTAssertTrue(race.displayDistance.hasPrefix("15 km"), race.displayDistance)
        XCTAssertTrue(race.displayDistance.contains("9.3 mi"), race.displayDistance)
        // A miles race leads with miles.
        let milesRace = RaceGoal(name: "Half", distanceMiles: 13.1, date: "2026-10-01", unit: .miles)
        XCTAssertTrue(milesRace.displayDistance.hasPrefix("13.1 mi"), milesRace.displayDistance)
    }

    // MARK: store

    func testStoreRoundTripsAndMutates() {
        let suite = "RaceGoalsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }

        XCTAssertTrue(RaceStore.load(d).isEmpty)
        let r = race("Trail Half", "2026-10-10")
        RaceStore.add(r, d)
        XCTAssertEqual(RaceStore.load(d).count, 1)

        var updated = r; updated.name = "Trail Half (renamed)"
        RaceStore.update(updated, d)
        XCTAssertEqual(RaceStore.load(d).first?.name, "Trail Half (renamed)")
        XCTAssertEqual(RaceStore.load(d).count, 1)   // updated in place, not appended

        RaceStore.remove(id: r.id, d)
        XCTAssertTrue(RaceStore.load(d).isEmpty)
    }

    func testReadStateDecodesSeededRaces() {
        let suite = "RaceGoalsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let json = String(data: try! JSONEncoder().encode([race("Trail Half", "2026-10-10")]), encoding: .utf8)!
        d.set(json, forKey: "rbRacesJSON")
        XCTAssertEqual(OtterpaceModel.readState(defaults: d).races.first?.name, "Trail Half")
    }

    // MARK: race-aware coaching

    private func stateWithRace(_ date: String, miles: Double = 13.1) -> TodayState {
        var s = TodayState(healthKitConnected: true, steps: 6000, goalSteps: 10000)
        s.races = [race("October Half", date, miles: miles)]
        return s
    }

    func testClassifyRaceIntent() {
        XCTAssertEqual(CoachIntent.classify("make me a plan for my marathon"), .raceGoal)
        XCTAssertEqual(CoachIntent.classify("how should I taper?"), .raceGoal)
        XCTAssertEqual(CoachIntent.classify("what's my race plan"), .raceGoal)
        // Step-goal wording still routes to hit10K, not race.
        XCTAssertEqual(CoachIntent.classify("how do I get to 10k steps?"), .hit10K)
    }

    func testRaceReplyPhases() {
        let taper = CoachEngine.reply(to: "race plan?", context: stateWithRace("2026-06-29"), asOf: today)
        XCTAssertEqual(taper.intent, .raceGoal)
        XCTAssertTrue(taper.text.lowercased().contains("taper"))

        let raceDay = CoachEngine.reply(to: "race plan?", context: stateWithRace("2026-06-24"), asOf: today)
        XCTAssertTrue(raceDay.text.lowercased().contains("race day"))

        let build = CoachEngine.reply(to: "race plan?", context: stateWithRace("2026-08-15"), asOf: today)
        XCTAssertTrue(build.text.contains("10%"))
    }

    func testGeneralReplyIsRaceAwareForFreshUser() {
        let r = CoachEngine.reply(to: "what should I do today?", context: stateWithRace("2026-06-29"), asOf: today)
        XCTAssertEqual(r.intent, .general)
        XCTAssertEqual(r.mood, .ready)
        XCTAssertTrue(r.text.lowercased().contains("taper"))
    }

    // MARK: race-aware weekly review

    func testWeeklyReviewFoldsInTaper() {
        var c = stateWithRace("2026-06-29")  // taper week
        c.weeklyLoad = WeeklyLoad(weeklyMileage: 18, daysRunThisWeek: 3, longestRunMiles: 7,
                                  restDaysThisWeek: 2, loadTrend: "steady")
        let review = WeeklyReviewEngine.generate(from: c, asOf: today)
        XCTAssertTrue(review.focusArea.lowercased().contains("taper"))
        XCTAssertTrue(review.nextWeek.contains("October Half"))
    }

    func testWeeklyReviewSpikingKeepsPrecedenceWithRace() {
        var c = stateWithRace("2026-06-29")
        c.weeklyLoad = WeeklyLoad(weeklyMileage: 40, daysRunThisWeek: 5, longestRunMiles: 14,
                                  restDaysThisWeek: 0, loadTrend: "spiking")
        let review = WeeklyReviewEngine.generate(from: c, asOf: today)
        XCTAssertTrue(review.safetyFlag)                              // spiking still wins
        XCTAssertTrue(review.nextWeek.lowercased().contains("ease off"))
    }
}
