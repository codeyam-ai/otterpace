import XCTest
@testable import AppCore

// How a failed coach call reaches the user.
//
// Regression: a working OpenAI key produced "I couldn't reach Buddy just now.
// Check your connection and try again." The key was valid and the network was
// fine — the backend had rejected the request for a provider-side reason — but
// every non-401 collapsed into `.server`, so the chat pointed the user at the
// one thing that was not wrong. These pin the reason surviving the trip.
final class CoachErrorSurfacingTests: XCTestCase {

    private func body(_ json: String) -> Data { Data(json.utf8) }

    func testActionableUpstreamReasonSurvives() {
        let data = body("""
        {"error":"model_unavailable","message":"OpenAI rejected the request: model \\"gpt-5\\" may be unavailable to this key."}
        """)
        XCTAssertEqual(RemoteCoach.errorMessage(from: data),
                       "OpenAI rejected the request: model \"gpt-5\" may be unavailable to this key.")
    }

    /// The real cause of the reported outage: an OpenAI account with no credits.
    /// The user can fix this in a minute, but only if they are told what it is
    /// AND where to go.
    func testOutOfCreditsIsSurfaced() {
        let data = body("""
        {"error":"insufficient_quota","message":"Your OpenAI account is out of credits, so it turned down my request. Add credits at platform.openai.com/settings/organization/billing and ask me again."}
        """)
        let message = RemoteCoach.errorMessage(from: data)
        XCTAssertNotNil(message)
        XCTAssertTrue(message!.contains("out of credits"))
        XCTAssertTrue(message!.contains("platform.openai.com"), "must say where to add credits")
        // The two messages this used to be mistaken for.
        XCTAssertFalse(message!.contains("connection"))
        XCTAssertFalse(message!.contains("try again shortly"))
    }

    /// The message renders as a chat bubble from Buddy, so the billing URL has to
    /// be tappable — a link the user must retype is barely better than none.
    func testBillingLinkIsTappableInTheBubble() {
        let text = "Your OpenAI account is out of credits, so it turned down my request. Add credits at platform.openai.com/settings/organization/billing and ask me again."
        let attributed = ChatBubble.linkified(text)

        let links = attributed.runs.compactMap { $0.link }
        XCTAssertEqual(links.count, 1, "the billing URL should become exactly one link")
        XCTAssertEqual(links.first?.scheme, "https", "a bare host must be upgraded to an absolute URL")
        XCTAssertTrue(links.first?.absoluteString.contains("platform.openai.com") == true)

        // The prose must survive untouched.
        XCTAssertEqual(String(attributed.characters), text)
    }

    func testOrdinaryCoachReplyGetsNoLinks() {
        let plain = "You ran yesterday, so an easy walk today keeps things moving without adding stress."
        let attributed = ChatBubble.linkified(plain)
        XCTAssertTrue(attributed.runs.allSatisfy { $0.link == nil })
        XCTAssertEqual(String(attributed.characters), plain)
    }

    func testAnthropicAndGeminiBillingLinksAlsoResolve() {
        for host in ["console.anthropic.com/settings/billing",
                     "aistudio.google.com/app/plan_information"] {
            let attributed = ChatBubble.linkified("Add credits at \(host) and ask me again.")
            let links = attributed.runs.compactMap { $0.link }
            XCTAssertEqual(links.count, 1, "\(host) should linkify")
            XCTAssertTrue(links.first?.absoluteString.contains(host) == true)
        }
    }

    func testExhaustedBudgetIsSurfaced() {
        let data = body("""
        {"error":"token_budget_exhausted","message":"OpenAI used its entire token budget before answering."}
        """)
        XCTAssertEqual(RemoteCoach.errorMessage(from: data),
                       "OpenAI used its entire token budget before answering.")
    }

    /// A genuine outage stays generic — the caller falls back to the offline
    /// coach rather than showing the user backend jargon they cannot act on.
    func testGenericUpstreamErrorIsNotSurfaced() {
        XCTAssertNil(RemoteCoach.errorMessage(from: body(#"{"error":"upstream_error"}"#)))
        XCTAssertNil(RemoteCoach.errorMessage(from: body(#"{"error":"no_text"}"#)))
    }

    func testMalformedOrEmptyBodiesAreIgnored() {
        XCTAssertNil(RemoteCoach.errorMessage(from: body("not json")))
        XCTAssertNil(RemoteCoach.errorMessage(from: Data()))
        XCTAssertNil(RemoteCoach.errorMessage(from: body(#"{"error":"model_unavailable"}"#)))
        XCTAssertNil(RemoteCoach.errorMessage(from: body(#"{"error":"model_unavailable","message":""}"#)))
    }

    /// The error the chat renders must not be the connection copy.
    func testUpstreamErrorIsDistinctFromNetworkError() {
        XCTAssertNotEqual(CoachError.upstream("model unavailable"), CoachError.server)
        XCTAssertNotEqual(CoachError.upstream("model unavailable"), CoachError.network)
        XCTAssertEqual(CoachError.upstream("same"), CoachError.upstream("same"))
    }
}
