import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class SessionStoreTests: XCTestCase {

    private final class MemoryTokens: TokenStoring {
        var store: [String: String] = [:]
        func read(_ account: String) -> String? { store[account] }
        func save(_ value: String, account: String) { store[account] = value }
        func delete(_ account: String) { store[account] = nil }
    }

    // Fake credential checker: returns a canned state and counts calls, so tests
    // exercise the revalidation lifecycle without ASAuthorizationAppleIDProvider.
    private final class FakeCredentialChecker: AppleCredentialChecking {
        var result: AppleCredentialState
        private(set) var calls = 0
        init(_ result: AppleCredentialState) { self.result = result }
        func state(forUserID userID: String) async -> AppleCredentialState {
            calls += 1
            return result
        }
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "SessionStoreTests.\(UUID().uuidString)")!
    }

    private func signedInStore(token: String = "u",
                               checker: AppleCredentialChecking,
                               window: TimeInterval = 24 * 60 * 60,
                               now: @escaping () -> Date = { Date() },
                               defaults d: UserDefaults? = nil) -> (SessionStore, MemoryTokens) {
        let t = MemoryTokens(); t.store["otterpace.appleUserID"] = token
        let s = SessionStore(tokens: t, defaults: d ?? defaults(),
                             credentialChecker: checker, revalidationWindow: window,
                             now: now, seeded: false, wantsSignInPreview: false)
        return (s, t)
    }

    // Production with no saved identity and no guest choice → show the sign-in screen.
    func testFreshProductionIsUndecided() {
        let s = SessionStore(tokens: MemoryTokens(), defaults: defaults(), seeded: false, wantsSignInPreview: false)
        XCTAssertEqual(s.state, .undecided)
    }

    // A normal seeded scenario skips sign-in (so existing previews go to content).
    func testSeededScenarioSkipsToGuest() {
        let s = SessionStore(tokens: MemoryTokens(), defaults: defaults(), seeded: true, wantsSignInPreview: false)
        XCTAssertEqual(s.state, .guest)
    }

    // A scenario can opt in to preview the sign-in screen.
    func testSignInPreviewSeedShowsSignIn() {
        let s = SessionStore(tokens: MemoryTokens(), defaults: defaults(), seeded: true, wantsSignInPreview: true)
        XCTAssertEqual(s.state, .undecided)
    }

    // A previously-saved Apple identifier resumes the signed-in state.
    func testExistingTokenResumesSignedIn() {
        let t = MemoryTokens(); t.store["otterpace.appleUserID"] = "001234.abcDEF"
        let s = SessionStore(tokens: t, defaults: defaults(), seeded: false, wantsSignInPreview: false)
        XCTAssertEqual(s.state, .signedIn(userID: "001234.abcDEF"))
    }

    // Signing in persists the identifier and moves to signed-in.
    func testSignInPersists() {
        let t = MemoryTokens()
        let s = SessionStore(tokens: t, defaults: defaults(), seeded: false, wantsSignInPreview: false)
        s.signIn(userID: "apple-user-1")
        XCTAssertEqual(s.state, .signedIn(userID: "apple-user-1"))
        XCTAssertEqual(t.store["otterpace.appleUserID"], "apple-user-1")
    }

    // Continuing as guest is remembered so we don't re-prompt next launch.
    func testContinueAsGuestRemembered() {
        let d = defaults()
        let s = SessionStore(tokens: MemoryTokens(), defaults: d, seeded: false, wantsSignInPreview: false)
        s.continueAsGuest()
        XCTAssertEqual(s.state, .guest)
        let next = SessionStore(tokens: MemoryTokens(), defaults: d, seeded: false, wantsSignInPreview: false)
        XCTAssertEqual(next.state, .guest)
    }

    // Signing out forgets the Apple identity but keeps the app usable as a guest.
    func testSignOutBecomesGuest() {
        let t = MemoryTokens(); t.store["otterpace.appleUserID"] = "x"
        let s = SessionStore(tokens: t, defaults: defaults(), seeded: false, wantsSignInPreview: false)
        s.signOut()
        XCTAssertEqual(s.state, .guest)
        XCTAssertNil(t.store["otterpace.appleUserID"])
    }

    // Deleting the account forgets the identity AND the guest choice, returning
    // to the welcome screen (the App Store account-deletion path).
    func testDeleteAccountResets() {
        let d = defaults()
        let t = MemoryTokens(); t.store["otterpace.appleUserID"] = "x"
        let s = SessionStore(tokens: t, defaults: d, seeded: false, wantsSignInPreview: false)
        s.deleteAccount()
        XCTAssertEqual(s.state, .undecided)
        XCTAssertNil(t.store["otterpace.appleUserID"])
        // A fresh launch with no token and no guest choice stays at the welcome screen.
        let next = SessionStore(tokens: MemoryTokens(), defaults: d, seeded: false, wantsSignInPreview: false)
        XCTAssertEqual(next.state, .undecided)
    }

    // MARK: - Durable revalidation lifecycle

    // A stored credential that's still authorized keeps the user signed in across
    // relaunch — the core "session survives restarts" guarantee.
    func testAuthorizedStaysSignedInAcrossRelaunch() async {
        let checker = FakeCredentialChecker(.authorized)
        let (s, t) = signedInStore(checker: checker)
        XCTAssertEqual(s.state, .signedIn(userID: "u"))
        await s.revalidate()
        XCTAssertEqual(s.state, .signedIn(userID: "u"))
        XCTAssertEqual(t.store["otterpace.appleUserID"], "u")
        XCTAssertEqual(checker.calls, 1)
    }

    // Within the revalidation window, a second check is skipped — long-lived, no churn.
    func testWithinWindowSkipsRecheck() async {
        let d = defaults()
        let checker = FakeCredentialChecker(.authorized)
        let clock = { Date(timeIntervalSinceReferenceDate: 1000) }
        let s = SessionStore(tokens: MemoryTokens(), defaults: d, credentialChecker: checker,
                             revalidationWindow: 3600, now: clock, seeded: false, wantsSignInPreview: false)
        s.signIn(userID: "u")        // stamps lastValidatedAt = 1000
        await s.revalidate()         // clock still 1000 → inside the 3600s window
        XCTAssertEqual(checker.calls, 0)
        XCTAssertEqual(s.state, .signedIn(userID: "u"))
    }

    // A genuinely revoked credential ends the session into GUEST, not the welcome
    // screen — the app keeps working, no nag.
    func testRevokedDropsToGuestNotWelcome() async {
        let checker = FakeCredentialChecker(.revoked)
        let (s, t) = signedInStore(checker: checker)
        await s.revalidate()
        XCTAssertEqual(s.state, .guest)
        XCTAssertNotEqual(s.state, .undecided)
        XCTAssertNil(t.store["otterpace.appleUserID"])
    }

    // `.notFound` (identifier unknown to Apple) is treated like revocation → guest.
    func testNotFoundDropsToGuest() async {
        let checker = FakeCredentialChecker(.notFound)
        let (s, _) = signedInStore(checker: checker)
        await s.revalidate()
        XCTAssertEqual(s.state, .guest)
    }

    // An offline/unknown check result keeps the user signed in (transient failures
    // never log the user out).
    func testUnknownKeepsSessionSignedIn() async {
        let checker = FakeCredentialChecker(.unknown)
        let (s, _) = signedInStore(checker: checker)
        await s.revalidate()
        XCTAssertEqual(s.state, .signedIn(userID: "u"))
    }

    // Revalidation is a no-op for a guest (nothing to check, no accidental sign-in).
    func testRevalidateNoOpForGuest() async {
        let checker = FakeCredentialChecker(.authorized)
        let s = SessionStore(tokens: MemoryTokens(), defaults: defaults(), credentialChecker: checker,
                             seeded: false, wantsSignInPreview: false)
        s.continueAsGuest()
        await s.revalidate()
        XCTAssertEqual(s.state, .guest)
        XCTAssertEqual(checker.calls, 0)
    }
}
