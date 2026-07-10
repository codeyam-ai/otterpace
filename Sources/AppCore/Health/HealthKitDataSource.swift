import Foundation

// MARK: - HealthKit data source (real, iOS)
//
// Reads live activity from HealthKit on a real device: today's step count,
// walking/running distance, and active energy, plus recent workouts. Compiled
// only for iOS; on other platforms (the macOS test build) a stub reports
// `.unavailable` so the package still compiles. This is platform glue — its real
// behavior is verified on a signed device build, not in the CodeYam preview loop
// (which uses the seeded source).
//
// Requires: the HealthKit capability/entitlement (declared in App/App.entitlements
// and wired via CODE_SIGN_ENTITLEMENTS) plus `NSHealthShareUsageDescription` in
// App/Info.plist. See docs/testflight-prep.md for the signing/capability checklist.

#if os(iOS)
import HealthKit

public final class HealthKitDataSource: HealthDataSource {
    private let store = HKHealthStore()

    public init() {}

    // The daily goal is read live from the user's persisted preference each load,
    // so changing it in Settings reflects immediately.
    private var goalSteps: Int { UserPreferences.goalSteps() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let dist = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(dist) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    public func authorizationState() -> HealthAuthState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        guard let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return .unavailable }
        // Note: read authorization is intentionally opaque in HealthKit — a
        // `.notDetermined`/`.sharingDenied` status here reflects whether we've asked,
        // not whether the user granted reads (Apple hides that for privacy). We treat
        // "asked" as authorized and rely on empty reads to surface a real denial.
        switch store.authorizationStatus(for: steps) {
        case .notDetermined: return .notDetermined
        case .sharingDenied: return .authorized   // may still allow reads; see note
        case .sharingAuthorized: return .authorized
        @unknown default: return .notDetermined
        }
    }

    public func requestAuthorization() async -> HealthAuthState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        return await withCheckedContinuation { cont in
            store.requestAuthorization(toShare: [], read: readTypes) { ok, _ in
                cont.resume(returning: ok ? .authorized : .denied)
            }
        }
    }

    public func loadToday() async -> TodayState {
        async let steps = sumToday(.stepCount, unit: .count())
        async let distance = sumToday(.distanceWalkingRunning, unit: .mile())
        async let energy = sumToday(.activeEnergyBurned, unit: .kilocalorie())
        async let workouts = recentWorkouts()

        let now = Date()
        let isoDate = DateFormatter.iso.string(from: now)
        let history = await workouts                       // newest-first, last ~30 days
        let todayISO = isoDate
        // Active minutes = time spent in workouts logged today.
        let activeMinutes = history
            .filter { $0.date == todayISO }
            .reduce(0) { $0 + $1.durationMinutes }
        // Latest run (preferred) or latest workout of any kind, for the Today card.
        let latest = history.first(where: { $0.type == "run" }) ?? history.first
        // Weekly Load / Activity History derive from the same workout list.
        let load = history.isEmpty ? nil : ActivityHistory.weeklyLoad(from: history, asOf: now)
        // The multi-week series the coaches reason from (empty when no history).
        let loadHistory = history.isEmpty ? [] : ActivityHistory.loadHistory(from: history)

        return TodayState(
            healthKitConnected: true,
            date: isoDate,
            steps: Int(await steps),
            goalSteps: goalSteps,
            activeMinutes: activeMinutes,
            distanceMiles: await distance,
            activeEnergyKcal: Int(await energy),
            minutesSinceLastMovement: 0,
            latestWorkout: latest,
            weeklyLoad: load,
            workouts: history,
            loadHistory: loadHistory
        )
    }

    public func lastMovementDate() async -> Date? {
        // Newest step OR distance sample end-date = the last time we saw movement.
        async let steps = mostRecentSampleDate(.stepCount)
        async let dist = mostRecentSampleDate(.distanceWalkingRunning)
        return [await steps, await dist].compactMap { $0 }.max()
    }

    /// End-date of the single most-recent sample of a quantity type, or nil.
    private func mostRecentSampleDate(_ id: HKQuantityTypeIdentifier) async -> Date? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: samples?.first?.endDate)
            }
            store.execute(q)
        }
    }

    /// Read recent workouts (last 30 days, newest-first) and map them to the app's
    /// `LatestWorkout` shape so the Today card, Weekly Load, Activity History, and
    /// Weekly Review all populate from live HealthKit data.
    private func recentWorkouts(days: Int = 30, limit: Int = 60) async -> [LatestWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: limit, sortDescriptors: [sort]) { _, samples, _ in
                let workouts = (samples as? [HKWorkout])?.map(Self.map) ?? []
                cont.resume(returning: workouts)
            }
            store.execute(q)
        }
    }

    /// Map an `HKWorkout` to a `LatestWorkout`. Distance is taken from the
    /// workout's total distance (0 when HealthKit didn't record one, e.g. yoga);
    /// the date is the workout's local calendar day so it groups under the day the
    /// user actually moved.
    private static func map(_ w: HKWorkout) -> LatestWorkout {
        let meters = w.totalDistance?.doubleValue(for: .meter()) ?? 0
        let miles = meters / 1609.344
        let minutes = Int((w.duration / 60).rounded())
        let pace = (miles > 0 && w.duration > 0) ? pacePerMile(secondsPerMile: w.duration / miles) : ""
        return LatestWorkout(
            type: activityName(w.workoutActivityType),
            distanceMiles: (miles * 10).rounded() / 10,
            durationMinutes: minutes,
            pace: pace,
            date: DateFormatter.iso.string(from: w.startDate),
            source: "healthkit"
        )
    }

    /// The app's coarse activity vocabulary (run | walk | ride | workout), matching
    /// the Strava mapping so both sources read the same downstream.
    private static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                return "run"
        case .walking, .hiking:       return "walk"
        case .cycling:                return "ride"
        default:                      return "workout"
        }
    }

    /// Format a "mm:ss/mi" pace from seconds-per-mile.
    private static func pacePerMile(secondsPerMile: Double) -> String {
        let total = Int(secondsPerMile.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))/mi"
    }

    /// Sum a cumulative quantity from midnight to now.
    private func sumToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }
}

private extension DateFormatter {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        // Explicitly the user's LOCAL calendar day: "today" pairs with the local-day
        // step sums, and a workout's date is the day the user actually moved. (This
        // differs intentionally from ActivityHistory's fixed-UTC date math, which
        // only does deterministic week-bucketing on these date-only strings.)
        f.timeZone = .current
        return f
    }()
}

#else

// Non-iOS (e.g. the macOS test build): HealthKit isn't used. Report unavailable so
// the package compiles and any production path falls back gracefully.
public final class HealthKitDataSource: HealthDataSource {
    public init(goalSteps: Int = 10000) {}
    public func authorizationState() -> HealthAuthState { .unavailable }
    public func requestAuthorization() async -> HealthAuthState { .unavailable }
    public func loadToday() async -> TodayState { .empty }
    public func lastMovementDate() async -> Date? { nil }
}

#endif
