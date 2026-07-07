import Foundation

// MARK: - Race import & search clients (Milestone 5 adjacent)
//
// Two thin clients over the same "BYO key, proxied through a backend" model as
// `RemoteCoach`: the user's Anthropic key (from `CoachKeyStore`) is sent per
// request in the `x-anthropic-key` header and never stored on the server. Both
// produce a partially-filled race the app opens in `RaceEditorView` for the user
// to confirm and save — we never auto-save a machine-extracted race.
//
//   RaceImportClient.importRace(from:)  URL   -> RaceImportResult (one race + hints)
//   RaceImportClient.searchRaces(query:) name -> [RaceSearchResult] (candidates)
//
// Errors reuse `CoachError` so callers can degrade the same way `AskCoachView`
// does: on no key or any failure, fall back to manual entry.

/// A race parsed from the web with every field optional — a sparse page may yield
/// only some. Maps to a `RaceGoal` (filling sensible defaults) for the editor.
public struct RaceDraft: Codable, Equatable {
    public var name: String?
    public var date: String?          // yyyy-MM-dd
    public var distanceMiles: Double?
    public var unit: DistanceUnit?
    public var location: String?
    public var notes: String?

    public init(name: String? = nil, date: String? = nil, distanceMiles: Double? = nil,
                unit: DistanceUnit? = nil, location: String? = nil, notes: String? = nil) {
        self.name = name
        self.date = date
        self.distanceMiles = distanceMiles
        self.unit = unit
        self.location = location
        self.notes = notes
    }

    /// A `RaceGoal` seed for the editor: missing name becomes empty (the editor's
    /// Save stays disabled until the user types one), missing distance falls back
    /// to the Half preset so a valid capsule is selected. The returned goal is a
    /// draft — a fresh id is minted on save, so importing never overwrites a race.
    public var asRaceGoalSeed: RaceGoal {
        RaceGoal(
            name: name ?? "",
            distanceMiles: distanceMiles ?? RaceDistance.half.miles,
            date: date ?? "",
            location: location ?? "",
            notes: (notes?.isEmpty == false) ? notes : nil,
            unit: unit
        )
    }
}

/// The import endpoint's reply: the extracted race plus hints the editor uses to
/// flag fields the user should double-check.
public struct RaceImportResult: Codable, Equatable {
    public var race: RaceDraft
    public var confidence: Double
    public var missingFields: [String]

    public init(race: RaceDraft, confidence: Double = 0, missingFields: [String] = []) {
        self.race = race
        self.confidence = confidence
        self.missingFields = missingFields
    }
}

/// One search candidate. Carries a best-effort `sourceUrl` so the user can open it
/// or re-import full detail via `importRace`.
public struct RaceSearchResult: Codable, Equatable, Identifiable {
    public var name: String
    public var date: String?
    public var distanceMiles: Double?
    public var unit: DistanceUnit?
    public var location: String?
    public var sourceUrl: String?

    // Identity for SwiftUI lists: name + date is stable within a result set and
    // avoids needing a server-provided id.
    public var id: String { "\(name)|\(date ?? "")|\(location ?? "")" }

    public var asDraft: RaceDraft {
        RaceDraft(name: name, date: date, distanceMiles: distanceMiles, unit: unit, location: location)
    }
}

/// Calls the backend race-import / race-search proxies. Stateless; construct per use.
public struct RaceImportClient {
    private let importEndpoint: URL
    private let searchEndpoint: URL
    private let session: URLSession

    public init(importEndpoint: URL = CoachConfig.raceImportEndpoint,
                searchEndpoint: URL = CoachConfig.raceSearchEndpoint,
                session: URLSession = .shared) {
        self.importEndpoint = importEndpoint
        self.searchEndpoint = searchEndpoint
        self.session = session
    }

    private struct ImportBody: Encodable { let url: String }
    private struct SearchBody: Encodable { let query: String }
    private struct SearchResponse: Decodable { let results: [RaceSearchResult] }

    /// Import a race from a web page. Throws `CoachError` so the caller can fall
    /// back to manual entry (network/server) or surface a bad key (invalidKey).
    public func importRace(from url: String, apiKey: String) async throws -> RaceImportResult {
        let data = try await post(to: importEndpoint, body: ImportBody(url: url), apiKey: apiKey)
        guard let decoded = try? JSONDecoder().decode(RaceImportResult.self, from: data) else {
            throw CoachError.server
        }
        return decoded
    }

    /// Search races by name. Returns candidates (possibly empty); throws on failure.
    public func searchRaces(query: String, apiKey: String) async throws -> [RaceSearchResult] {
        let data = try await post(to: searchEndpoint, body: SearchBody(query: query), apiKey: apiKey)
        guard let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
            throw CoachError.server
        }
        return decoded.results
    }

    /// Shared POST: JSON body + BYO key header, mapping status codes to `CoachError`
    /// exactly like `RemoteCoach` (only a rejected key surfaces to the user).
    private func post<Body: Encodable>(to endpoint: URL, body: Body, apiKey: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-anthropic-key")
        do {
            request.httpBody = try JSONEncoder().encode(body)
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
        case 200: return data
        case 401: throw CoachError.invalidKey
        case 429: throw CoachError.rateLimited
        default: throw CoachError.server
        }
    }
}
