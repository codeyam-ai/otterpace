import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class WeeklyReviewEngineTests: XCTestCase {

    // MARK: Helpers

    private func state(_ load: WeeklyLoad?, profile: CoachProfile? = nil) -> TodayState {
        var s = TodayState(healthKitConnected: true, steps: 6000, goalSteps: 10000)
        s.weeklyLoad = load
        s.profile = profile
        return s
    }

    // A walking-first user: shared a profile that lists walking with no other
    // training (the `walkingFocused` signal both engines key off).
    private func walkingProfile() -> CoachProfile {
        CoachProfile(walkVolume: .mostDays, walkTime: .mornings, otherTraining: [])
    }

    // A runner who also cross-trains — `otherTraining` is non-empty, so NOT
    // walking-focused, but the recap should acknowledge the cross-training.
    private func crossTrainingProfile() -> CoachProfile {
        CoachProfile(walkVolume: .someDays, walkTime: .evenings, otherTraining: [.strength, .mobility])
    }

    private func solidLoad(trend: String = "building") -> WeeklyLoad {
        WeeklyLoad(weeklyMileage: 22, daysRunThisWeek: 4, longestRunMiles: 8,
                   restDaysThisWeek: 2, loadTrend: trend)
    }

    private func spikingLoad() -> WeeklyLoad {
        WeeklyLoad(weeklyMileage: 31, daysRunThisWeek: 5, longestRunMiles: 11,
                   restDaysThisWeek: 0, loadTrend: "spiking")
    }

    private func sparseLoad() -> WeeklyLoad {
        WeeklyLoad(weeklyMileage: 3.5, daysRunThisWeek: 1, longestRunMiles: 3.5,
                   restDaysThisWeek: 5, loadTrend: "recovering")
    }

    // MARK: Empty

    // With no weekly load at all, the review is the encouraging first-week prompt.
    func testNoLoadIsEmptyReview() {
        let r = WeeklyReviewEngine.generate(from: state(nil))
        XCTAssertFalse(r.hasActivity)
        XCTAssertEqual(r.buddyMood, .ready)
        XCTAssertFalse(r.safetyFlag)
        XCTAssertFalse(r.focusArea.isEmpty)
    }

    // A load object with zero mileage and zero runs still counts as no activity.
    func testZeroActivityLoadIsEmptyReview() {
        let load = WeeklyLoad(weeklyMileage: 0, daysRunThisWeek: 0, longestRunMiles: 0,
                              restDaysThisWeek: 0, loadTrend: "")
        let r = WeeklyReviewEngine.generate(from: state(load))
        XCTAssertFalse(r.hasActivity)
    }

    // MARK: Spiking — safety

    // A spiking load is safety-flagged, concerned, and escalates real warning signs.
    func testSpikingIsSafetyFlagged() {
        let r = WeeklyReviewEngine.generate(from: state(spikingLoad()))
        XCTAssertTrue(r.hasActivity)
        XCTAssertTrue(r.safetyFlag)
        XCTAssertEqual(r.buddyMood, .concerned)
        XCTAssertTrue(r.trainingRisk.lowercased().contains("clinician"))
    }

    // Spiking wins even when several runs went in — load trend dominates.
    func testSpikingWinsOverHighRunCount() {
        var load = spikingLoad()
        load.daysRunThisWeek = 6
        let r = WeeklyReviewEngine.generate(from: state(load))
        XCTAssertTrue(r.safetyFlag)
        XCTAssertEqual(r.buddyMood, .concerned)
    }

    // MARK: Solid

    // A building week is celebratory and not safety-flagged.
    func testBuildingWeekIsCheeringAndUnflagged() {
        let r = WeeklyReviewEngine.generate(from: state(solidLoad(trend: "building")))
        XCTAssertTrue(r.hasActivity)
        XCTAssertEqual(r.buddyMood, .cheering)
        XCTAssertFalse(r.safetyFlag)
        XCTAssertFalse(r.wentWell.isEmpty)
        XCTAssertFalse(r.whatChanged.isEmpty)
    }

    // A steady week is also positive and unflagged, with steady-specific framing.
    func testSteadyWeekIsUnflagged() {
        let r = WeeklyReviewEngine.generate(from: state(solidLoad(trend: "steady")))
        XCTAssertEqual(r.buddyMood, .cheering)
        XCTAssertFalse(r.safetyFlag)
        XCTAssertTrue(r.whatChanged.lowercased().contains("steady"))
    }

    // MARK: Sparse

    // A single-run, mostly-rest week reads gently and is never safety-flagged.
    func testSparseWeekIsGentleAndUnflagged() {
        let r = WeeklyReviewEngine.generate(from: state(sparseLoad()))
        XCTAssertTrue(r.hasActivity)
        XCTAssertEqual(r.buddyMood, .ready)
        XCTAssertFalse(r.safetyFlag)
    }

    // A zero-run week that still logged mileage is treated as sparse, not empty.
    func testZeroRunsWithMileageIsSparse() {
        let load = WeeklyLoad(weeklyMileage: 2.0, daysRunThisWeek: 0, longestRunMiles: 0,
                              restDaysThisWeek: 6, loadTrend: "recovering")
        let r = WeeklyReviewEngine.generate(from: state(load))
        XCTAssertTrue(r.hasActivity)
        XCTAssertFalse(r.safetyFlag)
    }

    // MARK: Determinism

    // The same context always yields an identical review.
    func testDeterministic() {
        let s = state(spikingLoad())
        XCTAssertEqual(WeeklyReviewEngine.generate(from: s), WeeklyReviewEngine.generate(from: s))
    }

    // Every activity review fills all five sections plus a focus area.
    func testActivityReviewsFillAllSections() {
        for load in [solidLoad(), spikingLoad(), sparseLoad()] {
            let r = WeeklyReviewEngine.generate(from: state(load))
            XCTAssertFalse(r.headline.isEmpty)
            XCTAssertFalse(r.wentWell.isEmpty)
            XCTAssertFalse(r.whatChanged.isEmpty)
            XCTAssertFalse(r.trainingRisk.isEmpty)
            XCTAssertFalse(r.nextWeek.isEmpty)
            XCTAssertFalse(r.focusArea.isEmpty)
        }
    }

    // MARK: Personalization from the profile (additive framing only)

    // A walking-focused profile reframes the solid-week recap toward walks-as-
    // training — distinct from the generic no-profile copy, and naming walking.
    func testWalkingFocusedSolidReviewReframesCopy() {
        let baseline = WeeklyReviewEngine.generate(from: state(solidLoad()))
        let walking = WeeklyReviewEngine.generate(from: state(solidLoad(), profile: walkingProfile()))
        XCTAssertNotEqual(walking.wentWell, baseline.wentWell)
        XCTAssertTrue(walking.wentWell.lowercased().contains("walking"))
        // Classification, mood, and safety are unchanged — only the wording moves.
        XCTAssertEqual(walking.buddyMood, baseline.buddyMood)
        XCTAssertEqual(walking.safetyFlag, baseline.safetyFlag)
        XCTAssertEqual(walking.headline, baseline.headline)
    }

    // A walking-focused profile also reframes the sparse-week recap to speak of
    // movement sessions rather than runs.
    func testWalkingFocusedSparseReviewReframesCopy() {
        let baseline = WeeklyReviewEngine.generate(from: state(sparseLoad()))
        let walking = WeeklyReviewEngine.generate(from: state(sparseLoad(), profile: walkingProfile()))
        XCTAssertNotEqual(walking.wentWell, baseline.wentWell)
        XCTAssertTrue(walking.wentWell.lowercased().contains("session"))
        XCTAssertFalse(walking.safetyFlag)
    }

    // A runner who cross-trains gets the running-oriented "what went well" copy
    // (NOT the walking reframing) plus an acknowledgment of the cross-training.
    func testCrossTrainingSolidReviewAcknowledgesIt() {
        let baseline = WeeklyReviewEngine.generate(from: state(solidLoad()))
        let cross = WeeklyReviewEngine.generate(from: state(solidLoad(), profile: crossTrainingProfile()))
        // Not walking-focused → the run-oriented wentWell copy is preserved.
        XCTAssertEqual(cross.wentWell, baseline.wentWell)
        // The cross-training is named in the "what changed" section.
        XCTAssertNotEqual(cross.whatChanged, baseline.whatChanged)
        XCTAssertTrue(cross.whatChanged.lowercased().contains("strength"))
        XCTAssertTrue(cross.whatChanged.lowercased().contains("mobility"))
    }

    // Personalization must never soften the spiking-week safety copy — a
    // walking-focused profile yields a byte-identical spiking review.
    func testSpikingSafetyCopyUnchangedRegardlessOfProfile() {
        let plain = WeeklyReviewEngine.generate(from: state(spikingLoad()))
        let withProfile = WeeklyReviewEngine.generate(from: state(spikingLoad(), profile: walkingProfile()))
        XCTAssertEqual(withProfile, plain)
        XCTAssertTrue(withProfile.safetyFlag)
    }

    // An empty (all-skipped) profile is a no-op: the recap is identical to the
    // no-profile baseline, so existing captures/scenarios are unaffected.
    func testEmptyProfileLeavesReviewUnchanged() {
        let baseline = WeeklyReviewEngine.generate(from: state(solidLoad()))
        let empty = WeeklyReviewEngine.generate(from: state(solidLoad(), profile: CoachProfile()))
        XCTAssertEqual(empty, baseline)
    }

    // A profile-bearing context is still fully deterministic.
    func testDeterministicWithProfile() {
        let s = state(solidLoad(), profile: walkingProfile())
        XCTAssertEqual(WeeklyReviewEngine.generate(from: s), WeeklyReviewEngine.generate(from: s))
    }
}
