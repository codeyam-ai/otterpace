import XCTest
@testable import AppCore

// Tests for the M3/M5 integration modules' pure logic: reminder preferences,
// the BYO-coach-key store, and the RemoteCoach HTTP-status → CoachError mapping
// (the network call is stubbed via URLProtocol so no real request is made).

// MARK: - ReminderSettings

final class ReminderSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ReminderSettingsTests.\(UUID().uuidString)")!
    }

    // A fresh install has every reminder off, with sensible default times.
    func testDefaultsAreOff() {
        let s = ReminderSettings.load(defaults())
        XCTAssertFalse(s.dailyEnabled)
        XCTAssertFalse(s.goalEnabled)
        XCTAssertFalse(s.inactivityEnabled)
        XCTAssertFalse(s.anyEnabled)
        XCTAssertEqual(s.dailyHour, ReminderSettings.defaultDailyHour)
        XCTAssertEqual(s.inactivityHours, ReminderSettings.defaultInactivityHours)
    }

    // save() then load() round-trips every field exactly.
    func testSaveLoadRoundTrip() {
        let d = defaults()
        let s = ReminderSettings(dailyEnabled: true, dailyHour: 7, dailyMinute: 30,
                                 goalEnabled: true, inactivityEnabled: true, inactivityHours: 4)
        s.save(d)
        XCTAssertEqual(ReminderSettings.load(d), s)
        XCTAssertTrue(ReminderSettings.load(d).anyEnabled)
    }

    // An explicitly-set midnight (hour 0) is preserved, not mistaken for "unset".
    func testMidnightDailyHourPreserved() {
        let d = defaults()
        ReminderSettings(dailyEnabled: true, dailyHour: 0, dailyMinute: 0).save(d)
        XCTAssertEqual(ReminderSettings.load(d).dailyHour, 0)
    }
}

// MARK: - CoachKeyStore

final class CoachKeyStoreTests: XCTestCase {
    private final class MemoryTokens: TokenStoring {
        var store: [String: String] = [:]
        func read(_ account: String) -> String? { store[account] }
        func save(_ value: String, account: String) { store[account] = value }
        func delete(_ account: String) { store[account] = nil }
    }

    /// A store over in-memory tokens and a throwaway UserDefaults suite, so no
    /// test touches the real Keychain or leaks state into another test.
    private func makeStore(_ tokens: MemoryTokens = MemoryTokens()) -> (CoachKeyStore, UserDefaults) {
        let d = UserDefaults(suiteName: "coach-key-store-\(UUID().uuidString)")!
        return (CoachKeyStore(store: tokens, defaults: d), d)
    }

    // With no key saved, the store reports not-connected for every provider.
    func testEmptyIsNotConnected() {
        let (s, _) = makeStore()
        XCTAssertFalse(s.isConnected)
        XCTAssertTrue(s.connectedProviders.isEmpty)
        XCTAssertNil(s.activeProvider)
        XCTAssertNil(s.activeKey)
        for provider in CoachProvider.allCases {
            XCTAssertNil(s.key(for: provider))
            XCTAssertFalse(s.isConnected(provider))
        }
    }

    // Saving a key trims surrounding whitespace and reports connected.
    func testSaveTrimsAndConnects() {
        let (s, _) = makeStore()
        s.save("  sk-ant-abc  ", for: .anthropic)
        XCTAssertEqual(s.key(for: .anthropic), "sk-ant-abc")
        XCTAssertTrue(s.isConnected)
        XCTAssertEqual(s.activeProvider, .anthropic)
        XCTAssertEqual(s.activeKey, "sk-ant-abc")
    }

    // clear(provider) removes just that provider's key.
    func testClearOneProvider() {
        let (s, _) = makeStore()
        s.save("sk-ant-xyz", for: .anthropic)
        s.clear(.anthropic)
        XCTAssertNil(s.key(for: .anthropic))
        XCTAssertFalse(s.isConnected)
    }

    // A whitespace-only entry trims to empty, so it's treated as no key.
    func testWhitespaceSaveIsNotConnected() {
        let (s, _) = makeStore()
        s.save("    ", for: .anthropic)
        XCTAssertNil(s.key(for: .anthropic))
        XCTAssertFalse(s.isConnected)
    }

    // MARK: Paste detection

