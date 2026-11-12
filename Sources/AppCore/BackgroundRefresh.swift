import Foundation

// MARK: - Background refresh (the closed-app pass)
//
// One pass of "bring the cached picture and the server heartbeat up to date"
// while the app is closed. Called from the two background wakes iOS gives us:
// the HealthKit observer's hourly delivery (which we already pay for) and one
// infrequent `BGAppRefreshTask`. Battery-light by construction:
//
//   • every read goes through `RefreshPolicy` (Health ≥ 1h, Strava ≥ 3h apart);
//   • a locked-phone Health read is "unknown" and changes nothing;
//   • the AI coach never runs here — no card regeneration, no API-key spend;
//   • the heartbeat is pushed only when fresh data arrived AND the user is
//     signed in with Health sync on (`AccountSyncService.pushHealth` gates it).
//
// The background launch has no SwiftUI scene, so it runs its own model; the
// result lands in `SnapshotCache`, which the foreground model adopts on return.
public enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in App/Info.plist.
    public static let taskIdentifier = "com.otterpace.app.refresh"

    @MainActor
    public static func run(scheduler: MovementReminderScheduling = MovementReminderScheduler()) async {
        guard !HealthSource.isScenarioSeeded() else { return }
        let model = OtterpaceModel()
        let fresh = await model.refreshIfDue(.background, fetchStrava: stravaFetcher())
        guard fresh else { return }
        // Re-arm from the fresh read so the heartbeat can tell the server whether
        // this device already has the idle spell covered.
        await model.rearmInactivity(scheduler, settings: ReminderSettings.load())
        await AccountSyncService().pushHealth(await model.healthHeartbeat(), session: SessionStore().state)
    }

    /// The Strava import every launch/refresh path hands the model (the model
    /// doesn't own `StravaService`). Returns [] when Strava isn't connected.
    @MainActor
    public static func stravaFetcher() -> () async throws -> [LatestWorkout] {
        let strava = StravaService()
        return { try await strava.fetchActivities() }
    }
}
