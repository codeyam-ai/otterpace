import Foundation

// MARK: - Push registration service (opt-in, signed-in only)
//
// Registers this device's APNs token against the user's persistent backend
// session so the server-driven movement nudge can reach them, and deregisters it
// on sign-out / health-sync-off / account deletion. Best-effort by design: any
// failure just leaves server push off and the app fully functional (the on-device
// nudge from the prerequisite plan remains the fallback).
//
// Auth mirrors `URLSessionAccountSyncTransport`: the bearer session token is
// attached to every request and the user is resolved server-side — the client
// never sends a userId. Injectable `URLSession` + token provider so the gating
// and request shape are unit-testable without a backend or a real device token.

public final class PushRegistrationService {
    private let session: URLSession
    private let base: URL
    private let tokenProvider: () -> String?

    public init(session: URLSession = .shared,
                base: URL = AccountSyncConfig.apiBase,
                tokenProvider: @escaping () -> String? = { AccountSessionStore().token() }) {
        self.session = session
        self.base = base
        self.tokenProvider = tokenProvider
    }

    /// Register the device token. No-op (returns false) when there's no bearer
    /// session — server push is strictly opt-in and account-backed, so an
    /// unauthenticated device never registers a token.
    @discardableResult
    public func register(deviceToken: String, platform: String = "ios") async -> Bool {
        await send(method: "POST", body: ["deviceToken": deviceToken, "platform": platform])
    }

    /// Deregister one device token. A missing session is a no-op; failures are swallowed.
    @discardableResult
    public func deregister(deviceToken: String) async -> Bool {
        await send(method: "DELETE", body: ["deviceToken": deviceToken])
    }

    /// Deregister EVERY token for this user — the sign-out / health-off / delete-
    /// account opt-out, where the exact device token may not be to hand. The
    /// backend drops the whole push row, so no further server nudge is sent.
    @discardableResult
    public func deregisterAll() async -> Bool {
        await send(method: "DELETE", body: [:])
    }

    private func send(method: String, body: [String: Any]) async -> Bool {
        guard let token = tokenProvider() else { return false } // no session → opt-in gate holds
        var request = URLRequest(url: base.appendingPathComponent("account/push"))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, resp) = try? await session.data(for: request),
              let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code)
        else { return false }
        return true
    }
}

// MARK: - Double-nudge de-dup gate

/// Decides whether the server-driven nudge is active for this user, in which case
/// the app suppresses the *local* inactivity notification so the user gets exactly
/// one nudge, not two. Pure so the policy is unit-tested; the app consults it
/// before arming the local reminder. Server push is only ever active when the
/// user is signed in AND health sync is on AND a device token is registered — the
/// same three-way opt-in gate the backend enforces; if any drops, the local nudge
/// (from the prerequisite plan) takes back over.
public enum ServerPushGate {
    public static func suppressesLocalNudge(signedIn: Bool, healthSyncEnabled: Bool, pushRegistered: Bool) -> Bool {
        signedIn && healthSyncEnabled && pushRegistered
    }
}
