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

    public init(model: OtterpaceModel, onAskCoach: @escaping () -> Void = {}, onSettings: @escaping () -> Void = {}) {
        self.model = model
        self.onAskCoach = onAskCoach
        self.onSettings = onSettings
        _showHistory = State(initialValue: UserDefaults.standard.bool(forKey: "rbShowHistory"))
        _racePromptDismissed = State(initialValue: RacePromptState.isDismissed())
        _showJournalEditor = State(initialValue: UserDefaults.standard.bool(forKey: "rbShowJournalEditor"))
        _journalEditorIsPostRun = State(initialValue: UserDefaults.standard.bool(forKey: "rbJournalEditorPostRun"))
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

    private var showRacePrompt: Bool {
        forceRacePrompt || (!RaceGoal.hasUpcoming(in: model.today.races, asOf: todayISO) && !racePromptDismissed)
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Layout.cardSpacing) {
                    TodayHeader(date: model.today.date, onSettings: onSettings)
                    BuddySummaryCard(model: model)
                    StatsRow(today: model.today)
                    if showRacePrompt {
                        RacePromptBanner(
                            onTap: onSettings,
                            onDismiss: {
                                RacePromptState.markDismissed()
                                Analytics.shared.capture("race_prompt_dismissed")
                                withAnimation(Motion.overlay) { racePromptDismissed = true }
                            }
                        )
                    }
                    // Seeded scenarios may pin a coach recommendation; otherwise
                    // compute the honest nudge from the day's data (no key needed).
                    CoachCard(coach: model.today.coach ?? CoachEngine.dailyNudge(for: model.today),
                              onAskCoach: onAskCoach)
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
    }
}
