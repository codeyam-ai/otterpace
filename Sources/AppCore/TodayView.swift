import SwiftUI

// MARK: - Today dashboard
//
// The full Today surface, composed purely from section components: header,
// Buddy + step ring, quick stats, and the AI coach / latest activity / weekly
// load cards. Each section lives in its own file; this view only arranges them.
public struct TodayDashboard: View {
    @ObservedObject var model: RunBuddyModel
    var onAskCoach: () -> Void

    public init(model: RunBuddyModel, onAskCoach: @escaping () -> Void = {}) {
        self.model = model
        self.onAskCoach = onAskCoach
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                TodayHeader(date: model.today.date)
                BuddySummaryCard(model: model)
                StatsRow(today: model.today)
                if let coach = model.today.coach {
                    CoachCard(coach: coach, onAskCoach: onAskCoach)
                }
                if let workout = model.today.latestWorkout {
                    WorkoutCard(workout: workout)
                }
                if let load = model.today.weeklyLoad {
                    WeeklyLoadCard(load: load)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }
}