    // A pasted key is filed under the provider its shape identifies.
    func testSaveDetectsProviderFromKeyShape() {
        let cases: [(String, CoachProvider)] = [
            ("sk-ant-api03-abcdef", .anthropic),
            ("sk-proj-abcdef123456", .openai),
            ("AIzaSyABCDEF123456", .gemini),
        ]
        for (key, expected) in cases {
            let (s, _) = makeStore()
            XCTAssertEqual(s.save(key), expected, "\(key) should file under \(expected)")
            XCTAssertEqual(s.key(for: expected), key)
            XCTAssertEqual(s.activeProvider, expected)
        }
    }

    // The Anthropic prefix is also a valid OpenAI `sk-` prefix, so the more
    // specific pattern must win or every Anthropic key lands under OpenAI.
    func testAnthropicKeyIsNotMistakenForOpenAI() {
        XCTAssertEqual(CoachProvider.detect(fromKey: "sk-ant-api03-xyz"), .anthropic)
        XCTAssertEqual(CoachProvider.detect(fromKey: "sk-xyz"), .openai)
    }

    // An unrecognized shape saves nothing, so the UI can ask the user to pick.
    func testUnrecognizedKeyIsNotSaved() {
        let (s, _) = makeStore()
        XCTAssertNil(s.save("totally-unknown-key-format"))
        XCTAssertFalse(s.isConnected)
        XCTAssertNil(CoachProvider.detect(fromKey: "   "))
    }

    // Detection ignores surrounding whitespace from a sloppy paste.
    func testDetectionTrimsWhitespace() {
        XCTAssertEqual(CoachProvider.detect(fromKey: "  AIzaSyABC  \n"), .gemini)
    }

    // MARK: Several providers at once

    // Every connected provider is reported, in stable display order.
    func testMultipleProvidersConnect() {
        let (s, _) = makeStore()
        s.save("AIzaSyABC", for: .gemini)
        s.save("sk-openai", for: .openai)
        s.save("sk-ant-abc", for: .anthropic)
        XCTAssertEqual(s.connectedProviders, [.anthropic, .openai, .gemini])
    }

    // Switching the active provider changes which key a request would carry,
    // without disturbing any of the stored keys.
    func testSetActiveSwitchesWithoutLosingKeys() {
        let (s, _) = makeStore()
        s.save("sk-ant-abc", for: .anthropic)
        s.save("sk-openai", for: .openai)
        s.setActive(.anthropic)
        XCTAssertEqual(s.activeKey, "sk-ant-abc")
        s.setActive(.openai)
        XCTAssertEqual(s.activeProvider, .openai)
        XCTAssertEqual(s.activeKey, "sk-openai")
        XCTAssertEqual(s.key(for: .anthropic), "sk-ant-abc", "switching must not drop the other key")
    }

    // Disconnecting the active provider promotes another connected one rather
    // than dropping the user to the offline coach.
    func testDisconnectingActivePromotesAnother() {
        let (s, _) = makeStore()
        s.save("sk-ant-abc", for: .anthropic)
        s.save("sk-openai", for: .openai)
        s.setActive(.openai)
        s.clear(.openai)
        XCTAssertTrue(s.isConnected)
        XCTAssertEqual(s.activeProvider, .anthropic)
        XCTAssertEqual(s.activeKey, "sk-ant-abc")
    }

    // Disconnecting the last provider leaves nothing active.
    func testDisconnectingLastProviderLeavesNoneActive() {
        let (s, _) = makeStore()
        s.save("sk-openai", for: .openai)
        s.clear(.openai)
        XCTAssertFalse(s.isConnected)
        XCTAssertNil(s.activeProvider)
    }

    // clear() with no argument disconnects everything.
    func testClearAll() {
        let (s, _) = makeStore()
        s.save("sk-ant-abc", for: .anthropic)
        s.save("sk-openai", for: .openai)
        s.clear()
        XCTAssertFalse(s.isConnected)
        XCTAssertNil(s.activeProvider)
    }

    // MARK: Migration from the single-key era

    // A key written under the original account is already connected and active:
    // an existing user opens Settings to a working coach with nothing to re-enter.
    func testExistingAnthropicKeyMigratesSilently() {
        let tokens = MemoryTokens()
        tokens.store["coach-anthropic-key"] = "sk-ant-legacy"
        let (s, _) = makeStore(tokens)
        XCTAssertTrue(s.isConnected)
        XCTAssertEqual(s.connectedProviders, [.anthropic])
        XCTAssertEqual(s.activeProvider, .anthropic)
        XCTAssertEqual(s.activeKey, "sk-ant-legacy")
    }

