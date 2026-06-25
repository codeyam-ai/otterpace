import Foundation

// MARK: - Live HTTP transport for account sync
//
// Talks to the Vercel functions under /api/account/* (same host as the Strava
// proxy). Each stream is a tiny JSON contract:
//
//   GET  /api/account/sync?userId=…           → { found, prefs, updated_at }
//   PUT  /api/account/sync   { userId, prefs, updatedAt }
//   GET  /api/account/health?userId=…         → { found, health, updated_at }
//   PUT  /api/account/health { userId, health, updatedAt }
//   DELETE /api/account/health { userId }
//
// All failures throw; `AccountSyncService` swallows them so local data stays the
// source of truth offline.
public enum AccountSyncConfig {
    public static let apiBase = URL(string: "https://otterpace.com/api")!
}

public struct URLSessionAccountSyncTransport: AccountSyncTransport {
    private let session: URLSession
    private let base: URL

    public init(session: URLSession = .shared, base: URL = AccountSyncConfig.apiBase) {
        self.session = session
        self.base = base
    }

    public func fetchPrefs(userID: String) async throws -> TimestampedPayload<SyncablePreferences>? {
        try await fetch(path: "account/sync", userID: userID, field: "prefs", as: SyncablePreferences.self)
    }

    public func pushPrefs(userID: String, payload: SyncablePreferences, updatedAt: Date) async throws {
        try await put(path: "account/sync", body: [
            "userId": userID,
            "prefs": try jsonObject(payload),
            "updatedAt": iso(updatedAt),
        ])
    }

    public func fetchHealth(userID: String) async throws -> TimestampedPayload<SyncableHealthSnapshot>? {
        try await fetch(path: "account/health", userID: userID, field: "health", as: SyncableHealthSnapshot.self)
    }

    public func pushHealth(userID: String, payload: SyncableHealthSnapshot, updatedAt: Date) async throws {
        try await put(path: "account/health", body: [
            "userId": userID,
            "health": try jsonObject(payload),
            "updatedAt": iso(updatedAt),
        ])
    }

    public func deleteHealth(userID: String) async throws {
        var request = URLRequest(url: base.appendingPathComponent("account/health"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["userId": userID])
        let (_, resp) = try await session.data(for: request)
        try Self.check(resp)
    }

    // MARK: Helpers

    private func fetch<T: Decodable>(path: String, userID: String, field: String, as: T.Type) async throws -> TimestampedPayload<T>? {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "userId", value: userID)]
        guard let url = comps?.url else { return nil }
        let (data, resp) = try await session.data(from: url)
        try Self.check(resp)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["found"] as? Bool) == true,
              let payload = obj[field],
              let updatedAtString = obj["updated_at"] as? String,
              let updatedAt = Self.parseISO(updatedAtString)
        else { return nil }
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let value = try JSONDecoder().decode(T.self, from: payloadData)
        return TimestampedPayload(value: value, updatedAt: updatedAt)
    }

    private func put(path: String, body: [String: Any]) async throws {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await session.data(for: request)
        try Self.check(resp)
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private static func check(_ resp: URLResponse) throws {
        guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            throw URLError(.badServerResponse)
        }
    }
}
