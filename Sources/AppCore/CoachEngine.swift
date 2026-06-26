import Foundation

// MARK: - Ask Coach engine
//
// The mock AI coach behind the Ask Coach chat screen. Pure, deterministic logic:
// classify a free-text question into an intent, then build a curated, context-
// aware answer from the user's `TodayState`. No network, no LLM — this is
// Milestone 2's mock mode, which keeps scenarios stable and the coach honest
// about its safety rules. Milestone 3 swaps the body of `reply(to:context:)` for
// a real model while keeping this same shape.

/// What the user is really asking. Classification is keyword-based and
/// deliberately conservative: anything ambiguous falls through to `.general`.
public enum CoachIntent: String, CaseIterable {
    case runOrRest          // "can I run or should I rest?"
    case hit10K             // "how do I get to 10k steps?"
    case mileageTooFast     // "am I increasing mileage too fast?"
    case injuryPain         // "my knee hurts after my run"
    case postRunReflection  // "how did my run go?"
    case general            // catch-all: "what should I do today?"

    /// Classify a free-text question. Injury/pain is checked first so a
    /// safety-sensitive question is never mis-routed to upbeat coaching.
    public static func classify(_ question: String) -> CoachIntent {
        let q = question.lowercased()
        func has(_ needles: [String]) -> Bool { needles.contains { q.contains($0) } }

        if has(["hurt", "pain", "sore", "ache", "injur", "knee", "shin", "tweak", "twinge", "strain"]) {
            return .injuryPain
        }
        if has(["too fast", "too much", "ramp", "increasing mileage", "mileage too", "overtrain", "overdo", "build too"]) {
            return .mileageTooFast
        }
        if has(["10k", "10,000", "10000", "step"]) {
            return .hit10K
        }
        if has(["rest", "run today", "should i run", "run or", "or rest", "easy day", "day off", "recover"]) {
            return .runOrRest
        }
        if has(["how was", "how did", "reflect", "run go", "rate my", "last run"]) {
            return .postRunReflection
        }
        return .general
    }
}

/// A single coach answer: the prose plus how Buddy should look while saying it.
public struct CoachReply: Equatable {
    public var intent: CoachIntent
    public var text: String
    public var mood: BuddyMood
    public var safetyFlag: Bool

    public init(intent: CoachIntent, text: String, mood: BuddyMood, safetyFlag: Bool = false) {
        self.intent = intent
        self.text = text
        self.mood = mood
        self.safetyFlag = safetyFlag
    }
}

public enum CoachEngine {
    /// Build a curated, context-aware reply to `question` given the day's state.
    /// Pure and deterministic — the same inputs always yield the same reply.
    public static func reply(to question: String, context: TodayState) -> CoachReply {
        switch CoachIntent.classify(question) {
        case .injuryPain:        return injuryReply(context)
        case .mileageTooFast:    return mileageReply(context)
        case .hit10K:            return stepsReply(context)
        case .runOrRest:         return runOrRestReply(context)
        case .postRunReflection: return reflectionReply(context)
        case .general:           return generalReply(context)
        }
    }

    // Use the data we have, but never push through warning signs. A recent hard
    // run or a spiking weekly load tilts every recommendation toward recovery.
    private static func ranHardRecently(_ c: TodayState) -> Bool {
        if let w = c.latestWorkout, w.type == "run", w.distanceMiles >= 5 { return true }
        if let l = c.weeklyLoad, l.loadTrend == "spiking" { return true }
        return false
    }

    // MARK: Intent replies

    private static func injuryReply(_ c: TodayState) -> CoachReply {
        let text = "I can't diagnose injuries, so let's play it safe. If the pain is sharp, persistent, or getting worse, see a clinician. For now, skip hard running. Rest, gentle walking, and light mobility are the right call until it settles, and we'll ease back in once you're pain-free."
        return CoachReply(intent: .injuryPain, text: text, mood: .concerned, safetyFlag: true)
    }

