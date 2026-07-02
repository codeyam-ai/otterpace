import XCTest
@testable import AppCore

// Pure-logic tests for the onboarding personalization profile: its Codable
// round-trip and the UserDefaults-backed store (mirroring RaceGoalsTests /
// OnboardingStateTests, against an injected suite).
final class CoachProfileTests: XCTestCase {

    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "CoachProfileTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // A brand-new / never-stored profile loads as the empty default (all nil / []).
    func testDefaultIsEmpty() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        let loaded = CoachProfileStore.load(d)
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertNil(loaded.walkVolume)
        XCTAssertNil(loaded.walkTime)
        XCTAssertTrue(loaded.otherTraining.isEmpty)
    }

    // A fully-filled profile survives save -> load unchanged.
    func testFullRoundTrip() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        let profile = CoachProfile(walkVolume: .mostDays, walkTime: .mornings,
                                   otherTraining: [.running, .strength])
        CoachProfileStore.save(profile, d)
        XCTAssertEqual(CoachProfileStore.load(d), profile)
        XCTAssertFalse(profile.isEmpty)
    }

    // A partially-filled profile (a skipped question => nil) round-trips too, and
    // is still considered non-empty because something was shared.
    func testPartialRoundTrip() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        let profile = CoachProfile(walkVolume: .daily, walkTime: nil, otherTraining: [])
        CoachProfileStore.save(profile, d)
        let loaded = CoachProfileStore.load(d)
        XCTAssertEqual(loaded, profile)
        XCTAssertEqual(loaded.walkVolume, .daily)
        XCTAssertNil(loaded.walkTime)
        XCTAssertFalse(loaded.isEmpty)
    }

    // clear() removes the stored profile so a subsequent load is empty again.
    func testClear() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        CoachProfileStore.save(CoachProfile(walkVolume: .someDays), d)
        XCTAssertFalse(CoachProfileStore.load(d).isEmpty)
        CoachProfileStore.clear(d)
        XCTAssertTrue(CoachProfileStore.load(d).isEmpty)
    }

    // An all-nil profile is empty; any single field makes it non-empty. This is
    // the predicate the model uses to keep an all-skipped profile off TodayState.
    func testIsEmptyPredicate() {
        XCTAssertTrue(CoachProfile().isEmpty)
        XCTAssertFalse(CoachProfile(walkVolume: .rarely).isEmpty)
        XCTAssertFalse(CoachProfile(walkTime: .varies).isEmpty)
        XCTAssertFalse(CoachProfile(otherTraining: [.cycling]).isEmpty)
    }

    // Encoded JSON uses the enum raw values and omits skipped (nil) fields, which
    // is the shape the coach backend (api/coach.ts) reasons over.
    func testEncodesRawValuesAndOmitsNil() throws {
        let profile = CoachProfile(walkVolume: .mostDays, walkTime: nil,
                                   otherTraining: [.running])
        let data = try JSONEncoder().encode(profile)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"mostDays\""))
        XCTAssertTrue(json.contains("\"running\""))
        // walkTime was skipped, so it should not appear in the payload.
        XCTAssertFalse(json.contains("walkTime"))
    }
}
