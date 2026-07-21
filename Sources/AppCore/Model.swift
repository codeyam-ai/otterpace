import Foundation

// MARK: - Domain types
//
// Otterpace's Today dashboard renders a single `TodayState` snapshot. In a real
// build this is assembled from HealthKit (and optionally Strava); in the
// CodeYam preview it is injected at launch through the scenario's
// `deviceState.preferences` under the shared key `seedStateJSON` (a JSON-encoded
// `TodayState`). Production starts empty: no seed → `.empty` → the day-one
// "Connect Apple Health" hero.

public struct LatestWorkout: Codable, Equatable {
    public var type: String          // run | walk | ride
    public var distanceMiles: Double
    public var durationMinutes: Int
    public var pace: String          // e.g. "10:15/mi"
    public var date: String          // ISO date, e.g. "2026-06-21"
    public var source: String        // healthkit | strava

    public init(type: String, distanceMiles: Double, durationMinutes: Int, pace: String, date: String, source: String) {
        self.type = type
        self.distanceMiles = distanceMiles
        self.durationMinutes = durationMinutes
        self.pace = pace
        self.date = date
        self.source = source
    }
}

public struct WeeklyLoad: Codable, Equatable {
    public var weeklyMileage: Double
    public var daysRunThisWeek: Int
    public var longestRunMiles: Double
    public var restDaysThisWeek: Int  // measured over elapsed days, not a full 7
    public var loadTrend: String      // building | steady | spiking | recovering
    public var daysElapsedThisWeek: Int  // 1 (Monday) ... 7 (Sunday)
    public var rolling7Miles: Double     // trailing 7 days inclusive of the reference date
    public var rolling7DaysRun: Int      // distinct run days in that same window

    // The trailing-window fields default so every existing construction site
    // (tests, coach engines, scenario seeding) keeps compiling, and so older
    // persisted `Codable` payloads still decode.
    public init(weeklyMileage: Double, daysRunThisWeek: Int, longestRunMiles: Double, restDaysThisWeek: Int, loadTrend: String,
                daysElapsedThisWeek: Int = 7, rolling7Miles: Double = 0, rolling7DaysRun: Int = 0) {
        self.weeklyMileage = weeklyMileage
        self.daysRunThisWeek = daysRunThisWeek
        self.longestRunMiles = longestRunMiles
        self.restDaysThisWeek = restDaysThisWeek
        self.loadTrend = loadTrend
        self.daysElapsedThisWeek = daysElapsedThisWeek
        self.rolling7Miles = rolling7Miles
        self.rolling7DaysRun = rolling7DaysRun
    }

    // Tolerant decode, same rationale as `TodayState` (which embeds this type): a
    // payload written before the elapsed/rolling fields existed must still decode
    // instead of throwing on the missing keys. Swift's synthesized decoder ignores
    // initializer defaults, so the fallbacks have to be spelled out here.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weeklyMileage = try c.decodeIfPresent(Double.self, forKey: .weeklyMileage) ?? 0
        daysRunThisWeek = try c.decodeIfPresent(Int.self, forKey: .daysRunThisWeek) ?? 0
        longestRunMiles = try c.decodeIfPresent(Double.self, forKey: .longestRunMiles) ?? 0
        restDaysThisWeek = try c.decodeIfPresent(Int.self, forKey: .restDaysThisWeek) ?? 0
        loadTrend = try c.decodeIfPresent(String.self, forKey: .loadTrend) ?? "steady"
        daysElapsedThisWeek = try c.decodeIfPresent(Int.self, forKey: .daysElapsedThisWeek) ?? 7
        rolling7Miles = try c.decodeIfPresent(Double.self, forKey: .rolling7Miles) ?? 0
        rolling7DaysRun = try c.decodeIfPresent(Int.self, forKey: .rolling7DaysRun) ?? 0
    }
}

/// One week's mileage rollup in the coach-facing `loadHistory` series. Small on
/// purpose (week start, miles, run days) so several weeks fit comfortably under
/// the backend context byte cap. Derived from `ActivityHistory.groupByWeek`.
public struct WeeklyLoadPoint: Codable, Equatable {
    public var weekStartISO: String   // ISO Monday that starts the week
    public var miles: Double
    public var daysRun: Int

    public init(weekStartISO: String, miles: Double, daysRun: Int) {
        self.weekStartISO = weekStartISO
        self.miles = miles
        self.daysRun = daysRun
    }
}

public struct CoachRecommendation: Codable, Equatable {
    public var buddyMood: String        // resting|ready|jogging|cheering|concerned|celebrating|recovery
    public var headline: String
    public var body: String
    public var recommendationType: String // move|walk|run|rest|celebrate|caution
    public var safetyFlag: Bool

    public init(buddyMood: String, headline: String, body: String, recommendationType: String, safetyFlag: Bool = false) {
        self.buddyMood = buddyMood
        self.headline = headline
        self.body = body
        self.recommendationType = recommendationType
        self.safetyFlag = safetyFlag
    }
}

public struct TodayState: Codable, Equatable {
    public var healthKitConnected: Bool
    public var date: String
    public var steps: Int
    public var goalSteps: Int
    public var activeMinutes: Int
    public var distanceMiles: Double
    public var activeEnergyKcal: Int
    public var minutesSinceLastMovement: Int
    public var latestWorkout: LatestWorkout?
    public var weeklyLoad: WeeklyLoad?
    public var coach: CoachRecommendation?
    public var workouts: [LatestWorkout]   // recent history, newest-first; [] => day-one empty
    public var loadHistory: [WeeklyLoadPoint] // coach-facing weekly mileage series, newest-first; [] => none
    public var races: [RaceGoal]           // optional upcoming races; [] => none set
    public var profile: CoachProfile?      // optional onboarding personalization; nil => not shared
    /// Per-day step totals keyed by ISO date ("yyyy-MM-dd"), powering the progress
    /// heatmap's steps-vs-goal metric. Optional and empty by default: HealthKit
    /// gives us today's steps but no per-day series, so this is populated only
    /// where a scenario seeds it. [:] => the steps metric shows "no step data yet"
    /// rather than a grid of misleading zeroes.
    public var dailySteps: [String: Int]

    public init(
        healthKitConnected: Bool,
        date: String = "",
        steps: Int = 0,
        goalSteps: Int = 10000,
        activeMinutes: Int = 0,
        distanceMiles: Double = 0,
        activeEnergyKcal: Int = 0,
        minutesSinceLastMovement: Int = 0,
        latestWorkout: LatestWorkout? = nil,
        weeklyLoad: WeeklyLoad? = nil,
        coach: CoachRecommendation? = nil,
        workouts: [LatestWorkout] = [],
        loadHistory: [WeeklyLoadPoint] = [],
        races: [RaceGoal] = [],
        profile: CoachProfile? = nil,
        dailySteps: [String: Int] = [:]
    ) {
        self.healthKitConnected = healthKitConnected
        self.date = date
        self.steps = steps
        self.goalSteps = goalSteps
        self.activeMinutes = activeMinutes
        self.distanceMiles = distanceMiles
        self.activeEnergyKcal = activeEnergyKcal
        self.minutesSinceLastMovement = minutesSinceLastMovement
        self.latestWorkout = latestWorkout
        self.weeklyLoad = weeklyLoad
        self.coach = coach
        self.workouts = workouts
        self.loadHistory = loadHistory
        self.races = races
        self.profile = profile
        self.dailySteps = dailySteps
    }

    // Tolerant decode: TodayState is encode-only in production (assembled via the
    // memberwise init, then shipped to the backend), so the only real decode is of
    // hand-written / older JSON. Default every collection and optional field so a
    // payload written before a field existed — e.g. `loadHistory` or `profile` —
    // still decodes cleanly instead of throwing on the missing key.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        healthKitConnected = try c.decode(Bool.self, forKey: .healthKitConnected)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        goalSteps = try c.decodeIfPresent(Int.self, forKey: .goalSteps) ?? 10000
        activeMinutes = try c.decodeIfPresent(Int.self, forKey: .activeMinutes) ?? 0
        distanceMiles = try c.decodeIfPresent(Double.self, forKey: .distanceMiles) ?? 0
        activeEnergyKcal = try c.decodeIfPresent(Int.self, forKey: .activeEnergyKcal) ?? 0
        minutesSinceLastMovement = try c.decodeIfPresent(Int.self, forKey: .minutesSinceLastMovement) ?? 0
        latestWorkout = try c.decodeIfPresent(LatestWorkout.self, forKey: .latestWorkout)
        weeklyLoad = try c.decodeIfPresent(WeeklyLoad.self, forKey: .weeklyLoad)
        coach = try c.decodeIfPresent(CoachRecommendation.self, forKey: .coach)
        workouts = try c.decodeIfPresent([LatestWorkout].self, forKey: .workouts) ?? []
        loadHistory = try c.decodeIfPresent([WeeklyLoadPoint].self, forKey: .loadHistory) ?? []
        races = try c.decodeIfPresent([RaceGoal].self, forKey: .races) ?? []
        profile = try c.decodeIfPresent(CoachProfile.self, forKey: .profile)
        dailySteps = try c.decodeIfPresent([String: Int].self, forKey: .dailySteps) ?? [:]
    }

    // Production default: nothing connected yet, blank day-one state.
    public static let empty = TodayState(healthKitConnected: false, goalSteps: 10000)
}

// MARK: - Observable model

public final class OtterpaceModel: ObservableObject {
    @Published public var today: TodayState
    /// Whether the app may read HealthKit. Drives the Connect hero vs. the
    /// "Health access is off" state. Seeded scenarios start `.authorized`.
    @Published public var healthAuth: HealthAuthState

    private let source: HealthDataSource
    /// The UserDefaults the on-device stores (races, coach profile) read/write.
    /// Kept so `applyOnDeviceState()` and the race mutators use the same store —
    /// `.standard` in the app, an injectable suite in tests.
    private let defaults: UserDefaults
    #if os(iOS)
    /// The live HealthKit movement observer, retained while the inactivity reminder
    /// is on so its background-delivery query stays alive. iOS-only device glue.
    private var movementMonitor: MovementActivityMonitor?
    #endif

    public init(today: TodayState, source: HealthDataSource = SeededHealthDataSource(),
                defaults: UserDefaults = .standard) {
        self.today = today
        self.source = source
        self.defaults = defaults
        self.healthAuth = today.healthKitConnected ? .authorized : .notDetermined
    }

    /// Launch-time initializer used by the app. In a CodeYam scenario it builds the
    /// `TodayState` from the seeded `rb*` UserDefaults (previews unchanged). In
    /// production (no seed) it starts empty and reads live data from HealthKit once
    /// the user connects.
    public convenience init() {
        let defaults = UserDefaults.standard
        let source = HealthSource.make(defaults: defaults)
        if HealthSource.isScenarioSeeded(defaults) {
            self.init(today: OtterpaceModel.readState(defaults: defaults), source: source, defaults: defaults)
        } else {
            self.init(today: .empty, source: source, defaults: defaults)
            self.healthAuth = source.authorizationState()
            // Races live on-device (not in the HealthKit snapshot), so load them
            // so a real user's races reach coaching from launch.
            self.today.races = RaceStore.load(defaults)
            // The onboarding personalization profile is also on-device; attach it
            // (nil when empty) so it reaches coaching from launch too.
            let profile = CoachProfileStore.load(defaults)
            self.today.profile = profile.isEmpty ? nil : profile
        }
    }

    /// Read the snapshot from flat `rb*` UserDefaults keys. Each scenario writes
    /// these as primitive `preferences` values; the `rb` prefix keeps them from
    /// colliding with unrelated keys left on a shared simulator. A field group
    /// (workout / weekly load / coach) is present only when its anchor key is set.
    public static func readState(defaults d: UserDefaults = .standard) -> TodayState {
        let connected = d.bool(forKey: "rbConnected")
        var goal = d.integer(forKey: "rbGoalSteps")
        if goal == 0 { goal = 10000 }

        var workout: LatestWorkout? = nil
        if let type = d.string(forKey: "rbWorkoutType"), !type.isEmpty {
            workout = LatestWorkout(
                type: type,
                distanceMiles: d.double(forKey: "rbWorkoutDistanceMiles"),
                durationMinutes: d.integer(forKey: "rbWorkoutDurationMinutes"),
                pace: d.string(forKey: "rbWorkoutPace") ?? "",
                date: d.string(forKey: "rbWorkoutDate") ?? "",
                source: d.string(forKey: "rbWorkoutSource") ?? "healthkit"
            )
        }

        var load: WeeklyLoad? = nil
        if let trend = d.string(forKey: "rbLoadTrend"), !trend.isEmpty {
            load = WeeklyLoad(
                weeklyMileage: d.double(forKey: "rbWeeklyMileage"),
                daysRunThisWeek: d.integer(forKey: "rbDaysRunThisWeek"),
                longestRunMiles: d.double(forKey: "rbLongestRunMiles"),
                restDaysThisWeek: d.integer(forKey: "rbRestDaysThisWeek"),
                loadTrend: trend
            )
        }

        // Activity history: a JSON-encoded array of workouts under a single
        // preference key (the flat rb* primitives can't hold a list). Newest-first.
        var workouts: [LatestWorkout] = []
        if let json = d.string(forKey: "rbWorkoutsJSON"), !json.isEmpty,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([LatestWorkout].self, from: data) {
            workouts = decoded
        }

        // A seeded load carries only the flat rb* primitives, so the elapsed and
        // trailing-window fields would sit at their defaults (7 / 0 / 0) and a
        // scenario could never show the in-progress or rolling-window states the
        // real HealthKit path produces. When the scenario also seeds workouts,
        // derive those fields from the same reference date the rest of the
        // snapshot uses, so seeded previews match production.
        if load != nil, !workouts.isEmpty {
            let asOf = ActivityHistory.referenceDate(fromISO: d.string(forKey: "rbDate") ?? "")
            let rolling = ActivityHistory.rollingSevenDay(from: workouts, asOf: asOf)
            func round1(_ n: Double) -> Double { (n * 10).rounded() / 10 }
            load?.daysElapsedThisWeek = ActivityHistory.daysElapsedInWeek(asOf: asOf, cal: ActivityHistory.calendar)
            load?.rolling7Miles = round1(rolling.miles)
            load?.rolling7DaysRun = rolling.daysRun
        }

        // Coach-facing weekly mileage series. A scenario can seed it explicitly
        // via rbLoadHistoryJSON (mirroring rbWorkoutsJSON); otherwise, when the
        // scenario seeded a workout list, derive the series from it so a rich
        // multi-week scenario gets a real trajectory for free. [] => not shared.
        var loadHistory: [WeeklyLoadPoint] = []
        if let json = d.string(forKey: "rbLoadHistoryJSON"), !json.isEmpty,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([WeeklyLoadPoint].self, from: data) {
            loadHistory = decoded
        } else if !workouts.isEmpty {
            loadHistory = ActivityHistory.loadHistory(from: workouts)
        }

        // Races: a JSON-encoded array under one key (same shape as rbWorkoutsJSON),
        // so a scenario can seed upcoming races for capture.
        var races: [RaceGoal] = []
        if let json = d.string(forKey: "rbRacesJSON"), !json.isEmpty,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([RaceGoal].self, from: data) {
            races = decoded
        }

        // Personalization profile: a JSON-encoded CoachProfile under one key, so a
        // scenario can seed the onboarding-collected profile for capture / coaching.
        var profile: CoachProfile? = nil
        if let json = d.string(forKey: "rbCoachProfileJSON"), !json.isEmpty,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(CoachProfile.self, from: data),
           !decoded.isEmpty {
            profile = decoded
        }

        // Per-day steps for the progress heatmap: a JSON-encoded [ISO date: steps]
        // map under one key (same single-key pattern as rbWorkoutsJSON, since the
        // flat rb* primitives can't hold a dictionary). Absent => [:], which the
        // heatmap renders as an honest "no step data yet" instead of all-zero days.
        var dailySteps: [String: Int] = [:]
        if let json = d.string(forKey: "rbDailyStepsJSON"), !json.isEmpty,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            dailySteps = decoded
        }

        var coach: CoachRecommendation? = nil
        if let headline = d.string(forKey: "rbCoachHeadline"), !headline.isEmpty {
            coach = CoachRecommendation(
                buddyMood: d.string(forKey: "rbBuddyMood") ?? "ready",
                headline: headline,
                body: d.string(forKey: "rbCoachBody") ?? "",
                recommendationType: d.string(forKey: "rbCoachType") ?? "move",
                safetyFlag: d.bool(forKey: "rbCoachSafety")
            )
        }

