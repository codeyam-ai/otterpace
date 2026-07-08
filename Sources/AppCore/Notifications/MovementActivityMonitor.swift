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
        guard settings.inactivityEnabled else { stop(); return }

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
        scheduler.armInactivity(fireAt: nil, settings: ReminderSettings.load())
    }

    /// Read the real last-movement time, compute the fire date, and (re)arm.
    private func rearm(_ settings: ReminderSettings) async {
        let last = await source.lastMovementDate()
        let fireAt = InactivitySchedule.fireDate(lastMovement: last, hours: settings.inactivityHours)
        await MainActor.run { scheduler.armInactivity(fireAt: fireAt, settings: settings) }
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
