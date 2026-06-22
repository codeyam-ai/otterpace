import XCTest
import SwiftUI
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class BuddyMoodTests: XCTestCase {

    // A known raw string maps to the matching mood case, case-insensitively.
    func testInitFromKnownRaw() {
        XCTAssertEqual(BuddyMood(raw: "celebrating"), .celebrating)
        XCTAssertEqual(BuddyMood(raw: "CONCERNED"), .concerned)
        XCTAssertEqual(BuddyMood(raw: "Recovery"), .recovery)
    }

    // An unknown or empty raw string falls back to the friendly default, ready.
    func testInitUnknownFallsBackToReady() {
        XCTAssertEqual(BuddyMood(raw: "banana"), .ready)
        XCTAssertEqual(BuddyMood(raw: ""), .ready)
    }

    // Every mood exposes a non-empty caption used by the mood chip.
    func testEveryMoodHasCaption() {
        for mood in BuddyMood.allCases {
            XCTAssertFalse(mood.caption.isEmpty, "\(mood) should have a caption")
        }
    }

    // Caution-leaning moods carry distinct accent colors from the upbeat default.
    func testAccentsDifferentiateMoods() {
        XCTAssertEqual(BuddyMood.concerned.accent, Palette.amber)
        XCTAssertEqual(BuddyMood.recovery.accent, Palette.lilac)
        XCTAssertNotEqual(BuddyMood.concerned.accent, BuddyMood.celebrating.accent)
    }
}
