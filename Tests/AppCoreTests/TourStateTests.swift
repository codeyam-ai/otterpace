import XCTest
@testable import AppCore

// The Today spotlight tour's launch gate and its scenario seeds.
//
// The gate matters because the tour draws a full-screen scrim: showing it at the
// wrong moment (over the Connect hero, or on a scenario capture that never asked
// for it) does not just look wrong, it hides the whole screen underneath.
final class TourStateTests: XCTestCase {

    /// A defaults instance isolated from the real app domain, so the gate's
    /// persistence can be exercised without leaking into other tests.
    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "TourStateTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    // MARK: Gating matrix

    func testShowsOnFirstRunWhenHealthConnected() {
        let d = freshDefaults()
        XCTAssertTrue(TourState.shouldShow(defaults: d, seeded: false, healthConnected: true))
    }

    func testDoesNotShowOnceSeen() {
        let d = freshDefaults()
        TourState.markSeen(d)
        XCTAssertFalse(TourState.shouldShow(defaults: d, seeded: false, healthConnected: true))
    }

    /// The tour points at the Buddy card, the stats row, and the coach card. None
    /// of those are on screen before Health is connected — `ConnectHero` is. So
    /// the tour must stay down until there is something to point at.
    func testDoesNotShowBeforeHealthIsConnected() {
        let d = freshDefaults()
        XCTAssertFalse(TourState.shouldShow(defaults: d, seeded: false, healthConnected: false))
    }

    /// Scenarios skip the tour by default, matching `OnboardingState.shouldShow`.
    /// Otherwise every seeded Today capture would render behind a scrim.
    func testDoesNotShowUnderAScenarioSeed() {
        let d = freshDefaults()
        XCTAssertFalse(TourState.shouldShow(defaults: d, seeded: true, healthConnected: true))
    }

    /// The opt-in that lets a tour scenario capture the overlay on purpose. It
    /// wins over every other suppression, including `hasSeen`.
    func testStartScreenTourForcesItEvenWhenSeenAndSeeded() {
        let d = freshDefaults()
        TourState.markSeen(d)
        XCTAssertTrue(TourState.shouldShow(defaults: d, seeded: true,
                                           startScreen: "tour", healthConnected: true))
    }

    func testClearSeenMakesItShowAgain() {
        let d = freshDefaults()
        TourState.markSeen(d)
        XCTAssertFalse(TourState.shouldShow(defaults: d, seeded: false, healthConnected: true))
        TourState.clearSeen(d)
        XCTAssertTrue(TourState.shouldShow(defaults: d, seeded: false, healthConnected: true))
    }

    // MARK: Step index

    func testStartStepDefaultsToZero() {
        XCTAssertEqual(TourState.startStep(freshDefaults()), 0)
    }

    func testStartStepReadsTheSeed() {
        let d = freshDefaults()
        d.set(2, forKey: "rbTourStep")
        XCTAssertEqual(TourState.startStep(d), 2)
    }

    func testStartStepClampsOutOfRangeSeeds() {
        let d = freshDefaults()
        d.set(99, forKey: "rbTourStep")
        XCTAssertEqual(TourState.startStep(d), TourState.stepCount - 1)

        d.set(-3, forKey: "rbTourStep")
        XCTAssertEqual(TourState.startStep(d), 0)
    }

    func testStepCountMatchesTheScript() {
        XCTAssertEqual(TourState.stepCount, TourStep.allCases.count)
        XCTAssertGreaterThan(TourState.stepCount, 0)
    }

    // MARK: Copy

    func testEveryStepHasCopy() {
        for step in TourStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step.rawValue) has no title")
            XCTAssertFalse(step.body.isEmpty, "\(step.rawValue) has no body")
            XCTAssertFalse(step.title.contains("—"), "\(step.rawValue) title uses an em dash")
            XCTAssertFalse(step.body.contains("—"), "\(step.rawValue) body uses an em dash")
        }
    }

    /// Only the last step commits; the rest continue.
    func testAdvanceTitleMarksTheFinalStep() {
        let steps = TourStep.allCases
        for step in steps.dropLast() {
            XCTAssertEqual(step.advanceTitle, "Next", "\(step.rawValue) should continue the tour")
        }
        XCTAssertEqual(steps[steps.count - 1].advanceTitle, "Got it")
    }

    // MARK: Scenario index guard
    //
    // Same failure mode `OnboardingScenarioIndexTests` guards against: a seeded
    // index silently pointing at a different step than the scenario's name claims.
    // A capture built from a drifted seed is "correct" in that it renders what the
    // seed asked for, so nothing else catches it.

    private static let expectedStep: [String: Int] = [
        "tour-step-1-buddy": 0,
        "tour-step-2-stats": 1,
        "tour-step-3-coach-card": 2,
    ]

    private var scenariosDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(".codeyam/scenarios")
    }

    private func preferences(_ slug: String) throws -> [String: Any]? {
        let url = scenariosDir.appendingPathComponent("\(slug).json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["deviceState"] as? [String: Any])?["preferences"] as? [String: Any]
    }

    func testSeededTourStepsMatchNamedSteps() throws {
        for (slug, expected) in Self.expectedStep {
            let seeded = try preferences(slug)?["rbTourStep"] as? Int
            XCTAssertEqual(seeded, expected,
                           "\(slug) seeds rbTourStep=\(seeded.map(String.init) ?? "nil") but is named for step \(expected). Its capture renders a different step than its name claims.")
        }
    }

    /// A tour scenario must also opt in, or the gate suppresses the overlay under
    /// the scenario seed and the capture comes back with no tour at all.
    func testTourScenariosOptInViaStartScreen() throws {
        for slug in Self.expectedStep.keys {
            let startScreen = try preferences(slug)?["rbStartScreen"] as? String
            XCTAssertEqual(startScreen, "tour",
                           "\(slug) must seed rbStartScreen=\"tour\"; without it the tour is suppressed under a scenario seed and the capture shows no overlay.")
        }
    }

    /// Every seeded step must be addressable, so a stale seed can't be silently
    /// clamped onto a neighbouring step by `startStep`.
    func testSeededStepsAreInRange() throws {
        for (slug, _) in Self.expectedStep {
            guard let step = try preferences(slug)?["rbTourStep"] as? Int else {
                XCTFail("\(slug) has no rbTourStep seed"); continue
            }
            XCTAssertTrue((0..<TourState.stepCount).contains(step),
                          "\(slug) seeds step \(step), outside 0..<\(TourState.stepCount) — startStep would clamp it to a different screen.")
        }
    }

    /// A new tour scenario must be registered here too, so it can't be added with
    /// an unchecked step index.
    func testEveryTourScenarioIsCovered() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: scenariosDir.path)
        let slugs = files
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .filter { $0.hasPrefix("tour-") }

        for slug in slugs {
            XCTAssertNotNil(Self.expectedStep[slug],
                            "Scenario \(slug) has no expected step index — add it to expectedStep so its seed is guarded against step-order drift.")
        }
    }
}
