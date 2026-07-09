import Foundation

// MARK: - Account sync service (optional, signed-in only)
//
// For a `signedIn` user, mirrors whichever streams are enabled to the Supabase
// backend (api/account/*), keyed to the stable Apple userID, so settings — and,
// only if the user opts in, a health snapshot — survive reinstalls and devices:
//
//   • settings/preferences — always available behind the "Sync my settings" opt-in.
//   • health/activity      — pushed ONLY when the separate health opt-in is on
//                            (which itself requires prior consent). Hard-gated
//                            here, not just in the UI.
//
// Local values stay the source of truth: network failures are non-fatal and
// merges are last-write-wins on `updatedAt`. The HTTP seam (`AccountSyncTransport`)
// is injectable so the gating + merge logic is unit-testable without a backend.

/// The two payloads that can sync. Kept small + Codable for clean round-trips.
public struct SyncablePreferences: Codable, Equatable {
    public var goalSteps: Int
    public init(goalSteps: Int) { self.goalSteps = goalSteps }
}

public struct SyncableHealthSnapshot: Codable, Equatable {
    public var steps: Int
    public var distanceMiles: Double
    public var activeMinutes: Int
    public var activeEnergyKcal: Int
    /// Movement heartbeat for the opt-in server-driven nudge: the ISO timestamp of
    /// the user's last real movement and their inactivity setting. Optional so a
    /// snapshot without them round-trips unchanged (and existing callers/tests are
    /// unaffected); the backend mirrors them onto the push row when present.
    public var lastMovementAt: String?
    public var inactivityHours: Int?

    public init(steps: Int, distanceMiles: Double, activeMinutes: Int, activeEnergyKcal: Int,
                lastMovementAt: String? = nil, inactivityHours: Int? = nil) {
        self.steps = steps
        self.distanceMiles = distanceMiles
        self.activeMinutes = activeMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.lastMovementAt = lastMovementAt
        self.inactivityHours = inactivityHours
    }
}

/// A payload paired with the timestamp the remote recorded for it.
public struct TimestampedPayload<T> {
    public let value: T
    public let updatedAt: Date
    public init(value: T, updatedAt: Date) {
        self.value = value
        self.updatedAt = updatedAt
    }
}

// MARK: Pure merge (last-write-wins)

public struct SyncResolution<T: Equatable> {
    public let winner: T
    public let shouldPush: Bool   // local is authoritative — upload it
    public let shouldAdopt: Bool  // remote is authoritative — adopt it locally
}

public enum SyncMerge {
    /// Last-write-wins reconciliation of a local value against an optional remote
    /// one. Pure and side-effect-free so it can be unit-tested directly:
    ///   • no remote                → local wins, push it.
    ///   • remote newer than local  → remote wins, adopt it.
    ///   • local newer (or equal)   → local wins; push only if the values differ.
    public static func resolve<T: Equatable>(
        local: T,
        localUpdatedAt: Date,
        remote: T?,
        remoteUpdatedAt: Date?
    ) -> SyncResolution<T> {
        guard let remote, let remoteUpdatedAt else {
            return SyncResolution(winner: local, shouldPush: true, shouldAdopt: false)
        }
        if remoteUpdatedAt > localUpdatedAt {
            return SyncResolution(winner: remote, shouldPush: false, shouldAdopt: true)
        }
        return SyncResolution(winner: local, shouldPush: local != remote, shouldAdopt: false)
    }
}

// MARK: Transport seam

public protocol AccountSyncTransport {
    func fetchPrefs(userID: String) async throws -> TimestampedPayload<SyncablePreferences>?
    func pushPrefs(userID: String, payload: SyncablePreferences, updatedAt: Date) async throws
    func fetchHealth(userID: String) async throws -> TimestampedPayload<SyncableHealthSnapshot>?
    func pushHealth(userID: String, payload: SyncableHealthSnapshot, updatedAt: Date) async throws
    func deleteHealth(userID: String) async throws
}

// MARK: Service

public final class AccountSyncService {
    private let transport: AccountSyncTransport
    private let consent: SyncConsentStore

    public init(transport: AccountSyncTransport = URLSessionAccountSyncTransport(),
                consent: SyncConsentStore = SyncConsentStore()) {
        self.transport = transport
        self.consent = consent
    }

    /// Only signed-in users have a sync identity; everyone else is purely local.
    private func userID(for state: SessionState) -> String? {
        if case let .signedIn(userID) = state { return userID }
        return nil
    }

    // MARK: Preferences (settings opt-in)

    /// Push local preferences if settings sync is on and the user is signed in.
    /// A guest, or a signed-in user with the toggle off, is a no-op.
    public func pushPreferences(_ prefs: SyncablePreferences, session: SessionState, now: Date = Date()) async {
        guard let userID = userID(for: session), consent.settingsSyncEnabled else { return }
        try? await transport.pushPrefs(userID: userID, payload: prefs, updatedAt: now)
    }

    /// Pull remote preferences and reconcile against local (last-write-wins),
    /// returning the value the app should now use. Offline / not-enabled / guest
    /// all return `local` unchanged. When local wins and differs, re-push it.
    public func reconcilePreferences(local: SyncablePreferences, localUpdatedAt: Date, session: SessionState) async -> SyncablePreferences {
        guard let userID = userID(for: session), consent.settingsSyncEnabled else { return local }
        let remote = (try? await transport.fetchPrefs(userID: userID)) ?? nil
        let res = SyncMerge.resolve(local: local, localUpdatedAt: localUpdatedAt,
                                    remote: remote?.value, remoteUpdatedAt: remote?.updatedAt)
        if res.shouldPush {
            try? await transport.pushPrefs(userID: userID, payload: local, updatedAt: localUpdatedAt)
        }
        return res.winner
    }

    // MARK: Health (separate opt-in, off by default)

    /// Push a health snapshot — HARD-GATED on the health opt-in. Even a signed-in
    /// user never uploads health data unless `healthSyncEnabled` is on (which
    /// itself required consent). This is the single chokepoint for health upload.
    public func pushHealth(_ snapshot: SyncableHealthSnapshot, session: SessionState, now: Date = Date()) async {
        guard let userID = userID(for: session), consent.healthSyncEnabled else { return }
        try? await transport.pushHealth(userID: userID, payload: snapshot, updatedAt: now)
    }

    /// Turn health sync off. When `deleteRemote` is true, also remove the already
    /// uploaded health row from the backend — the "delete my health data" path.
    public func disableHealthSync(deleteRemote: Bool, session: SessionState) async {
        consent.setHealthSyncEnabled(false)
        guard deleteRemote, let userID = userID(for: session) else { return }
        try? await transport.deleteHealth(userID: userID)
    }

    /// Account deletion: forget both opt-ins and delete the remote health row.
    public func purgeOnAccountDeletion(session: SessionState) async {
        if let userID = userID(for: session) {
            try? await transport.deleteHealth(userID: userID)
        }
        consent.reset()
    }
}
