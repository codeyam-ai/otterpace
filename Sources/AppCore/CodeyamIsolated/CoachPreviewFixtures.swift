import SwiftUI

// Shared sample data for the Coach Data Preview isolation scaffolds.
//
// The seven preview cards each vary along one axis — populated vs absent — so
// they share one set of fixtures rather than each inventing its own. Keeping the
// data here means a card's two scenarios differ ONLY by the thing under test,
// which is what makes the pair readable as a before/after.
enum CoachPreviewFixtures {
    static let workouts: [LatestWorkout] = [
        LatestWorkout(type: "run", distanceMiles: 4.2, durationMinutes: 43,
                      pace: "10:15/mi", date: "2026-06-21", source: "healthkit"),
        LatestWorkout(type: "walk", distanceMiles: 2.1, durationMinutes: 38,
                      pace: "18:05/mi", date: "2026-06-19", source: "healthkit"),
        LatestWorkout(type: "run", distanceMiles: 6.0, durationMinutes: 62,
                      pace: "10:20/mi", date: "2026-06-17", source: "strava"),
    ]

    static let loadHistory: [WeeklyLoadPoint] = [
        WeeklyLoadPoint(weekStartISO: "2026-06-15", miles: 15.4, daysRun: 3),
        WeeklyLoadPoint(weekStartISO: "2026-06-08", miles: 11.2, daysRun: 2),
    ]

    static let races: [RaceGoal] = [
        RaceGoal(name: "Marin Headlands Trail Half", distanceMiles: 13.1,
                 date: "2026-10-10", location: "Sausalito, CA",
                 notes: "Goal: finish strong, under 2:30"),
    ]

    static let profile = CoachProfile(walkVolume: .mostDays, walkTime: .mornings,
                                      otherTraining: [.strength, .mobility],
                                      trainingPhase: .building)

    /// A rich, connected day — the state most fields are read from.
    static let richState = TodayState(
        healthKitConnected: true, date: "2026-06-22", steps: 6420, goalSteps: 10000,
        activeMinutes: 42, distanceMiles: 2.8, activeEnergyKcal: 310,
        minutesSinceLastMovement: 92, workouts: workouts,
        loadHistory: loadHistory, races: races, profile: profile
    )

    /// Health denied: the app knows the date and nothing else.
    static let deniedState = TodayState(healthKitConnected: false, date: "2026-06-22")

    /// Standard isolation chrome. The opaque full-bleed backdrop matters: a plain
    /// `.background` stays inside the safe area and the launch screen shows
    /// through the gaps, so a capture picks up a ghost splash behind the card.
    static func chrome<V: View>(_ content: V) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.bgTop.ignoresSafeArea())
    }
}
