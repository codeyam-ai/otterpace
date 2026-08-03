import Foundation

// MARK: - Ask Coach ice-breakers
//
// A blank text field tells a new user nothing about what Buddy can actually
// answer. These are the tappable examples that show the shape of a good question.
//
// Each suggestion declares the `CoachIntent` it was written for, and the wording
// is chosen so `CoachIntent.classify` genuinely routes it there — a test asserts
// that round-trip, so a suggestion can never quietly drift into the wrong intent
// (or, worse, into `.injuryPain`) as the classifier's keywords evolve.

public struct StarterQuestion: Equatable, Identifiable {
    public let text: String
    /// The intent this question is written to reach.
    public let intent: CoachIntent

    public var id: String { text }

    public init(text: String, intent: CoachIntent) {
        self.text = text
        self.intent = intent
    }
}

public enum StarterQuestions {
    /// The most chips we ever offer, so the row never dominates the screen.
    public static let maxCount = 4

    /// Ice-breakers for the current day's state, most useful first.
    ///
    /// Conditional suggestions only appear when the data behind them exists: a
    /// day-one user with no runs is not offered "how did my last run go?", and a
    /// user with no races is not offered race planning. Offering a question the
    /// app cannot answer well is exactly the first-run confusion this fixes.
    public static func suggestions(for context: TodayState, asOf today: String = "") -> [StarterQuestion] {
        var out: [StarterQuestion] = [
            StarterQuestion(text: "Should I run today or rest?", intent: .runOrRest),
            StarterQuestion(text: "How do I get to 10,000 steps today?", intent: .hit10K),
        ]

        if context.latestWorkout != nil {
            out.append(StarterQuestion(text: "How did my last run go?", intent: .postRunReflection))
        }

        let day = today.isEmpty ? context.date : today
        if !day.isEmpty, RaceGoal.hasUpcoming(in: context.races, asOf: day) {
            out.append(StarterQuestion(text: "How should I train for my race?", intent: .raceGoal))
        }

        if context.loadHistory.count >= 2 {
            out.append(StarterQuestion(text: "Am I building mileage too fast?", intent: .mileageTooFast))
        }

        // Always available, and the natural catch-all, so it backfills whenever
        // the conditional suggestions did not fire.
        out.append(StarterQuestion(text: "What should I focus on this week?", intent: .general))

        // De-duplicate defensively (by text) before capping, so a future edit that
        // repeats a question can't spend a scarce chip slot twice.
        var seen = Set<String>()
        let unique = out.filter { seen.insert($0.text).inserted }
        return Array(unique.prefix(maxCount))
    }
}
