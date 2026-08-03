import Foundation

// MARK: - Remote AI coach (Milestone 3)
//
// The real-LLM coach. When the user has connected their own API key — from
// Anthropic, OpenAI, or Gemini — `AskCoachView` calls this instead of the
// deterministic `CoachEngine` mock. The shape is intentionally identical to
// `CoachEngine.reply` — same `CoachReply` out — so the rest of the app doesn't
// care which coach answered, or which provider answered it.
//
// Architecture (the "BYO key, proxied through a backend" model):
//   app  ──{question, TodayState, x-ai-provider, x-ai-key}──▶  otterpace.com/api/coach
//                                                          │ (Vercel function,
//                                                          │  curated prompt +
//                                                          │  safety rules,
//                                                          │  routes per provider)
//                                                          ▼
//                                             Anthropic / OpenAI / Gemini
// The key is sent per request and never stored on the server. The coaching
// prompt and safety logic live in the backend (see `api/coach.ts`), so they can
// be tuned without an app release and stay identical across providers — the
// provider changes who generates the words, never the coaching or the safety
// rules. If there's no key, or the call fails, the caller falls back to
// `CoachEngine` — so the coach always works offline.

/// The coach endpoints, and the scenario/preference keys the coach reads. Kept in
/// one place so the host can change without touching call sites.
public enum CoachConfig {
    /// The backend coach proxy. Co-located with the marketing site on Vercel.
    public static let endpoint = URL(string: "https://otterpace.com/api/coach")!
    /// Import a race from a URL (page -> structured race). Same host + BYO key.
    public static let raceImportEndpoint = URL(string: "https://otterpace.com/api/race-import")!
    /// Search for races by name (name -> candidate list). Same host + BYO key.
    public static let raceSearchEndpoint = URL(string: "https://otterpace.com/api/race-search")!

    /// UserDefaults key remembering which connected provider the user picked.
    /// Only the choice lives here; every key value stays in the Keychain.
    public static let activeProviderKey = "coachActiveProvider"

    // Scenario-only seed hooks. A simulator capture cannot hold a real Keychain
    // key, so a scenario declares the connection *shape* through these
    // UserDefaults keys and `CoachKeyStore` reports it. Production never carries
    // them, so they are inert outside a capture.

    /// Comma-separated provider raw values that should appear connected,
    /// e.g. "anthropic,openai". Seeded as `rbCoachConnectedProviders`.
    public static let seedConnectedProvidersKey = "rbCoachConnectedProviders"
    /// Which seeded provider is active, e.g. "openai". Seeded as `rbCoachActiveProvider`.
    public static let seedActiveProviderKey = "rbCoachActiveProvider"
    /// The original single-provider hook, still honored: true means "Anthropic
    /// connected and active" so every scenario written before multi-provider
    /// support keeps capturing the same frame.
    public static let seedConnectedKey = "rbCoachConnected"
}

/// Stores the user's own provider keys in the Keychain — one account per
/// provider — and remembers which one is active. Reuses the same `TokenStoring`
/// seam the Apple sign-in identifier uses, so tests inject an in-memory store
/// while production uses `KeychainTokenStore`.
///
/// Several providers may be connected at once. Exactly one is active, and only a
/// connected provider can be: `activeProvider` falls back to the first connected
/// provider whenever the remembered choice is gone, which is what makes
/// disconnecting the active provider promote another instead of dropping the
/// user to the offline coach.
///
/// Migration from the single-key era is a no-op by construction — `.anthropic`
/// still reads the original `coach-anthropic-key` account, so an existing key is
/// already connected and (being the only one) already active.
public struct CoachKeyStore {
    private let store: TokenStoring
    private let defaults: UserDefaults

    public init(store: TokenStoring = KeychainTokenStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    // MARK: Reading

    /// The stored key for one provider, or nil if none is connected.
    public func key(for provider: CoachProvider) -> String? {
        guard let k = store.read(provider.keyAccount), !k.isEmpty else { return nil }
        return k
    }

    /// Whether this specific provider has a key. Honors a scenario seed when one
    /// is present, so a capture can show a connected row without a real key.
    public func isConnected(_ provider: CoachProvider) -> Bool {
        if let seeded = seededConnectedProviders { return seeded.contains(provider) }
        return key(for: provider) != nil
    }

    /// Every connected provider, in stable display order.
    public var connectedProviders: [CoachProvider] {
        CoachProvider.displayOrder.filter { isConnected($0) }
    }

    /// Whether a real-LLM coach is available at all (any provider connected).
    public var isConnected: Bool { !connectedProviders.isEmpty }

    /// The provider Buddy currently uses: the user's remembered choice when it is
    /// still connected, otherwise the first connected provider, otherwise nil.
    public var activeProvider: CoachProvider? {
        let connected = connectedProviders
        guard !connected.isEmpty else { return nil }
        if let seededActive, connected.contains(seededActive) { return seededActive }
        if let raw = defaults.string(forKey: CoachConfig.activeProviderKey),
           let remembered = CoachProvider(rawValue: raw),
           connected.contains(remembered) {
            return remembered
        }
        return connected.first
    }

    /// The key to send with a coach request, or nil when nothing is connected.
    /// Nil under a scenario seed (there is no real key to send), which correctly
    /// leaves a captured conversation on the deterministic `CoachEngine`.
    public var activeKey: String? {
        guard let provider = activeProvider else { return nil }
        return key(for: provider)
    }

    // MARK: Writing

    /// Store a key for an explicitly chosen provider and make it active.
    public func save(_ key: String, for provider: CoachProvider) {
        store.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: provider.keyAccount)
        setActive(provider)
    }

