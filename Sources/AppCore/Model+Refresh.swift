import Foundation

// MARK: - Automatic refresh (battery-light background refresh)
//
// The throttled refresh every non-user path goes through — returning to the app,
// a HealthKit background wake, and the rare iOS background refresh — plus the
// helpers it shares with `restoreOnLaunch`. Kept apart from `Model.swift` so the
// model file stays about the dashboard state, not about when to re-read it.
// Decisions live in `RefreshPolicy` (pure); this file only sequences them.
extension OtterpaceModel {

    /// `RefreshPolicy` throttles each source; a background read that comes back
    /// empty (phone locked) is treated as unknown and leaves the cache alone.
    /// Never touches the AI coach. Returns true when fresh Health or Strava data
    /// replaced what was on screen — the signal to re-send the heartbeat.
    @MainActor
    @discardableResult
    public func refreshIfDue(_ kind: RefreshPolicy.Kind,
                             fetchStrava: (() async throws -> [LatestWorkout])? = nil,
                             now: Date = Date()) async -> Bool {
        // Launch fires both the cold-launch restore and the first foreground
        // refresh; whichever starts first does the work and the other stands down.
        guard beginRefresh() else { return false }
        defer { endRefresh() }

        let freshHealth = await refreshHealthIfDue(kind, now: now)
        let freshStrava = await refreshStravaIfDue(fetchStrava, now: now)
        let fresh = freshHealth || freshStrava

        if fresh {
            recompose()
        } else if kind == .foreground {
            // A background wake may have refreshed the cache since this model last
            // composed — show that rather than the older in-memory picture.
            adoptNewerCache()
        }
        return fresh
    }

    /// The movement heartbeat the opt-in server nudge reads, built from what is on
    /// screen now. Shared by the Settings opt-in and every automatic refresh so
    /// both send the same shape.
    @MainActor
    public func healthHeartbeat() async -> SyncableHealthSnapshot {
        SyncableHealthSnapshot.heartbeat(from: today,
                                         lastMovementAt: await lastMovementISO(),
                                         inactivityHours: ReminderSettings.load().inactivityHours,
                                         localNudgeArmedAt: armedInactivityISO())
    }

    // MARK: Shared with restoreOnLaunch

    /// Claim the single refresh slot. False in a seeded scenario (never read live
    /// data there) or while another restore/refresh is already reading.
    @MainActor
    func beginRefresh() -> Bool {
        guard !HealthSource.isScenarioSeeded(defaults), !refreshInFlight else { return false }
        refreshInFlight = true
        return true
    }

    @MainActor
    func endRefresh() {
        refreshInFlight = false
    }

    /// Call Strava and stamp any successful call — even an empty list, so a quiet
    /// account isn't re-polled. A failed call returns nil and leaves the stamp, so
    /// the next chance retries.
    @MainActor
    func fetchStravaStamped(_ fetch: () async throws -> [LatestWorkout], at now: Date) async -> [LatestWorkout]? {
        guard let workouts = try? await fetch() else { return nil }
        RefreshStamps.markStrava(now, defaults)
        return workouts
    }

    // MARK: Steps

    /// Re-read Health when authorized and due; adopt it only if the read is usable
    /// for this kind (a locked-phone background read is not). True when adopted.
    @MainActor
    private func refreshHealthIfDue(_ kind: RefreshPolicy.Kind, now: Date) async -> Bool {
        guard healthAuth == .authorized,
              RefreshPolicy.shouldRefresh(kind, lastRefreshed: RefreshStamps.lastHealth(defaults), now: now)
        else { return false }
        let state = await source.loadToday()
        guard RefreshPolicy.isUsableRead(state, for: kind) else { return false }
        healthSnapshot = state
        RefreshStamps.markHealth(now, defaults)
        return true
    }

    /// Re-import Strava when a fetcher is given and the 3h throttle allows. True
    /// only when the import changed the runs on screen.
    @MainActor
    private func refreshStravaIfDue(_ fetch: (() async throws -> [LatestWorkout])?, now: Date) async -> Bool {
        guard let fetch,
              RefreshPolicy.shouldRefresh(.strava, lastRefreshed: RefreshStamps.lastStrava(defaults), now: now),
              let workouts = await fetchStravaStamped(fetch, at: now),
              RefreshPolicy.isNewStravaImport(workouts, current: stravaWorkouts)
        else { return false }
        stravaWorkouts = workouts
        return true
    }

    /// Replace the in-memory sources with the cached snapshot when the cache was
    /// written after this model last composed (by the background-launch path,
    /// which runs its own model instance).
    @MainActor
    private func adoptNewerCache() {
        guard let cached = SnapshotCache.load(defaults),
              RefreshPolicy.shouldAdoptCache(cachedAt: cached.refreshedAt, lastComposedAt: lastComposedAt)
        else { return }
        let todayISO = HealthKitDataSource.isoDay.string(from: Date())
        healthSnapshot = cached.healthState(asOf: todayISO) ?? healthSnapshot
        stravaWorkouts = cached.strava
        recompose()
    }
}
