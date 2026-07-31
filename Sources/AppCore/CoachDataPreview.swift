import SwiftUI

// MARK: - Coach Data Preview ("What Buddy sees")
//
// The privacy principle this closes: *users can inspect what data is sent to the
// coach*. Otterpace asks people to paste their own API key and then sends their
// activity to a model — this screen is the honest counterpart, showing exactly
// what would leave the device right now, in plain language.
//
// It reads the SAME `TodayState` that `AskCoachView` hands to `RemoteCoach`
// (`let context = model.today`). That is deliberate: a preview assembled from a
// separate snapshot could drift from the real payload and quietly start lying.
// Sharing the value makes drift impossible by construction.
//
// Absent data reads "Not shared" rather than being omitted. Showing what ISN'T
// sent is as much the point as showing what is — a section that silently
// disappears when empty teaches the reader nothing.

/// The distinct sources behind a workout list, named the way a person would say
/// them: "Apple Health", or "Apple Health and Strava" once an import is present.
/// First-seen order, so the list reads in the order the data actually arrived.
///
/// Free of SwiftUI (like the helpers in `Formatters.swift`) so the dedup, the
/// ordering, and the "and" grammar are unit-testable without rendering a view —
/// this string is a privacy claim about where data came from, so it should be
/// provable rather than only observable in a screenshot.
func coachWorkoutSources(_ workouts: [LatestWorkout]) -> String {
    var seen: [String] = []
    for w in workouts {
        let pretty = w.source == "strava" ? "Strava" : "Apple Health"
        if !seen.contains(pretty) { seen.append(pretty) }
    }
    if seen.count <= 1 { return seen.first ?? "Apple Health" }
    return seen.dropLast().joined(separator: ", ") + " and " + seen[seen.count - 1]
}

/// The read-only "what would be sent right now" screen.
///
/// Purely props-driven: it takes a `TodayState` and the connected-provider
/// facts, holds no store and reads no UserDefaults, so every state is
/// capturable in isolation without a Keychain entry.
public struct CoachDataPreview: View {
    let state: TodayState
    /// The provider Buddy would use, or nil when no key is connected.
    let activeProvider: CoachProvider?
    var onClose: () -> Void

    public init(state: TodayState,
                activeProvider: CoachProvider?,
                onClose: @escaping () -> Void) {
        self.state = state
        self.activeProvider = activeProvider
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                CoachPreviewHeader(onClose: onClose)
                Divider().opacity(0.4)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            CoachPreviewDestinationCard(activeProvider: activeProvider)
                            CoachPreviewActivityCard(state: state)
                            CoachPreviewWorkoutsCard(workouts: state.workouts)
                            CoachPreviewLoadCard(loadHistory: state.loadHistory)
                            CoachPreviewRacesCard(races: state.races).id("races")
                            CoachPreviewAboutYouCard(profile: state.profile).id("about")
                            CoachPreviewNeverSentCard().id("never")
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 28)
                    }
                    // Scenario-only hook, mirroring SettingsView's `rbSettingsScroll`:
                    // a capture can seed `rbCoachPreviewScroll` ("races" / "about" /
                    // "never") to open this screen scrolled to a specific card, so
                    // below-the-fold sections are visible in the frame. Production
                    // never carries this key — and every scenario seeds its OFF
                    // value explicitly, because an omitted rb* key persists from
                    // whichever scenario ran before and hijacks the first frame.
                    .onAppear {
                        let target = UserDefaults.standard.string(forKey: "rbCoachPreviewScroll") ?? ""
                        guard !target.isEmpty else { return }
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
    }
}
