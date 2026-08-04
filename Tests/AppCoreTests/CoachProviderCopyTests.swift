import XCTest
@testable import AppCore

// The user-facing copy that names a provider.
//
// Regression: every surface outside Settings and onboarding hardcoded "Anthropic"
// long after OpenAI and Gemini worked, so the race sheets told users their OpenAI
// key would not work there — which was never true. These pin the copy to the enum
// so it cannot drift out of sync with the providers that actually ship.
final class CoachProviderCopyTests: XCTestCase {

    // MARK: Naming every provider

    /// Derived from `displayOrder`, so a fourth provider appears in the prose the
    /// moment it is added to the enum rather than the next time someone
    /// remembers to edit a sentence.
    func testAllNamesSentenceNamesEveryProvider() {
        let sentence = CoachProvider.allNamesSentence
        for provider in CoachProvider.allCases {
            XCTAssertTrue(sentence.contains(provider.displayName),
                          "\(provider.displayName) is missing from \"\(sentence)\"")
        }
    }

    func testAllNamesSentenceReadsAsProse() {
        // "Anthropic, OpenAI, or Gemini" — an Oxford-comma list, not a raw join.
        XCTAssertTrue(CoachProvider.allNamesSentence.contains(", or "))
        XCTAssertFalse(CoachProvider.allNamesSentence.hasSuffix(","))
        XCTAssertFalse(CoachProvider.allNamesSentence.contains(",,"))
    }

    // MARK: keyRequirementCopy

    /// With a key connected the sentence names THAT provider and no other, so it
    /// can never contradict the request the sheet is about to make.
    func testNamesTheConnectedProviderAndNoOther() {
        for provider in CoachProvider.allCases {
            let copy = CoachProvider.keyRequirementCopy(action: "Importing", provider: provider)
            XCTAssertTrue(copy.contains(provider.displayName),
                          "\(provider.displayName) copy does not name itself: \(copy)")

            for other in CoachProvider.allCases where other != provider {
                XCTAssertFalse(copy.contains(other.displayName),
                               "copy for \(provider.displayName) also names \(other.displayName): \(copy)")
            }
        }
    }

    /// With nothing connected there is no provider to name, so the copy must
    /// offer all of them rather than picking one.
    func testNamesEveryProviderWhenNoneIsConnected() {
        let copy = CoachProvider.keyRequirementCopy(action: "Searching", provider: nil)
        for provider in CoachProvider.allCases {
            XCTAssertTrue(copy.contains(provider.displayName),
                          "\(provider.displayName) missing from the no-key copy: \(copy)")
        }
    }

    /// The two sheets must read distinctly instead of sharing one sentence.
    func testUsesTheCallersVerb() {
        XCTAssertTrue(CoachProvider.keyRequirementCopy(action: "Importing", provider: .openai)
            .hasPrefix("Importing"))
        XCTAssertTrue(CoachProvider.keyRequirementCopy(action: "Searching", provider: nil)
            .hasPrefix("Searching"))
    }

    func testNoKeyCopyPointsAtSettingsAndTheManualPath() {
        let copy = CoachProvider.keyRequirementCopy(action: "Importing", provider: nil)
        XCTAssertTrue(copy.contains("Settings"), "the user needs to know where to connect a key")
        XCTAssertTrue(copy.lowercased().contains("manually"), "the manual path must stay offered")
    }

    // MARK: House style

    func testNoEmDashesInAnyVariant() {
        var variants = [CoachProvider.keyRequirementCopy(action: "Importing", provider: nil),
                        CoachProvider.allNamesSentence]
        for provider in CoachProvider.allCases {
            variants.append(CoachProvider.keyRequirementCopy(action: "Importing", provider: provider))
        }
        for copy in variants {
            XCTAssertFalse(copy.contains("—"), "em dash in: \(copy)")
        }
    }

    /// `article` exists so prose reads correctly before a provider name; the rule
    /// is about sound, not spelling, so it is asserted rather than derived.
    func testArticleReadsCorrectlyForEveryProvider() {
        XCTAssertEqual(CoachProvider.anthropic.article, "an")
        XCTAssertEqual(CoachProvider.openai.article, "an")
        XCTAssertEqual(CoachProvider.gemini.article, "a")
    }
}
