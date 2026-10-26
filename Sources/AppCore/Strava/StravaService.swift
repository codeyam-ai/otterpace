import Foundation
#if os(iOS)
import AuthenticationServices
import UIKit
#endif

// MARK: - Strava connect + import (optional data source, M5)
//
// "Connect Strava" lets the user import their runs/rides as an alternative to
// Apple Health. Strava OAuth needs the client secret to exchange/refresh tokens,
// so that happens server-side (Vercel `/api/strava/*`); the tokens are stored in
// Supabase keyed by an anonymous device key and NEVER touch the device. The app:
//   1. generates a random device key (Keychain),
//   2. runs the OAuth web flow (ASWebAuthenticationSession) to get a code,
//   3. POSTs {code, deviceKey} to /api/strava/exchange,
//   4. later GETs /api/strava/activities?deviceKey=… for mapped runs.
//
// The app's Strava client_id (public, safe to ship) comes from Info.plist
// `StravaClientID`; with none set, the feature shows as "not configured".

public enum StravaConfig {
    public static let apiBase = URL(string: "https://otterpace.com/api")!
    public static let deviceKeyAccount = "otterpace-strava-device-key"
    public static let connectedDefaultsKey = "otterpaceStravaConnected"
    public static let callbackScheme = "otterpace"
    public static let redirectURI = "https://otterpace.com/api/strava/callback"
    public static let scope = "read,activity:read"

    public static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "StravaClientID") as? String) ?? ""
    }
}

enum StravaError: Error { case notConfigured, cancelled, failed }

/// Random per-install identifier used to key the user's Strava tokens server-side.
/// No PII — just a UUID in the Keychain (reusing the `TokenStoring` seam).
struct StravaDeviceKey {
    private let store: TokenStoring
    init(store: TokenStoring = KeychainTokenStore()) { self.store = store }

    func current() -> String {
        if let k = store.read(StravaConfig.deviceKeyAccount), !k.isEmpty { return k }
        let k = UUID().uuidString
        store.save(k, account: StravaConfig.deviceKeyAccount)
        return k
    }
    func clear() { store.delete(StravaConfig.deviceKeyAccount) }
}

@MainActor
public final class StravaService: NSObject, ObservableObject {
    @Published public private(set) var isConnected: Bool
    @Published public var isWorking = false
    @Published public var lastError: String?

    private let deviceKey = StravaDeviceKey()
    private let defaults: UserDefaults

    #if os(iOS)
    /// Held for the lifetime of the OAuth flow so ARC can't deallocate the session
    /// mid-login (which would hang the continuation forever). Overwritten next connect.
    private var authSession: ASWebAuthenticationSession?
    #endif

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isConnected = defaults.bool(forKey: StravaConfig.connectedDefaultsKey)
        super.init()
    }

    /// Whether a Strava client_id is configured (Info.plist `StravaClientID`).
    public var isConfigured: Bool { !StravaConfig.clientID.isEmpty }

    /// Run the OAuth web flow and exchange the code for server-stored tokens.
    public func connect() async {
        guard isConfigured else { lastError = "Strava isn't set up yet."; return }
        isWorking = true; lastError = nil
        defer { isWorking = false }
        do {
            let key = deviceKey.current()
            let code = try await authorize(deviceKey: key)
            _ = try await post("strava/exchange", body: ["code": code, "deviceKey": key])
            defaults.set(true, forKey: StravaConfig.connectedDefaultsKey)
            isConnected = true
        } catch StravaError.cancelled {
            // user backed out — no error to show
        } catch {
            lastError = "Couldn't connect to Strava. Please try again."
        }
    }

    public func disconnect() async {
        let key = deviceKey.current()
        _ = try? await post("strava/disconnect", body: ["deviceKey": key])
        deviceKey.clear()
        defaults.set(false, forKey: StravaConfig.connectedDefaultsKey)
        isConnected = false
    }

    /// Fetch imported activities from the backend proxy, mapped to `LatestWorkout`.
    /// The device key rides in the `x-device-key` header (never the query string)
    /// so it stays out of any proxy/CDN access logs.
    ///
    /// Throws on a real failure (network/non-200/decode) so the caller can tell
    /// "connected but the import failed" apart from "connected with no activities
    /// yet" — the latter is a legitimate empty array, not an error. A not-connected
    /// service returns [] without a network call.
    public func fetchActivities() async throws -> [LatestWorkout] {
        guard isConnected else { return [] }
        var request = URLRequest(url: StravaConfig.apiBase.appendingPathComponent("strava/activities"))
        request.setValue(deviceKey.current(), forHTTPHeaderField: "x-device-key")
        let (data, resp) = try await URLSession.shared.data(for: request)
        return try Self.decodeActivities(data, statusCode: (resp as? HTTPURLResponse)?.statusCode)
    }

    /// Map the backend's activities response to `LatestWorkout`s. Anything but a
    /// 200 is a real failure — distinct from a legitimate empty list.
    nonisolated static func decodeActivities(_ data: Data, statusCode: Int?) throws -> [LatestWorkout] {
        try requireOK(statusCode)
        return try JSONDecoder().decode(ActivitiesResponse.self, from: data).activities.map { $0.workout }
    }

    nonisolated static func requireOK(_ statusCode: Int?) throws {
        guard statusCode == 200 else { throw StravaError.failed }
    }

    // MARK: Networking

    @discardableResult
    private func post(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: StravaConfig.apiBase.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: request)
        try Self.requireOK((resp as? HTTPURLResponse)?.statusCode)
        return data
    }

    // MARK: OAuth URL handling (platform-free, so it unit-tests on macOS)

    /// Strava's authorize page for this install. `state` carries the device key
    /// so the server-side callback can pair the code with it.
    nonisolated static func authorizeURL(clientID: String, deviceKey: String) -> URL? {
        var comps = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: StravaConfig.redirectURI),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: StravaConfig.scope),
            .init(name: "state", value: deviceKey),
        ]
        return comps.url
    }

    /// The OAuth `code` from the app's callback URL, or nil when it's missing or
    /// empty (e.g. the user denied access and Strava sent `error=` instead).
    nonisolated static func authorizationCode(from callbackURL: URL?) -> String? {
        guard let callbackURL,
              let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty
        else { return nil }
        return code
    }

    private struct ActivitiesResponse: Decodable {
        let connected: Bool
        let activities: [WorkoutDTO]
    }
    private struct WorkoutDTO: Decodable {
        let type: String; let distanceMiles: Double; let durationMinutes: Int
        let pace: String; let date: String; let source: String
        var workout: LatestWorkout {
            LatestWorkout(type: type, distanceMiles: distanceMiles, durationMinutes: durationMinutes,
                          pace: pace, date: date, source: source)
        }
    }

    // MARK: OAuth (iOS only)

    #if os(iOS)
    private func authorize(deviceKey: String) async throws -> String {
        guard let authURL = Self.authorizeURL(clientID: StravaConfig.clientID, deviceKey: deviceKey) else {
            throw StravaError.failed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL, callbackURLScheme: StravaConfig.callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: StravaError.cancelled)
                    } else {
                        continuation.resume(throwing: StravaError.failed)
                    }
                    return
                }
                guard let code = Self.authorizationCode(from: callbackURL) else {
                    continuation.resume(throwing: StravaError.failed); return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session  // retain for the flow's lifetime (else ARC can hang the login)
            if !session.start() { continuation.resume(throwing: StravaError.failed) }
        }
    }
    #else
    private func authorize(deviceKey: String) async throws -> String { throw StravaError.notConfigured }
    #endif
}

#if os(iOS)
extension StravaService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif
