import SwiftUI

// MARK: - Today dashboard
//
// The full Today surface, composed purely from section components: header,
// Buddy + step ring, quick stats, and the AI coach / latest activity / weekly
// load cards. Each section lives in its own file; this view only arranges them.
public struct TodayDashboard: View {
    @ObservedObject var model: OtterpaceModel
    var onAskCoach: () -> Void
    var onSettings: () -> Void

    // Activity History presents as a full-cover overlay (cross-platform; a
    // SwiftUI `fullScreenCover` is unavailable on macOS). Initialized from the
    // scenario seed in `init` so a launch-seeded capture renders it on the first
    // frame, never mid-transition — same pattern as the Weekly Review overlay.
    @State private var showHistory: Bool
    @State private var racePromptDismissed: Bool

    // The journal editor presents as a full-cover overlay too, and is likewise
    // seeded from the scenario so a launch-seeded capture renders it complete on
    // the first frame. `journalEditorTarget` records WHICH entry is open: a
    // standalone check-in, or a note bound to the latest workout.
    @State private var showJournalEditor: Bool
    @State private var journalEditorIsPostRun: Bool

    // Scenario seed: force the "add a race" banner visible for capture even when a
    // scenario would otherwise hide it.
    private let forceRacePrompt = UserDefaults.standard.bool(forKey: "rbShowRacePrompt")

    // The spotlight tour's current step, or nil when the tour isn't running.
    // Seeded in `init` (like `showHistory` / `showJournalEditor`) so a
    // launch-seeded capture renders the tour complete on the very first frame
    // rather than mid-transition.
    @State private var tourStep: Int?

    public init(model: OtterpaceModel, onAskCoach: @escaping () -> Void = {}, onSettings: @escaping () -> Void = {}) {
        self.model = model
        self.onAskCoach = onAskCoach
        self.onSettings = onSettings
        _showHistory = State(initialValue: UserDefaults.standard.bool(forKey: "rbShowHistory"))
        _racePromptDismissed = State(initialValue: RacePromptState.isDismissed())
        _showJournalEditor = State(initialValue: UserDefaults.standard.bool(forKey: "rbShowJournalEditor"))
        _journalEditorIsPostRun = State(initialValue: UserDefaults.standard.bool(forKey: "rbJournalEditorPostRun"))

        let showTour = TourState.shouldShow(
            startScreen: UserDefaults.standard.string(forKey: "rbStartScreen") ?? "",
            healthConnected: model.today.healthKitConnected
        )
        _tourStep = State(initialValue: showTour ? TourState.startStep() : nil)
    }

