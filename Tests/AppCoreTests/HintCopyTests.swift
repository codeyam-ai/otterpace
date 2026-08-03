import XCTest
@testable import AppCore

// The ⓘ explanations. Every topic must actually have copy: a hint that renders an
// empty caption is worse than no hint, because the user taps and gets nothing.
final class HintCopyTests: XCTestCase {

    func testEveryTopicHasTitleAndBody() {
        for topic in HintTopic.allCases {
            XCTAssertFalse(topic.title.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(topic.rawValue) has no title")
            XCTAssertFalse(topic.body.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(topic.rawValue) has no body")
        }
    }

    func testNoEmDashes() {
        for topic in HintTopic.allCases {
            XCTAssertFalse(topic.title.contains("—"), "\(topic.rawValue) title uses an em dash")
            XCTAssertFalse(topic.body.contains("—"), "\(topic.rawValue) body uses an em dash")
        }
    }

    /// The body should explain, not just restate the label.
    func testBodiesAreExplanatory() {
        for topic in HintTopic.allCases {
            XCTAssertGreaterThan(topic.body.count, 40,
                                 "\(topic.rawValue) body is too short to explain anything")
        }
    }

    func testTitlesAreDistinct() {
        let titles = HintTopic.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "two hint topics share a title")
    }

    func testBodiesAreDistinct() {
        let bodies = HintTopic.allCases.map(\.body)
        XCTAssertEqual(Set(bodies).count, bodies.count, "two hint topics share a body")
    }

    /// The three confusions that prompted this feature must each be answered.
    func testAnswersTheReportedConfusions() {
        XCTAssertTrue(HintTopic.buddyMood.body.contains("Ready"),
                      "The mood hint should explain what the default 'Ready' chip means.")
        XCTAssertTrue(HintTopic.activeMinutes.body.lowercased().contains("zero"),
                      "The active-minutes hint should explain why it starts at zero.")
        XCTAssertTrue(HintTopic.sinceMoving.body.lowercased().contains("last recorded"),
                      "The since-you-moved hint should say what it measures from.")
    }
}