    // A remembered choice pointing at a provider that is no longer connected
    // falls back instead of reporting an active provider with no key.
    func testStaleActiveChoiceFallsBack() {
        let (s, d) = makeStore()
        s.save("sk-ant-abc", for: .anthropic)
        d.set(CoachProvider.gemini.rawValue, forKey: CoachConfig.activeProviderKey)
        XCTAssertEqual(s.activeProvider, .anthropic)
        XCTAssertEqual(s.activeKey, "sk-ant-abc")
    }

    // MARK: Scenario seeding

    // A scenario declares the connection shape without a real key, so a capture
    // renders connected rows while `activeKey` stays nil (no network call).
    func testScenarioSeedDeclaresConnectionShape() {
        let (s, d) = makeStore()
        d.set("anthropic,openai", forKey: CoachConfig.seedConnectedProvidersKey)
        d.set("openai", forKey: CoachConfig.seedActiveProviderKey)
        XCTAssertEqual(s.connectedProviders, [.anthropic, .openai])
        XCTAssertEqual(s.activeProvider, .openai)
        XCTAssertNil(s.activeKey, "a seeded scenario carries no secret")
    }

    // The pre-multi-provider hook still means "Anthropic connected", so every
    // scenario written before this feature captures the same frame.
    func testLegacySeedHookStillMeansAnthropic() {
        let (s, d) = makeStore()
        d.set(true, forKey: CoachConfig.seedConnectedKey)
        XCTAssertEqual(s.connectedProviders, [.anthropic])
        XCTAssertEqual(s.activeProvider, .anthropic)
    }

    // An explicit `false` seed forces the disconnected state even if a key exists,
    // which is what the "no key" capture relies on.
    func testLegacySeedFalseForcesDisconnected() {
        let (s, d) = makeStore()
        s.save("sk-ant-abc", for: .anthropic)
        d.set(false, forKey: CoachConfig.seedConnectedKey)
        XCTAssertFalse(s.isConnected)
    }

    // With no seed key present at all, the store reports the real Keychain state.
    func testAbsentSeedFallsThroughToRealKeys() {
        let (s, _) = makeStore()
        s.save("sk-ant-abc", for: .anthropic)
        XCTAssertTrue(s.isConnected)
    }
}

// MARK: - RemoteCoach status mapping

// MARK: - BYO-key request headers
//
// `RemoteCoach` and `RaceImportClient` must authenticate identically — a drift
// between them would authenticate one feature and 400 the other — so both go
// through `CoachRequestHeaders`. These assert the wire contract the backend's
// `credentialsFromHeaders` reads.
final class CoachRequestHeadersTests: XCTestCase {
    private func headers(for provider: CoachProvider, key: String = "k-123") -> [String: String] {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        CoachRequestHeaders.apply(provider: provider, apiKey: key, to: &request)
        return request.allHTTPHeaderFields ?? [:]
    }

    // Every provider names itself and carries the key on the current headers.
    func testNamesProviderAndCarriesKey() {
        for provider in CoachProvider.allCases {
            let h = headers(for: provider)
            XCTAssertEqual(h[CoachRequestHeaders.provider], provider.rawValue)
            XCTAssertEqual(h[CoachRequestHeaders.key], "k-123")
        }
    }

    // An Anthropic key ALSO rides the legacy header, so an app build that ships
    // ahead of the backend keeps working against the Anthropic-only deployment.
    func testAnthropicAlsoSendsLegacyHeader() {
        XCTAssertEqual(headers(for: .anthropic)[CoachRequestHeaders.legacyAnthropicKey], "k-123")
    }

    // The legacy header must NOT carry a non-Anthropic key: an older backend
    // would otherwise spend an OpenAI/Gemini key against Anthropic.
    func testNonAnthropicOmitsLegacyHeader() {
        for provider in [CoachProvider.openai, .gemini] {
            XCTAssertNil(headers(for: provider)[CoachRequestHeaders.legacyAnthropicKey],
                         "\(provider) must not populate the Anthropic-only header")
        }
    }
}

