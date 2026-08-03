import Foundation

// MARK: - Buddy's scripted opening
//
// The Coach tab used to open on a blank text field, which answered neither "who
// am I talking to?" nor "what can it actually see?". This is the short, scripted
// welcome that answers both.
//
// It is app-authored copy, NOT a fabricated model reply, and it never claims to
// be a generated answer — so it is honest to render in the locked (no key) state
// too. That preserves the rule `AskCoachLockedState` already follows: invite the
// user to connect a key rather than faking a reply.
//
// Pure and testable, like `CoachEngine`. No em dashes in user-facing copy.

public enum CoachTutorial {
    /// Buddy's opening turns, rendered as coach chat bubbles.
    ///
    /// - Parameters:
    ///   - context: the day's state, so the copy never promises run analysis on a
    ///     day-one install that has no runs to analyze.
    ///   - connected: whether an AI key is connected. When false the closing turn
    ///     names the connect step instead of inviting a question.
    public static func openingTurns(for context: TodayState, connected: Bool) -> [String] {
        var turns: [String] = [
            "Hi, I'm Buddy, your running coach. I'm here to help you move more consistently and build running fitness without getting hurt."
        ]

        turns.append(dataTurn(for: context))

        turns.append(
            "I can't see how you're feeling unless you tell me, so mention sore legs, bad sleep, or a stressful week and I'll factor it in. I'm not a doctor, so anything sharp or persistent is one for a professional."
        )

        turns.append(
            connected
                ? "Tap one of the questions below to get started, or just type your own."
                : "Connect your own AI key in Settings and we can talk properly. Here are the kinds of things you'll be able to ask."
        )

        return turns
    }

    /// What Buddy can actually see today. Adapts to a day-one state so it never
    /// promises analysis of runs that do not exist yet.
    private static func dataTurn(for context: TodayState) -> String {
        var visible: [String] = ["today's steps and movement"]

        if !context.workouts.isEmpty || context.latestWorkout != nil {
            visible.append("your recent runs and walks")
        }
        if context.weeklyLoad != nil || !context.loadHistory.isEmpty {
            visible.append("how hard your week has been")
        }
        if !context.journal.isEmpty {
            visible.append("your check ins")
        }
        if !context.races.isEmpty {
            visible.append("any races you've added")
        }

        let list = sentenceList(visible)

        if context.workouts.isEmpty && context.latestWorkout == nil {
            return "Right now I can see \(list). Once you log a few runs I'll be able to talk about pace, mileage, and recovery too."
        }
        return "I can see \(list), so my answers are about your actual week, not generic advice."
    }

    /// "a", "a and b", "a, b, and c" — plain English, no trailing separator.
    private static func sentenceList(_ items: [String]) -> String {
        switch items.count {
        case 0:  return "nothing yet"
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }
}