    private static func mileageReply(_ c: TodayState) -> CoachReply {
        if let l = c.weeklyLoad, l.loadTrend == "spiking" {
            let text = "Your weekly load is climbing fast, about \(miles(l.weeklyMileage)) mi this week. That's where injury risk creeps in, so let's hold steady or pull back about 10% next week and keep most runs easy. How's recovery feeling right now?"
            return CoachReply(intent: .mileageTooFast, text: text, mood: .concerned, safetyFlag: true)
        }
        let text = "Good instinct to check. Keep weekly mileage growth under about 10%, with an easier week every few weeks. You're in a reasonable range right now, so keep most runs conversational and the fitness builds without the injury tax. What's the goal for this block?"
        return CoachReply(intent: .mileageTooFast, text: text, mood: .ready)
    }

    private static func stepsReply(_ c: TodayState) -> CoachReply {
        let remaining = max(0, c.goalSteps - c.steps)
        if remaining == 0 {
            let text = "You've already cleared \(formatted(c.goalSteps)) steps today. Nice work. Anything more is a bonus, so a gentle walk to loosen up is plenty."
            return CoachReply(intent: .hit10K, text: text, mood: .celebrating)
        }
        let minutes = max(8, Int((Double(remaining) / 110.0).rounded()))
        let text = "You're \(formatted(remaining)) steps from \(formatted(c.goalSteps)). A relaxed \(minutes)-minute walk gets you there without adding real training stress, podcast optional but encouraged. No need to rush it all at once."
        return CoachReply(intent: .hit10K, text: text, mood: .ready)
    }

    private static func runOrRestReply(_ c: TodayState) -> CoachReply {
        if ranHardRecently(c) {
            let text = "Take today easy. You put in a solid effort recently, so an easy 20 to 40 minute walk or some light mobility will help that work settle into fitness. How do the legs feel today?"
            return CoachReply(intent: .runOrRest, text: text, mood: .recovery)
        }
        let text = "An easy run is on the table today. Keep it conversational, nothing heroic, and if your legs feel heavy or sleep was rough a brisk walk is a perfectly good substitute. How do the legs feel?"
        return CoachReply(intent: .runOrRest, text: text, mood: .ready)
    }

    private static func reflectionReply(_ c: TodayState) -> CoachReply {
        if let w = c.latestWorkout {
            let text = "Your last \(w.type) was \(miles(w.distanceMiles)) mi at \(w.pace), a real effort in the bank. A little tired today is normal, sharp or one-sided pain is not. How are the legs feeling after it?"
            return CoachReply(intent: .postRunReflection, text: text, mood: .cheering)
        }
        let text = "I don't see a recent run logged yet. Get one in, then ask me again and I'll help you reflect on how it went and where to go next. What are you thinking of running?"
        return CoachReply(intent: .postRunReflection, text: text, mood: .ready)
    }

    private static func generalReply(_ c: TodayState) -> CoachReply {
        if ranHardRecently(c) {
            let text = "After that recent effort, today is an easy movement day. Go for 30 to 45 minutes of walking and some light mobility. That's how hard work turns into fitness instead of soreness. How are you feeling after it?"
            return CoachReply(intent: .general, text: text, mood: .recovery)
        }
        let remaining = max(0, c.goalSteps - c.steps)
        if remaining > 0 {
            let text = "Today's a great day for easy movement. You're \(formatted(remaining)) steps from your goal, and a relaxed walk covers most of that. Keep it light and consistent, that's what builds the habit. Want to aim for a quick walk now?"
            return CoachReply(intent: .general, text: text, mood: .ready)
        }
        let text = "You're already on track today, goal met and moving well. Keep things easy and hydrate, and let's set tomorrow up to feel just as good. Anything on your mind for the week?"
        return CoachReply(intent: .general, text: text, mood: .cheering)
    }
}
