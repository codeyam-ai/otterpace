import XCTest
@testable import AppCore

// Covers the persistence-clobber fix (races + coach profile survive a HealthKit
// loadToday) and the web-import mapping (RaceDraft / RaceSearchResult -> RaceGoal).
//
// The fix can't be shown in the CodeYam preview: seeded scenarios deliberately
// skip the re-merge (they already carry races via readState), so the bug only
// ever reproduces on the real, non-seeded HealthKit path — which is exactly what
// these tests exercise with a raceless stub source.
final class RaceImportPersistenceTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "RaceImportPersistenceTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    /// A production-like source: authorized, and its snapshot carries NO races or
    /// profile (like the real HealthKitDataSource, which knows nothing about the
    /// on-device UserDefaults where they live).
    private struct RacelessSource: HealthDataSource {
        func authorizationState() -> HealthAuthState { .authorized }
        func requestAuthorization() async -> HealthAuthState { .authorized }
        func loadToday() async -> TodayState { TodayState(healthKitConnected: true, steps: 4200) }
    }

    private func race(_ name: String, _ date: String) -> RaceGoal {
        RaceGoal(name: name, distanceMiles: 13.1, date: date, location: "Bend")
    }

    // MARK: The bug: added races must survive connect() / refresh().

    func testConnectReMergesPersistedRaces() async {
        let d = freshDefaults()                       // no rb* keys → production (non-seeded)
        RaceStore.save([race("Cascade Half", "2026-09-06")], d)
        let model = await MainActor.run { OtterpaceModel(today: .empty, source: RacelessSource(), defaults: d) }

        await MainActor.run { model.connect() }
        // connect() runs an async Task; poll for it to settle.
        for _ in 0..<50 {
            let ok = await MainActor.run { model.today.races.count == 1 }
            if ok { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let races = await MainActor.run { model.today.races }
        XCTAssertEqual(races.map { $0.name }, ["Cascade Half"],
                       "connect() must re-merge on-device races onto the HealthKit snapshot")
    }

    func testRefreshKeepsRaceAddedThisSession() async {
        let d = freshDefaults()
        let model = await MainActor.run {
            let m = OtterpaceModel(today: TodayState(healthKitConnected: true, steps: 100), source: RacelessSource(), defaults: d)
            m.addRace(self.race("Summer 10K", "2026-06-27"))      // persists to RaceStore in `d`
            return m
        }
        // A pull-to-refresh reloads the HealthKit snapshot (raceless) — the added
        // race must NOT vanish. This is the exact "added a race, gone" repro.
        await model.refresh()
        let races = await MainActor.run { model.today.races }
        XCTAssertEqual(races.map { $0.name }, ["Summer 10K"])
    }

    func testConnectReMergesCoachProfile() async {
        let d = freshDefaults()
        CoachProfileStore.save(CoachProfile(walkVolume: .mostDays, walkTime: .mornings, otherTraining: [.strength]), d)
        let model = await MainActor.run { OtterpaceModel(today: .empty, source: RacelessSource(), defaults: d) }

        await MainActor.run { model.connect() }
        for _ in 0..<50 {
            let ok = await MainActor.run { model.today.profile != nil }
            if ok { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let profile = await MainActor.run { model.today.profile }
        XCTAssertEqual(profile?.walkVolume, .mostDays)
        XCTAssertEqual(profile?.otherTraining, [.strength])
    }

    // An empty on-device profile stays nil after a load (not an empty struct), so
    // existing no-profile captures/coaching are unaffected.
    func testReMergeLeavesProfileNilWhenNoneStored() async {
        let d = freshDefaults()
        let model = await MainActor.run { OtterpaceModel(today: .empty, source: RacelessSource(), defaults: d) }
        await MainActor.run { model.connect() }
        for _ in 0..<25 {
            let authed = await MainActor.run { model.healthAuth == .authorized }
            if authed { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let profile = await MainActor.run { model.today.profile }
        XCTAssertNil(profile)
    }

    // MARK: Import mapping — a partial draft opens the editor with sane defaults.

    func testRaceDraftSeedFillsDefaultsForMissingFields() {
        // A sparse import: only a name. Distance falls back to the Half preset so a
        // valid capsule is selected; name is kept; nothing is invented.
        let seed = RaceDraft(name: "Mystery Trail Run").asRaceGoalSeed
        XCTAssertEqual(seed.name, "Mystery Trail Run")
        XCTAssertEqual(seed.distanceMiles, RaceDistance.half.miles, accuracy: 0.001)
        XCTAssertEqual(seed.date, "")
        XCTAssertNil(seed.notes)
    }

    func testRaceDraftSeedPreservesKmUnitAndValues() {
        let draft = RaceDraft(name: "Berlin 10K", date: "2026-09-27",
                              distanceMiles: 6.2137, unit: .kilometers, location: "Berlin", notes: "flat")
        let seed = draft.asRaceGoalSeed
        XCTAssertEqual(seed.name, "Berlin 10K")
        XCTAssertEqual(seed.date, "2026-09-27")
        XCTAssertEqual(seed.unit, .kilometers)
        XCTAssertEqual(seed.location, "Berlin")
        XCTAssertEqual(seed.notes, "flat")
    }

    func testSearchResultMapsToDraft() {
        let result = RaceSearchResult(name: "Cascade Marathon", date: "2026-09-06",
                                      distanceMiles: 26.2, unit: .miles, location: "Seattle, WA",
                                      sourceUrl: "https://example.com/cascade")
        let draft = result.asDraft
        XCTAssertEqual(draft.name, "Cascade Marathon")
        XCTAssertEqual(draft.distanceMiles, 26.2)
        XCTAssertEqual(draft.location, "Seattle, WA")
        // A stable id for SwiftUI lists, derived from name+date+location.
        XCTAssertEqual(result.id, "Cascade Marathon|2026-09-06|Seattle, WA")
    }
}