    /// Store a pasted key, recognizing its provider from its shape. Returns the
    /// provider it was filed under, or nil when the shape matches none — in which
    /// case nothing is saved and the caller asks the user to pick.
    @discardableResult
    public func save(_ key: String) -> CoachProvider? {
        guard let provider = CoachProvider.detect(fromKey: key) else { return nil }
        save(key, for: provider)
        return provider
    }

    /// Switch which connected provider Buddy uses.
    public func setActive(_ provider: CoachProvider) {
        defaults.set(provider.rawValue, forKey: CoachConfig.activeProviderKey)
    }

    /// Disconnect one provider. If it was active, `activeProvider` promotes
    /// another connected provider on the next read.
    public func clear(_ provider: CoachProvider) {
        store.delete(provider.keyAccount)
        if defaults.string(forKey: CoachConfig.activeProviderKey) == provider.rawValue {
            defaults.removeObject(forKey: CoachConfig.activeProviderKey)
        }
    }

    /// Disconnect every provider.
    public func clear() {
        for provider in CoachProvider.allCases { store.delete(provider.keyAccount) }
        defaults.removeObject(forKey: CoachConfig.activeProviderKey)
    }

    // MARK: Scenario seeding

    /// The connection shape a scenario declared, or nil when none did (production).
    private var seededConnectedProviders: Set<CoachProvider>? {
        if let raw = defaults.string(forKey: CoachConfig.seedConnectedProvidersKey), !raw.isEmpty {
            let providers = raw.split(separator: ",")
                .compactMap { CoachProvider(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
            return Set(providers)
        }
        // The pre-multi-provider hook: a plain bool meaning "Anthropic connected".
        // Only an explicitly present key counts, so an absent key stays production.
        if defaults.object(forKey: CoachConfig.seedConnectedKey) != nil {
            return defaults.bool(forKey: CoachConfig.seedConnectedKey) ? [.anthropic] : []
        }
        return nil
    }

    /// The active provider a scenario declared, if any.
    private var seededActive: CoachProvider? {
        guard let raw = defaults.string(forKey: CoachConfig.seedActiveProviderKey), !raw.isEmpty else { return nil }
        return CoachProvider(rawValue: raw)
    }
}

/// The BYO-key headers every coach-backed request carries. One place, because
/// `RemoteCoach` and `RaceImportClient` must stay byte-identical here — a
/// mismatch would authenticate one feature and 400 the other.
public enum CoachRequestHeaders {
    /// Names the provider and carries the key. Both are read by the backend's
    /// shared LLM router.
    public static let provider = "x-ai-provider"
    public static let key = "x-ai-key"
    /// The original Anthropic-only header. Still sent for Anthropic keys so an
    /// app build that ships ahead of the backend keeps working, and still
    /// accepted by the backend so an older installed app keeps working. Neither
    /// side can be upgraded atomically, so compatibility runs both ways.
    public static let legacyAnthropicKey = "x-anthropic-key"

    public static func apply(provider: CoachProvider, apiKey: String, to request: inout URLRequest) {
        request.setValue(provider.rawValue, forHTTPHeaderField: Self.provider)
        request.setValue(apiKey, forHTTPHeaderField: key)
        if provider == .anthropic {
            request.setValue(apiKey, forHTTPHeaderField: legacyAnthropicKey)
        }
    }
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

    /// The context actually put on the wire. The journal is projected down to its
    /// bounded recent slice here — at the single point where the payload leaves
    /// the device — so an unbounded diary can never push `loadHistory` out of the
    /// backend's 16 KB `MAX_CONTEXT_BYTES` cap and quietly degrade the coaching
    /// this feature exists to improve. Every other field passes through untouched.
    func bounded(_ context: TodayState) -> TodayState {
        guard !context.journal.isEmpty else { return context }
        var out = context
        out.journal = Journal.coachSlice(context.journal, asOf: context.date)
        return out
    }

    /// Ask the real coach. Throws `CoachError` so the caller can decide whether to
    /// fall back to `CoachEngine` (network/server) or surface the problem (bad key).
    /// `history` is the recent conversation (oldest first); pass it so the model
    /// builds on the exchange instead of answering each message from scratch.
    public func reply(to question: String,
                      context: TodayState,
                      history: [CoachTurn] = [],
                      apiKey: String,
                      provider: CoachProvider = .anthropic) async throws -> CoachReply {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        CoachRequestHeaders.apply(provider: provider, apiKey: apiKey, to: &request)
        do {
            let turns = history.map { Turn(role: $0.role.rawValue, text: $0.text) }
            request.httpBody = try JSONEncoder().encode(
                RequestBody(question: question, context: bounded(context), history: turns))
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