// MARK: - RaceImportClient

final class RaceImportClientTests: XCTestCase {
    private func makeClient() -> RaceImportClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return RaceImportClient(importEndpoint: URL(string: "https://example.com/api/race-import")!,
                                searchEndpoint: URL(string: "https://example.com/api/race-search")!,
                                session: URLSession(configuration: config))
    }

    override func tearDown() {
        StubURLProtocol.responder = nil
        super.tearDown()
    }

    /// Capture the request the client actually sent, then answer it.
    private func captureRequest(status: Int, body: String) -> () -> URLRequest? {
        var seen: URLRequest?
        StubURLProtocol.responder = { request in
            seen = request
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        return { seen }
    }

    // The active provider travels with the import request, so a Gemini user's
    // race import is routed to Gemini and not silently to Anthropic.
    func testImportSendsActiveProviderHeaders() async throws {
        let seen = captureRequest(status: 200, body: #"{"race":{},"confidence":0,"missingFields":[]}"#)
        _ = try? await makeClient().importRace(from: "https://race.example/x", apiKey: "AIza-1", provider: .gemini)
        XCTAssertEqual(seen()?.value(forHTTPHeaderField: CoachRequestHeaders.provider), "gemini")
        XCTAssertEqual(seen()?.value(forHTTPHeaderField: CoachRequestHeaders.key), "AIza-1")
    }

    // Search authenticates the same way as import.
    func testSearchSendsActiveProviderHeaders() async throws {
        let seen = captureRequest(status: 200, body: #"{"results":[]}"#)
        _ = try? await makeClient().searchRaces(query: "trail half", apiKey: "sk-openai", provider: .openai)
        XCTAssertEqual(seen()?.value(forHTTPHeaderField: CoachRequestHeaders.provider), "openai")
    }

    // A rejected key surfaces to the user; other failures fall back to manual entry.
    func test401IsInvalidKey() async {
        _ = captureRequest(status: 401, body: "{}")
        do {
            _ = try await makeClient().searchRaces(query: "x", apiKey: "k", provider: .anthropic)
            XCTFail("expected invalidKey")
        } catch let error as CoachError {
            XCTAssertEqual(error, .invalidKey)
        } catch {
            XCTFail("expected CoachError, got \(error)")
        }
    }
}

final class RemoteCoachTests: XCTestCase {
    private func makeCoach() -> RemoteCoach {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return RemoteCoach(endpoint: URL(string: "https://example.com/api/coach")!,
                           session: URLSession(configuration: config))
    }

    private func respond(status: Int, body: String) {
        StubURLProtocol.responder = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    override func tearDown() {
        StubURLProtocol.responder = nil
        super.tearDown()
    }

    // A 200 with a valid body decodes into a CoachReply.
    func testSuccessDecodes() async throws {
        respond(status: 200, body: #"{"text":"Easy walk today.","mood":"recovery","safetyFlag":true}"#)
        let reply = try await makeCoach().reply(to: "should I rest?", context: .empty, apiKey: "k")
        XCTAssertEqual(reply.text, "Easy walk today.")
        XCTAssertEqual(reply.mood, .recovery)
        XCTAssertTrue(reply.safetyFlag)
    }

    // 401 is the only status that means "your key was rejected".
    func test401IsInvalidKey() async {
        respond(status: 401, body: "{}")
        await assertThrows(.invalidKey)
    }

    // 429 maps to rateLimited.
    func test429IsRateLimited() async {
        respond(status: 429, body: "{}")
        await assertThrows(.rateLimited)
    }

    // A 400 is a server-side/request bug, NOT the user's key — must not say "invalid key".
    func test400IsServerNotInvalidKey() async {
        respond(status: 400, body: "{}")
        await assertThrows(.server)
    }

    // A 200 with malformed JSON is a server error (caller falls back to the mock).
    func testMalformedBodyIsServer() async {
        respond(status: 200, body: "not json")
        await assertThrows(.server)
    }

    private func assertThrows(_ expected: CoachError,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await makeCoach().reply(to: "hi", context: .empty, apiKey: "k")
            XCTFail("expected \(expected) to be thrown", file: file, line: line)
        } catch let error as CoachError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}

/// Minimal URLProtocol stub: returns whatever `responder` produces for a request.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let responder = StubURLProtocol.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
