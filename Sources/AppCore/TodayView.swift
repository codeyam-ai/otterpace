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

    // Scenario seed: force the "add a race" banner visible for capture even when a
    // scenario would otherwise hide it.
    private let forceRacePrompt = UserDefaults.standard.bool(forKey: "rbShowRacePrompt")

    public init(model: OtterpaceModel, onAskCoach: @escaping () -> Void = {}, onSettings: @escaping () -> Void = {}) {
        self.model = model
        self.onAskCoach = onAskCoach
        self.onSettings = onSettings
        _showHistory = State(initialValue: UserDefaults.standard.bool(forKey: "rbShowHistory"))
        _racePromptDismissed = State(initialValue: RacePromptState.isDismissed())
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
                    if let workout = model.today.latestWorkout {
                        WorkoutCard(workout: workout)
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
        }
    }
}