    // The "today" used for race math: the seeded/observed dashboard date when set
    // (so the banner stays in lockstep with the coaching engines and the Settings
    // race list), else the device clock. Mirrors `SettingsView.todayISO`.
    private var todayISO: String {
        let snapshot = model.today.date
        if !snapshot.isEmpty { return snapshot }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    // Show the race prompt when there is no *upcoming* race and it hasn't been
    // dismissed (or when a scenario forces it). A finished (past-only) race no
    // longer suppresses the banner, so the user is invited to set their next goal.
    // Today's standalone check-in, and the note attached to the latest workout.
    // Kept separate on purpose: the check-in card and the workout card each own
    // their own entry instead of the two surfaces fighting over one.
    private var todayCheckIn: JournalEntry? {
        Journal.checkIn(on: todayISO, in: model.today.journal)
    }

    private var latestWorkoutNote: JournalEntry? {
        guard let workout = model.today.latestWorkout else { return nil }
        return Journal.entry(forWorkoutOn: workout.date, in: model.today.journal)
    }

    // Dismissal is a snooze now, not a self-destruct, and the banner stays quiet
    // through the first session — see `RacePromptState.shouldShow`.
    private var showRacePrompt: Bool {
        forceRacePrompt
            || (!racePromptDismissed
                && RacePromptState.shouldShow(asOf: todayISO, races: model.today.races))
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Layout.cardSpacing) {
                    TodayHeader(date: model.today.date, onSettings: onSettings)
                    BuddySummaryCard(model: model)
                        .tourAnchor(.buddy)
                    StatsRow(today: model.today)
                        .tourAnchor(.stats)
                    if showRacePrompt {
                        RacePromptBanner(
                            onTap: onSettings,
                            onDismiss: {
                                RacePromptState.snooze(asOf: todayISO)
                                Analytics.shared.capture(
                                    "race_prompt_snoozed",
                                    ["count": "\(RacePromptState.dismissCount())"]
                                )
                                withAnimation(Motion.overlay) { racePromptDismissed = true }
                            }
                        )
                    }
                    // Seeded scenarios may pin a coach recommendation; otherwise
                    // compute the honest nudge from the day's data (no key needed).
                    CoachCard(coach: model.today.coach ?? CoachEngine.dailyNudge(for: model.today),
                              onAskCoach: onAskCoach)
                        .tourAnchor(.coachCard)
                    CheckInCard(
                        entry: todayCheckIn,
                        onQuickFeel: { feel in
                            // One tap logs a check-in outright — the fastest
                            // possible entry, and the journal's whole premise.
                            model.quickFeel(feel, on: todayISO)
                            Analytics.shared.capture("journal_quick_feel")
                        },
                        onOpenEditor: {
                            journalEditorIsPostRun = false
                            withAnimation(Motion.overlay) { showJournalEditor = true }
                        }
                    )
                    .tourAnchor(.checkIn)
                    if let workout = model.today.latestWorkout {
                        WorkoutCard(
                            workout: workout,
                            note: Journal.entry(forWorkoutOn: workout.date, in: model.today.journal),
                            onAddNote: {
                                journalEditorIsPostRun = true
                                withAnimation(Motion.overlay) { showJournalEditor = true }
                            }
                        )
                    }
                    if let load = model.today.weeklyLoad {
                        WeeklyLoadCard(load: load)
                    }
                    ActivityHistoryButton(onTap: { withAnimation(Motion.overlay) { showHistory = true } })
                        .tourAnchor(.history)
                }
                .screenScrollContent()
            }
            .refreshable { await model.refresh() }

            if showHistory {
                ActivityHistoryView(model: model, onClose: { withAnimation(Motion.overlay) { showHistory = false } })
                    .overlayTransition()
                    .zIndex(1)
            }

            if showJournalEditor {
                JournalEditorSheet(
                    entry: journalEditorIsPostRun ? latestWorkoutNote : todayCheckIn,
                    date: journalEditorIsPostRun ? (model.today.latestWorkout?.date ?? todayISO) : todayISO,
                    workoutDate: journalEditorIsPostRun ? model.today.latestWorkout?.date : nil,
                    workoutType: journalEditorIsPostRun ? model.today.latestWorkout?.type : nil,
                    onSave: { entry in
                        model.saveJournalEntry(entry)
                        Analytics.shared.capture("journal_entry_saved")
                    },
                    onDelete: { id in model.deleteJournalEntry(id: id) },
                    onClose: { withAnimation(Motion.overlay) { showJournalEditor = false } }
                )
                .overlayTransition()
                .zIndex(2)
            }
        }
        // The tour sits above every other overlay, and reads the anchor bounds
        // collected from the tagged sections. When no anchor has resolved yet the
        // callout centers itself, so a launch-seeded capture is never blank.
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let index = tourStep, index < TourStep.allCases.count {
                    let step = TourStep.allCases[index]
                    TodayTourOverlay(
                        step: step,
                        index: index,
                        highlight: anchors[step.anchorID].map { proxy[$0] },
                        onNext: { advanceTour(from: index) },
                        onSkip: { endTour(step: step, completed: false) }
                    )
                }
            }
        }
        .onAppear {
            if let index = tourStep, index < TourStep.allCases.count {
                Analytics.shared.capture("tour_started")
                Analytics.shared.capture("tour_step_viewed", ["step": TourStep.allCases[index].rawValue])
            }
        }
    }

    // MARK: Tour

    private func advanceTour(from index: Int) {
        let next = index + 1
        guard next < TourStep.allCases.count else {
            endTour(step: TourStep.allCases[index], completed: true)
            return
        }
        Analytics.shared.capture("tour_step_viewed", ["step": TourStep.allCases[next].rawValue])
        withAnimation(Motion.overlay) { tourStep = next }
    }

    private func endTour(step: TourStep, completed: Bool) {
        TourState.markSeen()
        Analytics.shared.capture(completed ? "tour_completed" : "tour_skipped",
                                 ["step": step.rawValue])
        withAnimation(Motion.overlay) { tourStep = nil }
    }
}
