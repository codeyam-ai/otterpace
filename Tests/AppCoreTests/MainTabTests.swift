import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class MainTabTests: XCTestCase {

    // A known raw string maps to the matching tab, case-insensitively.
    func testInitFromKnownRaw() {
        XCTAssertEqual(MainTab(raw: "coach"), .coach)
        XCTAssertEqual(MainTab(raw: "COACH"), .coach)
        XCTAssertEqual(MainTab(raw: "today"), .today)
    }

    // An unknown or empty raw string falls back to today, the default landing tab.
    func testInitUnknownFallsBackToToday() {
        XCTAssertEqual(MainTab(raw: "banana"), .today)
        XCTAssertEqual(MainTab(raw: ""), .today)
    }
}
