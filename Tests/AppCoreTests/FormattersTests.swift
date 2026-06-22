import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class FormattersTests: XCTestCase {

    // formatted groups thousands with separators for readable step counts.
    func testFormattedGroupsThousands() {
        XCTAssertEqual(formatted(11240), "11,240")
        XCTAssertEqual(formatted(10000), "10,000")
        XCTAssertEqual(formatted(1234567), "1,234,567")
    }

    // formatted leaves small numbers and zero untouched.
    func testFormattedSmallNumbers() {
        XCTAssertEqual(formatted(0), "0")
        XCTAssertEqual(formatted(42), "42")
        XCTAssertEqual(formatted(999), "999")
    }

    // movementLabel reads "now" at or below zero minutes since moving.
    func testMovementLabelNow() {
        XCTAssertEqual(movementLabel(0), "now")
        XCTAssertEqual(movementLabel(-5), "now")
    }

    // movementLabel uses bare minutes under an hour.
    func testMovementLabelMinutes() {
        XCTAssertEqual(movementLabel(1), "1m")
        XCTAssertEqual(movementLabel(45), "45m")
        XCTAssertEqual(movementLabel(59), "59m")
    }

    // movementLabel rolls into hours, dropping the minutes part when it is zero.
    func testMovementLabelHours() {
        XCTAssertEqual(movementLabel(60), "1h")
        XCTAssertEqual(movementLabel(92), "1h32m")
        XCTAssertEqual(movementLabel(125), "2h5m")
    }

    // prettyDate turns a valid ISO date into a short weekday-and-day label.
    func testPrettyDateValid() {
        XCTAssertEqual(prettyDate("2026-06-22"), "Mon, Jun 22")
        XCTAssertEqual(prettyDate("2026-01-01"), "Thu, Jan 1")
    }

    // prettyDate returns the input unchanged when it is not a valid ISO date.
    func testPrettyDateInvalidFallsThrough() {
        XCTAssertEqual(prettyDate(""), "")
        XCTAssertEqual(prettyDate("not-a-date"), "not-a-date")
    }
}
