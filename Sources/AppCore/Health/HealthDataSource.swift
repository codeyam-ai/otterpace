import Foundation

// MARK: - Health data source
//
// The seam that lets the app read REAL HealthKit data in production while every
// CodeYam scenario still renders from seeded mock state. Views never change —
// they always consume a `TodayState`; only where that state comes from differs.
//
//   • SeededHealthDataSource — reads the flat `rb*` UserDefaults a scenario injects
//     at launch (the existing behavior; used in previews and tests).
//   • HealthKitDataSource    — reads live steps/distance/energy/workouts from
//     HealthKit on a real device (see HealthKitDataSource.swift). iOS only.
//
// `OtterpaceModel` picks the source at launch: if a scenario seed is present it
// uses the seeded source; otherwise (production) it uses HealthKit.

/// Whether the app may read the user's health data. `unavailable` covers
/// platforms/simulators with no HealthKit (so the UI can fall back gracefully).
public enum HealthAuthState: Equatable {
    case notDetermined   // never asked → show the Connect hero
    case authorized      // granted → load + show the dashboard
    case denied          // user said no → show the "enable in Settings" state
    case unavailable     // no HealthKit on this device/platform
}

public protocol HealthDataSource {
    /// Current authorization without prompting.
    func authorizationState() -> HealthAuthState
    /// Prompt for read access (no-op-returns-current if already decided).
    func requestAuthorization() async -> HealthAuthState
    /// Today's activity snapshot, once authorized.
    func loadToday() async -> TodayState
    /// The timestamp of the user's most recent movement (step / distance) sample,
    /// or `nil` when none is known. Drives the real-inactivity reminder — the nudge
    /// fires `inactivityHours` after this moment, not after the app was last closed.
    func lastMovementDate() async -> Date?
}

// MARK: - Seeded source (scenarios / previews / tests)

/// Serves the `TodayState` a scenario seeded via `rb*` UserDefaults — the exact
/// behavior the app had before HealthKit existed, now behind the source seam so
/// CodeYam previews keep working unchanged.
public struct SeededHealthDataSource: HealthDataSource {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func authorizationState() -> HealthAuthState {
        defaults.bool(forKey: "rbConnected") ? .authorized : .notDetermined
    }

    public func requestAuthorization() async -> HealthAuthState {
        // A seeded scenario "grants" immediately; nothing real is prompted.
        defaults.set(true, forKey: "rbConnected")
        return .authorized
    }

    public func loadToday() async -> TodayState {
        var s = OtterpaceModel.readState(defaults: defaults)
        s.healthKitConnected = true
        return s
    }

    public func lastMovementDate() async -> Date? {
        // Scenarios drive the nudge deterministically: `rbLastMovementMinutesAgo`
        // (preferred) or the existing `rbMinutesSinceMovement` places the last
        // movement that many minutes before now. Neither seeded → no known movement.
        let key = defaults.object(forKey: "rbLastMovementMinutesAgo") != nil
            ? "rbLastMovementMinutesAgo"
            : (defaults.object(forKey: "rbMinutesSinceMovement") != nil ? "rbMinutesSinceMovement" : nil)
        guard let key else { return nil }
        return Date().addingTimeInterval(-Double(defaults.integer(forKey: key)) * 60)
    }
}

// MARK: - Scenario detection

public enum HealthSource {
    /// True when a CodeYam scenario has seeded any `rb*` preference at launch —
    /// the signal to use seeded data instead of live HealthKit. Production launches
    /// carry no `rb*` keys.
    public static func isScenarioSeeded(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("rb") }
    }

    /// The source to use at launch: seeded in scenarios/previews, HealthKit in
    /// production.
    public static func make(defaults: UserDefaults = .standard) -> HealthDataSource {
        isScenarioSeeded(defaults) ? SeededHealthDataSource(defaults: defaults) : HealthKitDataSource()
    }
}
