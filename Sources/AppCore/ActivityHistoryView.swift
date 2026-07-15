import SwiftUI

// MARK: - Activity History screen
//
// A scrollable history of recent workouts grouped by week (Milestone 4), each
// week fronted by its training-load rollup — mileage, run count, rest days —
// with rows reusing the shared WorkoutCard. Read-only; production starts empty
// and shows the friendly day-one prompt.
//
// Pure composition over `model.today.workouts`: the grouping is done by the
// testable `ActivityHistory.groupByWeek`, and the header, per-week section, and
// empty state each live in their own component file. This view only arranges
// them and branches between the populated history and the empty prompt.

public struct ActivityHistoryView: View {
    // Re-render this screen when the theme changes so Palette retints live.
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject var model: OtterpaceModel
    var onClose: () -> Void

    public init(model: OtterpaceModel, onClose: @escaping () -> Void = {}) {
        self.model = model
        self.onClose = onClose
    }

    private var weeks: [WeekGroup] { ActivityHistory.groupByWeek(model.today.workouts) }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ActivityHistoryHeader(onClose: onClose)
                Divider().opacity(0.4)
                if weeks.isEmpty {
                    ActivityHistoryEmptyState()
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Layout.xl) {
                            ForEach(weeks) { ActivityWeekSection(group: $0) }
                        }
                        .screenScrollContent()
                    }
                }
            }
        }
    }
}