        return TodayState(
            healthKitConnected: connected,
            date: d.string(forKey: "rbDate") ?? "",
            steps: d.integer(forKey: "rbSteps"),
            goalSteps: goal,
            activeMinutes: d.integer(forKey: "rbActiveMinutes"),
            distanceMiles: d.double(forKey: "rbDistanceMiles"),
            activeEnergyKcal: d.integer(forKey: "rbActiveEnergyKcal"),
            minutesSinceLastMovement: d.integer(forKey: "rbMinutesSinceMovement"),
            latestWorkout: workout,
            weeklyLoad: load,
            coach: coach,
            workouts: workouts,
            loadHistory: loadHistory,
            races: races,
            profile: profile,
            dailySteps: dailySteps
        )
    }

    // MARK: Derived values

    /// Fraction of the daily step goal reached, clamped to 0...1.
    public var goalProgress: Double {
        guard today.goalSteps > 0 else { return 0 }
        return min(1.0, Double(today.steps) / Double(today.goalSteps))
    }

    /// Steps still needed to hit the goal (never negative).
    public var stepsRemaining: Int {
        max(0, today.goalSteps - today.steps)
    }

    public var goalReached: Bool {
        today.steps >= today.goalSteps && today.goalSteps > 0
    }

    /// True when the user has gone *past* the goal, not merely reached it — used
    /// to swap the ring's caption from "goal hit" to a celebratory "Goal crushed".
    public var goalExceeded: Bool {
        today.steps > today.goalSteps && today.goalSteps > 0
    }

    /// Connect Apple Health: request read authorization, then load today's data.
    /// Seeded scenarios "grant" immediately and load their seeded state; production
    /// drives the real HealthKit permission sheet. On denial the model exposes
    /// `.denied` so the UI can point the user to Settings.
    public func connect() {
        Task { @MainActor in
            let state = await source.requestAuthorization()
            healthAuth = state
            if state == .authorized {
                today = await source.loadToday()
                applyOnDeviceState()
            }
        }
    }

    /// Re-read today's data from the source, if authorized. Wired to the Today
    /// dashboard's pull-to-refresh so a real HealthKit user can pull in newly
    /// recorded steps/workouts without relaunching. `@MainActor` so the
    /// `@Published today` mutation always publishes on the main actor (matching
    /// `connect()` and `ingestStravaWorkouts`).
    @MainActor
    public func refresh() async {
        guard healthAuth == .authorized else { return }
        today = await source.loadToday()
        applyOnDeviceState()
    }

    /// Re-apply the on-device race list and coach profile onto the freshly loaded
    /// `today` snapshot. The real HealthKit `loadToday()` builds its snapshot only
    /// from HealthKit and knows nothing about the UserDefaults where races and the
    /// coach profile live, so without this they reset to `[]`/`nil` on every
    /// `connect()`/`refresh()` — the "added a race, gone next session" bug.
    ///
    /// Scoped to the production (non-seeded) path: a seeded scenario's source
    /// already folds races/profile in through `readState`, and its live edits write
    /// to a different key (`rbRacesJSON`) than the mutators (`otterpaceRaces`), so
    /// re-merging there would clobber the seeded list. In production both this and
    /// the race mutators read/write the same `defaults`, so the persisted list is
    /// always authoritative.
    private func applyOnDeviceState() {
        guard !HealthSource.isScenarioSeeded(defaults) else { return }
        today.races = RaceStore.load(defaults)
        let profile = CoachProfileStore.load(defaults)
        today.profile = profile.isEmpty ? nil : profile
    }

    /// Set the daily step goal: persist it and apply immediately to the dashboard.
    /// Persists through the model's own `defaults` (like the race mutators) so a
    /// seeded/isolated store is honored rather than always hitting `.standard`.
    public func setGoalSteps(_ goal: Int) {
        UserPreferences.setGoalSteps(goal, defaults)
        today.goalSteps = goal
    }

    // MARK: Races (persist through RaceStore + apply to the dashboard immediately)

    @MainActor public func addRace(_ race: RaceGoal) { today.races = RaceStore.add(race, defaults) }
    @MainActor public func updateRace(_ race: RaceGoal) { today.races = RaceStore.update(race, defaults) }
    @MainActor public func removeRace(id: UUID) { today.races = RaceStore.remove(id: id, defaults) }

    /// Ingest activities imported from Strava (an optional data source alongside
    /// Apple Health). Populates the workout history + latest workout, and flips
    /// the app into the connected dashboard so the imported runs are visible even
    /// for a Strava-only user.
    @MainActor
    public func ingestStravaWorkouts(_ workouts: [LatestWorkout]) {
        guard !workouts.isEmpty else { return }
        today.workouts = workouts
        today.latestWorkout = workouts.first(where: { $0.type == "run" }) ?? workouts.first
        // Roll the imported activities up into the weekly load, the same way
        // `HealthKitDataSource.loadToday()` does, so a Strava-only user gets a real
        // Weekly Review recap instead of the empty "first week starts here" prompt.
        today.weeklyLoad = ActivityHistory.weeklyLoad(
            from: workouts,
            asOf: ActivityHistory.referenceDate(fromISO: today.date))
        // Carry the multi-week series too, so the coach can reason from the shape
        // of the imported trajectory rather than a single trend flag.
        today.loadHistory = ActivityHistory.loadHistory(from: workouts)
        today.healthKitConnected = true
    }

    // MARK: Training phase (persist through CoachProfileStore + apply immediately)

    /// Set (or clear, with `nil`) the user's declared training phase. Persists it
    /// onto the on-device `CoachProfile` and refreshes `today.profile` so it
    /// reaches coaching immediately — mirroring how `addRace` refreshes state.
    /// Builds on the current in-memory profile so a seeded scenario's other fields
    /// (walk habits, other training) are preserved.
    @MainActor public func setTrainingPhase(_ phase: TrainingPhase?) {
        var profile = today.profile ?? CoachProfileStore.load(defaults)
        profile.trainingPhase = phase
        CoachProfileStore.save(profile, defaults)
        today.profile = profile.isEmpty ? nil : profile
    }

    // MARK: Real-inactivity reminder

    /// Re-arm the inactivity nudge from the user's ACTUAL last movement: read the
    /// last-movement time from the health source, compute the fire date, and arm
    /// (or clear) the notification. This is what makes the reminder fire on real
    /// stillness rather than on app-close time, and it's what foreground/background
    /// call instead of blindly cancelling. The scheduling decision itself is the
    /// pure, unit-tested `InactivitySchedule.fireDate`.
    @MainActor
    public func rearmInactivity(_ scheduler: MovementReminderScheduling,
                                settings: ReminderSettings, now: Date = Date()) async {
        guard settings.inactivityEnabled else {
            scheduler.armInactivity(fireAt: nil, settings: settings)
            return
        }
        let last = await source.lastMovementDate()
        let fireAt = InactivitySchedule.fireDate(lastMovement: last, hours: settings.inactivityHours, now: now)
        scheduler.armInactivity(fireAt: fireAt, settings: settings)
    }

    /// The ISO-8601 timestamp of the user's last real movement, or nil when none
    /// is known — the movement heartbeat the server-driven nudge (opt-in) uploads
    /// so the backend can decide when to push. Reads the same `lastMovementDate()`
    /// the local nudge uses, so device and server share one idle baseline.
    @MainActor
    public func lastMovementISO() async -> String? {
        guard let date = await source.lastMovementDate() else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }

    /// Begin/refresh real-movement observation (HealthKit background delivery +
    /// observer query) so the nudge stays correct even while the app is closed.
    /// Owned here because the model holds the health `source`. iOS-only; a no-op in
    /// the macOS test build. Also does an immediate re-arm from current movement.
    @MainActor
    public func startMovementMonitoring(_ scheduler: MovementReminderScheduling, settings: ReminderSettings) {
        #if os(iOS)
        let monitor = movementMonitor ?? MovementActivityMonitor(source: source, scheduler: scheduler)
        movementMonitor = monitor
        monitor.start(settings: settings)
        #endif
    }

    /// Stop real-movement observation and clear any pending inactivity nudge (the
    /// user turned the reminder off). iOS-only; a no-op elsewhere.
    @MainActor
    public func stopMovementMonitoring() {
        #if os(iOS)
        movementMonitor?.stop()
        #endif
    }
}
