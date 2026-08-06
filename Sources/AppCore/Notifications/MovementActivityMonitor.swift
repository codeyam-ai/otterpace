import Foundation

// MARK: - Movement activity monitor (real-inactivity observer)
//
// The HealthKit glue that keeps the inactivity nudge honest: it observes real
// step/distance data in the background and re-arms the reminder against the user's
// ACTUAL last movement, so the "it's been a while since you moved" notification
// fires the right number of hours after they actually went still — even while the
// app is closed. iOS relaunches the app in the background to run the observer.
//
// This is platform glue (like `HealthKitDataSource`): its real behavior is
// verified on a signed device build, not in the CodeYam preview/test loop. The
// scheduling *decision* it feeds is the pure, unit-tested `InactivitySchedule`.
// A no-op stub keeps `AppCore` compiling/testing on non-iOS.

#if os(iOS)
import HealthKit

public final class MovementActivityMonitor {
    private let store = HKHealthStore()
    private let source: HealthDataSource
    private let scheduler: MovementReminderScheduling
    private var query: HKObserverQuery?

    /// Movement types whose new samples mean "the user just moved".
    private static let movementIDs: [HKQuantityTypeIdentifier] = [.stepCount, .distanceWalkingRunning]

    public init(source: HealthDataSource, scheduler: MovementReminderScheduling) {
        self.source = source
        self.scheduler = scheduler
    }

    /// Enable hourly background delivery for step/distance and run a long-lived
    /// observer query that re-arms the inactivity nudge whenever new data lands.
    /// Also does an immediate re-arm from the current last-movement time. Disabling
    /// the reminder tears everything down.
    public func start(settings: ReminderSettings) {
        // Observe when EITHER data-driven nudge is on. The goal nudge now depends
        // on this observer too (it is no longer a fixed calendar trigger), so
        // gating solely on `inactivityEnabled` would leave a goal-only user with
        // nothing waking the app — and their nudge would silently never arm.
        guard settings.inactivityEnabled || settings.goalEnabled else { stop(); return }

        Task { await rearm(settings) }   // arm now from the latest known movement

        for id in Self.movementIDs {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            // `.hourly` is the finest cadence iOS allows for cumulative types —
            // plenty for an "it's been a while" nudge.
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }

        guard query == nil, let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let observer = HKObserverQuery(sampleType: steps, predicate: nil) { [weak self] _, completion, _ in
            guard let self else { completion(); return }
            Task {
                await self.rearm(settings)
                completion()   // tell HealthKit we've handled this background wake
            }
        }
        query = observer
        store.execute(observer)
    }

    /// Stop observing and clear any pending inactivity nudge.
    public func stop() {
        if let query {
            store.stop(query)
            self.query = nil
        }
        for id in Self.movementIDs {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                store.disableBackgroundDelivery(for: type) { _, _ in }
            }
        }
        // Reached only when BOTH data-driven nudges are off, so take both down —
        // leaving a pending goal request armed after the observer that keeps it
        // honest has gone away is exactly the stale-premise nudge we're removing.
        let current = ReminderSettings.load()
        scheduler.armInactivity(fireAt: nil, settings: current)
        scheduler.armGoal(fireAt: nil, settings: current)
    }

    /// Re-evaluate EVERY data-driven reminder against fresh data and (re)arm or
    /// cancel each one. Generalized from inactivity-only: a nudge whose premise no
    /// longer holds must be taken down, not just left pending — that is what makes
    /// "verify at fire time" real rather than a better guess at schedule time.
    private func rearm(_ settings: ReminderSettings) async {
        if settings.inactivityEnabled {
            let last = await source.lastMovementDate()
            let fireAt = InactivitySchedule.fireDate(lastMovement: last, hours: settings.inactivityHours)
            await MainActor.run { scheduler.armInactivity(fireAt: fireAt, settings: settings) }
        }
        if settings.goalEnabled {
            // Reads today's steps live. `fireDate` returns nil once the goal is
            // met (cancelling any pending nudge) or while the hour is further out
            // than the step count can be trusted — the observer arms it nearer
            // the time on a later wake.
            let state = await source.loadToday()
            let fireAt = GoalNudgeSchedule.fireDate(steps: state.steps, goalSteps: state.goalSteps)
            await MainActor.run { scheduler.armGoal(fireAt: fireAt, settings: settings) }
        }
    }
}

#else

/// Non-iOS stub (macOS test build): no HealthKit, nothing to observe.
public final class MovementActivityMonitor {
    public init(source: HealthDataSource, scheduler: MovementReminderScheduling) {}
    public func start(settings: ReminderSettings) {}
    public func stop() {}
}

#endif
