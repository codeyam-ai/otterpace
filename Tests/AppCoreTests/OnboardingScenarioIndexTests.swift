import XCTest
@testable import AppCore

// Guards the onboarding/welcome scenario page indices against silent drift.
//
// Inserting a personalization step — as the five-theme "choose your look" commit
// did — shifts every later step's index by one. Scenario seeds that pin
// `rbOnboardingPage` keep pointing at their OLD index and silently begin
// capturing a DIFFERENT screen: a scenario named "walking habits" renders the
// step-goal page instead.
//
// Nothing else catches this. Screenshot freshness compares code against capture
// time, and the capture itself is "correct" in that it faithfully renders what
// the seed asked for — so a recapture happily overwrites a right screenshot with
// a wrong one and every check still passes. The only durable guard is asserting
// the seeded index against the step order itself, which is what this file does.
final class OnboardingScenarioIndexTests: XCTestCase {

    /// Which step index each scenario is NAMED for. Intro carousel pages are
    /// 0..<introPageCount; personalization steps follow in the order documented
    /// on `OnboardingState.personalizationStepCount` (choose your look, set goal,
    /// walking habits, other training, training phase, add AI coaching).
    private static let expectedPage: [String: Int] = [
        // intro carousel
        "welcome-meet-buddy": 0,
        "welcome-day-by-day-coaching": 1,
        "welcome-ask-me-anything": 2,
        "welcome-large-text": 2,
        // personalization steps
        "onboarding-choose-your-look": 3,
        "onboarding-choose-your-look-otter": 3,
        "onboarding-choose-your-look-orbit": 3,
        "onboarding-choose-your-look-fieldnote": 3,
        "onboarding-choose-your-look-garden": 3,
        "onboarding-set-goal-8k": 4,
        "onboarding-walking-habits": 5,
        "onboarding-other-training": 6,
        "onboarding-training-phase": 7,
        "onboarding-add-ai-coaching-skip": 8,
        "onboarding-ai-coaching-connected": 8,
    ]

    private var scenariosDir: URL {
        // Tests/AppCoreTests/<this file> -> repo root -> .codeyam/scenarios
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(".codeyam/scenarios")
    }

    private func seededPage(_ slug: String) throws -> Int? {
        let url = scenariosDir.appendingPathComponent("\(slug).json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let prefs = (json?["deviceState"] as? [String: Any])?["preferences"] as? [String: Any]
        return prefs?["rbOnboardingPage"] as? Int
    }

    /// The step order is what the scenario indices are pinned against. If a step
    /// is added or removed, every index at or after it shifts and the seeds in
    /// `expectedPage` (plus the scenario JSON they mirror) must be updated in the
    /// same change — otherwise captures silently drift onto the wrong screens.
    func testStepCountsAreUnchanged() {
        XCTAssertEqual(OnboardingState.introPageCount, 3,
                       "Intro carousel length changed — update welcome-* scenario rbOnboardingPage seeds and expectedPage.")
        XCTAssertEqual(OnboardingState.personalizationStepCount, 6,
                       "A personalization step was added or removed — every later step index shifts. Update the onboarding-* scenario rbOnboardingPage seeds and expectedPage.")
    }

    /// Every scenario's seeded page must match the step it is named for.
    func testSeededPagesMatchNamedSteps() throws {
        for (slug, expected) in Self.expectedPage {
            let actual = try seededPage(slug)
            XCTAssertEqual(actual, expected,
                           "\(slug) seeds rbOnboardingPage=\(actual.map(String.init) ?? "nil") but is named for step \(expected). Its capture renders a different screen than its name claims.")
        }
    }

    /// Every seeded page must be addressable, so a stale seed can't be silently
    /// clamped onto a neighbouring screen by `startPage`.
    func testSeededPagesAreInRange() throws {
        for (slug, _) in Self.expectedPage {
            guard let page = try seededPage(slug) else {
                XCTFail("\(slug) has no rbOnboardingPage seed"); continue
            }
            XCTAssertTrue((0..<OnboardingState.stepCount).contains(page),
                          "\(slug) seeds page \(page), outside 0..<\(OnboardingState.stepCount) — startPage would clamp it to a different screen.")
        }
    }

    /// A new onboarding/welcome scenario must be registered here too, so it can't
    /// be added with an unchecked page index.
    func testEveryOnboardingScenarioIsCovered() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: scenariosDir.path)
        let slugs = files
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .filter { $0.hasPrefix("onboarding-") || $0.hasPrefix("welcome-") }

        for slug in slugs {
            XCTAssertNotNil(Self.expectedPage[slug],
                            "Scenario \(slug) has no expected page index — add it to expectedPage so its seed is guarded against step-order drift.")
        }
    }
}
