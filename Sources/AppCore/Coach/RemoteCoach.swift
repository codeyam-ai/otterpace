import Foundation

// MARK: - Remote AI coach (Milestone 3)
//
// The real-LLM coach. When the user has connected their own Anthropic API key,
// `AskCoachView` calls this instead of the deterministic `CoachEngine` mock. The
// shape is intentionally identical to `CoachEngine.reply` — same `CoachReply` out
// — so the rest of the app doesn't care which coach answered.
//
// Architecture (the "BYO key, proxied through a backend" model):
//   app  ──{question, TodayState, x-anthropic-key}──▶  otterpace.com/api/coach
//                                                          │ (Vercel function,
//                                                          │  curated prompt +
//                                                          │  safety rules)
//                                                          ▼
//                                                       Anthropic
// The key is sent per request and never stored on the server. The coaching
// prompt and safety logic live in the backend (see `api/coach.ts`), so they can
// be tuned without an app release. If there's no key, or the call fails, the
// caller falls back to `CoachEngine` — so the coach always works offline.

/// Where the BYO Anthropic key lives, and the coach endpoint. Kept in one place
/// so the rename/host can change without touching call sites.
public enum CoachConfig {
    /// Keychain account for the user's Anthropic key (stored via `TokenStoring`).
    public static let keyAccount = "coach-anthropic-key"
    /// The backend coach proxy. Co-located with the marketing site on Vercel.
    public static let endpoint = URL(string: "https://otterpace.com/api/coach")!
    /// Import a race from a URL (page -> structured race). Same host + BYO key.
    public static let raceImportEndpoint = URL(string: "https://otterpace.com/api/race-import")!
    /// Search for races by name (name -> candidate list). Same host + BYO key.
    public static let raceSearchEndpoint = URL(string: "https://otterpace.com/api/race-search")!
}

/// Stores the user's own Anthropic key in the Keychain (reusing the same
/// `TokenStoring` seam the Apple sign-in identifier uses). Tests inject an
/// in-memory store; production uses `KeychainTokenStore`.
public struct CoachKeyStore {
    private let store: TokenStoring

    public init(store: TokenStoring = KeychainTokenStore()) {
        self.store = store
    }

    /// The stored key, or nil if the user hasn't connected one.
    public var key: String? {
        guard let k = store.read(CoachConfig.keyAccount), !k.isEmpty else { return nil }
        return k
    }

    /// Whether a real-LLM coach is available (a key is connected).
    public var isConnected: Bool { key != nil }

    public func save(_ key: String) {
        store.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: CoachConfig.keyAccount)
    }

    public func clear() { store.delete(CoachConfig.keyAccount) }
}

/// Failures the chat surfaces differently — a bad key is worth telling the user
/// about; a transient network error just falls back to the mock silently.
public enum CoachError: Error, Equatable {
    case invalidKey
    case rateLimited
    case server
    case network
}

/// Calls the backend coach proxy. Stateless; safe to construct per request.
public struct RemoteCoach {
    private let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL = CoachConfig.endpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    /// One prior turn on the wire. Mirrors `CoachTurn` (role + text only) — the
    /// backend rebuilds these into a real multi-turn conversation so the model
    /// can see what it already said and stop repeating itself.
    private struct Turn: Encodable {
        let role: String   // "user" | "coach" (backend maps coach -> assistant)
        let text: String
    }

    private struct RequestBody: Encodable {
        let question: String
        let context: TodayState
        let history: [Turn]
    }

    private struct ResponseBody: Decodable {
        let text: String
        let mood: String
        let safetyFlag: Bool
    }

    /// Ask the real coach. Throws `CoachError` so the caller can decide whether to
    /// fall back to `CoachEngine` (network/server) or surface the problem (bad key).
    /// `history` is the recent conversation (oldest first); pass it so the model
    /// builds on the exchange instead of answering each message from scratch.
    public func reply(to question: String, context: TodayState, history: [CoachTurn] = [], apiKey: String) async throws -> CoachReply {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-anthropic-key")
        do {
            let turns = history.map { Turn(role: $0.role.rawValue, text: $0.text) }
            request.httpBody = try JSONEncoder().encode(RequestBody(question: question, context: context, history: turns))
        } catch {
            throw CoachError.server
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CoachError.network
        }

        guard let http = response as? HTTPURLResponse else { throw CoachError.network }
        switch http.statusCode {
        case 200: break
        case 401: throw CoachError.invalidKey  // only a rejected key surfaces to the user; a 400 (bad request) is our bug, not theirs
        case 429: throw CoachError.rateLimited
        default: throw CoachError.server
        }

        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw CoachError.server
        }
        // Reuse the mock's keyword classifier for the internal intent tag; the
        // backend owns the prose, mood, and safety call.
        return CoachReply(
            intent: CoachIntent.classify(question),
            text: decoded.text,
            mood: BuddyMood(raw: decoded.mood),
            safetyFlag: decoded.safetyFlag
        )
    }
}
