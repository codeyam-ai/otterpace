import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
// The network call is stubbed via URLProtocol so no real request is made.
final class PushRegistrationServiceTests: XCTestCase {

    private func makeService(token: String?, status: Int = 200) -> PushRegistrationService {
        PushCaptureURLProtocol.lastRequest = nil
        PushCaptureURLProtocol.status = status
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PushCaptureURLProtocol.self]
        return PushRegistrationService(
            session: URLSession(configuration: config),
            base: URL(string: "https://example.com/api")!,
            tokenProvider: { token }
        )
    }

    override func tearDown() {
        PushCaptureURLProtocol.lastRequest = nil
        super.tearDown()
    }

    // MARK: Gating — opt-in requires a session

    // With no bearer session, register is a no-op: returns false and never fires a request.
    func testRegisterNoOpsWithoutSession() async {
        let service = makeService(token: nil)
        let ok = await service.register(deviceToken: "abc123")
        XCTAssertFalse(ok)
        XCTAssertNil(PushCaptureURLProtocol.lastRequest)
    }

    // MARK: Request shape

    // A signed-in register POSTs to /account/push with the bearer attached, and
    // reports success on a 2xx.
    func testRegisterPostsWithBearer() async {
        let service = makeService(token: "sess-token", status: 200)
        let ok = await service.register(deviceToken: "abc123")
        XCTAssertTrue(ok)
        let req = PushCaptureURLProtocol.lastRequest
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.url?.path, "/api/account/push")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer sess-token")
    }

    // A non-2xx response is a soft failure — returns false, app stays functional.
    func testRegisterReportsFailureOnNon2xx() async {
        let service = makeService(token: "sess-token", status: 500)
        let ok = await service.register(deviceToken: "abc123")
        XCTAssertFalse(ok)
    }

    // deregisterAll issues a DELETE (the sign-out / health-off opt-out).
    func testDeregisterAllDeletes() async {
        let service = makeService(token: "sess-token", status: 200)
        let ok = await service.deregisterAll()
        XCTAssertTrue(ok)
        XCTAssertEqual(PushCaptureURLProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(PushCaptureURLProtocol.lastRequest?.url?.path, "/api/account/push")
    }

    // MARK: ServerPushGate — double-nudge suppression policy

    // The local nudge is suppressed only when all three opt-in conditions hold.
    func testServerPushGateRequiresAllThreeConditions() {
        XCTAssertTrue(ServerPushGate.suppressesLocalNudge(signedIn: true, healthSyncEnabled: true, pushRegistered: true))
        XCTAssertFalse(ServerPushGate.suppressesLocalNudge(signedIn: false, healthSyncEnabled: true, pushRegistered: true))
        XCTAssertFalse(ServerPushGate.suppressesLocalNudge(signedIn: true, healthSyncEnabled: false, pushRegistered: true))
        XCTAssertFalse(ServerPushGate.suppressesLocalNudge(signedIn: true, healthSyncEnabled: true, pushRegistered: false))
    }

    // MARK: SyncableHealthSnapshot — heartbeat fields round-trip

    // The movement heartbeat fields survive a Codable round-trip and are omitted
    // (nil) by default so a snapshot without them is unchanged.
    func testHealthSnapshotHeartbeatRoundTrips() throws {
        let snap = SyncableHealthSnapshot(steps: 6000, distanceMiles: 2.0, activeMinutes: 20,
                                          activeEnergyKcal: 150, lastMovementAt: "2026-07-08T14:00:00Z",
                                          inactivityHours: 3)
        let decoded = try JSONDecoder().decode(SyncableHealthSnapshot.self,
                                               from: JSONEncoder().encode(snap))
        XCTAssertEqual(decoded, snap)
        XCTAssertEqual(decoded.lastMovementAt, "2026-07-08T14:00:00Z")
        XCTAssertEqual(decoded.inactivityHours, 3)

        let plain = SyncableHealthSnapshot(steps: 100, distanceMiles: 0, activeMinutes: 0, activeEnergyKcal: 0)
        XCTAssertNil(plain.lastMovementAt)
        XCTAssertNil(plain.inactivityHours)
    }
}

/// URLProtocol stub that records the last request and returns a configurable status.
private final class PushCaptureURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var status: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        PushCaptureURLProtocol.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: PushCaptureURLProtocol.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
