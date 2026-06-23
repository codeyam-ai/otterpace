import XCTest
import SwiftUI
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class DynamicTypeOverrideTests: XCTestCase {

    // An empty seed honors the system size (returns nil, no override).
    func testEmptyReturnsNil() {
        XCTAssertNil(dynamicTypeSize(forSeed: ""))
    }

    // An unrecognized value returns nil rather than a wrong size.
    func testUnknownReturnsNil() {
        XCTAssertNil(dynamicTypeSize(forSeed: "ginormous"))
    }

    // Accessibility aliases map to the matching accessibility sizes.
    func testAccessibilityAliases() {
        XCTAssertEqual(dynamicTypeSize(forSeed: "accessibility3"), .accessibility3)
        XCTAssertEqual(dynamicTypeSize(forSeed: "a5"), .accessibility5)
    }

    // Standard size aliases map to the matching standard sizes.
    func testStandardAliases() {
        XCTAssertEqual(dynamicTypeSize(forSeed: "xxxl"), .xxxLarge)
        XCTAssertEqual(dynamicTypeSize(forSeed: "large"), .large)
    }

    // Mapping is case-insensitive.
    func testCaseInsensitive() {
        XCTAssertEqual(dynamicTypeSize(forSeed: "XXL"), .xxLarge)
        XCTAssertEqual(dynamicTypeSize(forSeed: "Accessibility1"), .accessibility1)
    }

    // Every accessibility size maps to one flagged as an accessibility size.
    func testAccessibilitySizesAreAccessibility() {
        for raw in ["a1", "a2", "a3", "a4", "a5"] {
            XCTAssertEqual(dynamicTypeSize(forSeed: raw)?.isAccessibilitySize, true, "\(raw)")
        }
    }
}
