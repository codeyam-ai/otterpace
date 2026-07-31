import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
//
// The "Get an API key" chooser renders one row per provider via
// `if let url = provider.consoleURL`. A nil URL therefore does not fail loudly —
// it silently drops that provider from the list, which is EXACTLY the bug the
// chooser exists to fix (OpenAI and Gemini being unreachable). These tests make
// that failure mode impossible to reintroduce without a red test.
final class CoachProviderConsoleTests: XCTestCase {

    // Every provider must have a console URL, or it vanishes from the chooser.
    func testEveryProviderHasAConsoleURL() {
        for provider in CoachProvider.allCases {
            XCTAssertNotNil(provider.consoleURL,
                            "\(provider.displayName) has no consoleURL, so it would silently disappear from the Get an API key chooser")
        }
    }

    // The chooser offers all three providers — the whole point of the change.
    func testDisplayOrderCoversEveryProvider() {
        XCTAssertEqual(Set(CoachProvider.displayOrder), Set(CoachProvider.allCases))
        XCTAssertEqual(CoachProvider.displayOrder.count, 3)
    }

    // Anthropic leads: it is the provider Otterpace shipped with, so it stays
    // first even though the chooser no longer defaults to it.
    func testAnthropicLeadsTheDisplayOrder() {
        XCTAssertEqual(CoachProvider.displayOrder.first, .anthropic)
    }

    // Each console URL points at that provider's own host over HTTPS — a link
    // sending someone to the wrong vendor's console is worse than no link.
    func testConsoleURLsPointAtTheRightHost() {
        let expected: [CoachProvider: String] = [
            .anthropic: "console.anthropic.com",
            .openai: "platform.openai.com",
            .gemini: "aistudio.google.com",
        ]
        for (provider, host) in expected {
            let url = provider.consoleURL
            XCTAssertEqual(url?.host, host, "\(provider.displayName) console URL host")
            XCTAssertEqual(url?.scheme, "https", "\(provider.displayName) console URL scheme")
        }
    }

    // The chooser labels rows with displayName alone, so those must be distinct —
    // two rows reading the same thing would be unpickable.
    func testDisplayNamesAreDistinct() {
        let names = CoachProvider.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count, "provider display names must be unique: \(names)")
    }
}
