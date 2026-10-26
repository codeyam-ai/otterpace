import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
// StravaService's network and OAuth calls are glue; these cover the decisions it
// makes around them, which are platform-free.
final class StravaServiceTests: XCTestCase {

    // The authorize page carries the app's client id and the device key as
    // `state`, so the server-side callback can pair the code with this install.
    func testAuthorizeURLCarriesClientIDAndDeviceKey() throws {
        let url = try XCTUnwrap(StravaService.authorizeURL(clientID: "12345", deviceKey: "DEVICE-1"))
        let items = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "www.strava.com")
        XCTAssertEqual(items["client_id"], "12345")
        XCTAssertEqual(items["state"], "DEVICE-1")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["redirect_uri"], StravaConfig.redirectURI)
        XCTAssertEqual(items["scope"], StravaConfig.scope)
    }

    // The callback's `code` is what gets exchanged for tokens.
    func testAuthorizationCodeReadFromCallback() {
        let url = URL(string: "otterpace://strava?state=DEVICE-1&code=abc123&scope=read")
        XCTAssertEqual(StravaService.authorizationCode(from: url), "abc123")
    }

    // A denied login (Strava sends `error=` and no code), an empty code, or no
    // callback at all is a failure, never an empty code sent to the server.
    func testAuthorizationCodeNilWhenMissingOrEmpty() {
        XCTAssertNil(StravaService.authorizationCode(from: URL(string: "otterpace://strava?error=access_denied")))
        XCTAssertNil(StravaService.authorizationCode(from: URL(string: "otterpace://strava?code=")))
        XCTAssertNil(StravaService.authorizationCode(from: nil))
    }

    // A 200 response maps each activity to a LatestWorkout.
    func testDecodeActivitiesMapsWorkouts() throws {
        let json = """
        {"connected": true, "activities": [
          {"type": "run", "distanceMiles": 4.2, "durationMinutes": 43, "pace": "10:15/mi", "date": "2026-06-21", "source": "strava"}
        ]}
        """
        let workouts = try StravaService.decodeActivities(Data(json.utf8), statusCode: 200)
        XCTAssertEqual(workouts, [LatestWorkout(type: "run", distanceMiles: 4.2, durationMinutes: 43,
                                                pace: "10:15/mi", date: "2026-06-21", source: "strava")])
    }

    // Connected with nothing imported yet is a legitimate empty list, not an error.
    func testDecodeActivitiesEmptyListIsNotAnError() throws {
        let workouts = try StravaService.decodeActivities(Data(#"{"connected": true, "activities": []}"#.utf8), statusCode: 200)
        XCTAssertEqual(workouts, [])
    }

    // A non-200 (or no HTTP response at all) is a real failure the caller can show.
    func testDecodeActivitiesThrowsOnNon200() {
        XCTAssertThrowsError(try StravaService.decodeActivities(Data("{}".utf8), statusCode: 502))
        XCTAssertThrowsError(try StravaService.decodeActivities(Data("{}".utf8), statusCode: nil))
    }

    // Without a configured client id, connect explains instead of opening a login.
    @MainActor func testConnectWithoutClientIDExplains() async {
        let service = StravaService(defaults: UserDefaults(suiteName: "StravaTests.\(UUID().uuidString)")!)
        XCTAssertFalse(service.isConfigured)
        await service.connect()
        XCTAssertEqual(service.lastError, "Strava isn't set up yet.")
        XCTAssertFalse(service.isConnected)
    }

    // Not connected → no network call, just an empty list.
    @MainActor func testFetchActivitiesWhenNotConnectedReturnsEmpty() async throws {
        let service = StravaService(defaults: UserDefaults(suiteName: "StravaTests.\(UUID().uuidString)")!)
        let workouts = try await service.fetchActivities()
        XCTAssertEqual(workouts, [])
    }
}
