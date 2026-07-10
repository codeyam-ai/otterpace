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
    case raceGoal           // "make me a plan for my October half"
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
        // Race wording routes to dedicated race coaching. Kept AFTER injury/mileage
        // so safety routing is never overridden, and the keywords avoid the
        // step-goal terms ("10k"/"5k") that belong to .hit10K.
        if has(["marathon", "race", "taper", "goal race", "race plan", "race day"]) {
            return .raceGoal
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
    public static func reply(to question: String, context: TodayState, asOf today: String = "") -> CoachReply {
        let day = resolvedToday(today, context)
        switch CoachIntent.classify(question) {
        case .injuryPain:        return injuryReply(context)
        case .mileageTooFast:    return mileageReply(context)
        case .hit10K:            return stepsReply(context)
        case .runOrRest:         return runOrRestReply(context)
        case .postRunReflection: return reflectionReply(context)
        case .raceGoal:          return raceReply(context, asOf: day)
        case .general:           return generalReply(context, asOf: day)
        }
    }

    /// Build the deterministic Today-dashboard nudge from the day's state. This is
    /// the honest, computed encouragement every user sees with no AI key required
    /// (analysis, not pretend reasoning) — distinct from `reply(to:context:)`, which
    /// is a chat answer. A scenario's seeded `rbCoachHeadline` still overrides this.
    public static func dailyNudge(for c: TodayState, asOf today: String = "") -> CoachRecommendation {
        let day = resolvedToday(today, c)
        // Safety first: a spiking weekly load pulls the nudge toward caution.
        if let l = c.weeklyLoad, l.loadTrend == "spiking" {
            return CoachRecommendation(
                buddyMood: "recovery",
                headline: "Ease up this week",
                body: "Your weekly load is climbing, about \(miles(l.weeklyMileage)) mi so far. Hold steady or pull back about 10% and keep runs easy, so the work settles into fitness instead of soreness.",
                recommendationType: "caution",
                safetyFlag: true)
        }
        // A recent hard effort means today is for recovery.
        if ranHardRecently(c) {
            return CoachRecommendation(
                buddyMood: "recovery",
                headline: "Recover today",
                body: "After that recent effort, an easy 20 to 40 minute walk or some light mobility is the move. That's how hard work turns into fitness.",
                recommendationType: "rest")
        }
        // Goal met for the day.
        let remaining = max(0, c.goalSteps - c.steps)
        if remaining == 0 {
            return CoachRecommendation(
                buddyMood: "celebrating",
                headline: "Goal crushed, nice work!",
                body: "You cleared \(formatted(c.goalSteps)) steps today. Anything more is a bonus, so a gentle walk to loosen up is plenty.",
                recommendationType: "celebrate")
        }
        // Not enough history to read the load yet — be honest and keep it safe
        // rather than emitting a confident verdict. "No coaching over bad coaching."
        if historyThin(c) {
            return CoachRecommendation(
                buddyMood: "ready",
                headline: "Still learning your week",
                body: "I'm still gathering enough history to read your training trend, so no strong verdict today. Easy movement is always a safe call, so a relaxed walk or gentle jog fits nicely. A couple more weeks and I'll have a real read.",
                recommendationType: "walk")
        }
        // A race on the calendar frames the day.
        if let clause = raceClause(c, asOf: day) {
            return CoachRecommendation(
                buddyMood: "ready",
                headline: "Eyes on race day",
                body: clause,
                recommendationType: "run")
        }
        // A declared build that's progressing (not a true spike, caught above) is
        // the plan working — affirm it instead of nudging toward rest.
        if isBuilding(c) && (trend(c) == "building" || trend(c) == "steady") {
            return CoachRecommendation(
                buddyMood: "ready",
                headline: "Your build is on track",
                body: "You're building, and it's climbing the right way. Keep today's movement easy and consistent, that steady progression is exactly how the fitness comes without the injury tax.",
                recommendationType: "run")
        }
        // Otherwise, a gentle nudge toward the step goal. For a walking-focused
        // user (their onboarding profile lists no other training), frame the walk
        // as their real training rather than a warm-up. Safety-neutral copy only.
        let minutes = max(8, Int((Double(remaining) / 110.0).rounded()))
        let walkingFocused = c.profile.map { !$0.isEmpty && $0.otherTraining.isEmpty } ?? false
        let body = walkingFocused
            ? "A relaxed \(minutes)-minute walk gets you to \(formatted(c.goalSteps)). Walking is your training, so keep it easy and steady, that's exactly what builds the habit."
            : "A relaxed \(minutes)-minute walk gets you to \(formatted(c.goalSteps)). Keep it light and consistent, that's what builds the habit."
        return CoachRecommendation(
            buddyMood: "ready",
            headline: "\(formatted(remaining)) steps to go",
            body: body,
            recommendationType: "walk")
    }

    /// The "today" date used for race math: an explicit override wins, else the
    /// context's own date, else the system date (only hit in production / when no
    /// race is set, so determinism for the no-race tests is preserved).
    private static func resolvedToday(_ asOf: String, _ c: TodayState) -> String {
        if !asOf.isEmpty { return asOf }
        if !c.date.isEmpty { return c.date }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    /// Race-aware coaching clause for the soonest upcoming race, or nil when none.
    /// Phase-based: race day, taper week (<=7d), sharpen (<=21d), build (>21d).
    private static func raceClause(_ c: TodayState, asOf today: String) -> String? {
        guard let race = RaceGoal.next(in: c.races, asOf: today),
              let days = RaceGoal.daysUntil(date: race.date, asOf: today) else { return nil }
        if days <= 0 {
            return "Race day for your \(race.name). Keep it calm, trust your training, and run your plan. You've done the work."
        }
        if days <= 7 {
            return "Your \(race.name) is in \(days) day\(days == 1 ? "" : "s"). This is taper time: keep runs short and easy, prioritize sleep, and trust the work you've banked."
        }
        if days <= 21 {
            return "Your \(race.name) is about \(days) days out. Sharpen gently now, but don't cram. A little quality, plenty of easy."
        }
        return "You've got \(miles(race.distanceMiles)) mi at \(race.name) in \(days) days. Plenty of runway: build gradually, about 10% a week, and keep most runs easy."
    }

    private static func raceReply(_ c: TodayState, asOf today: String) -> CoachReply {
        if let clause = raceClause(c, asOf: today) {
            return CoachReply(intent: .raceGoal, text: clause, mood: .ready)
        }
        let text = "Tell me about your race in Settings — the name, distance, and date — and I'll build your training toward it, then ease you off as it nears. What are you aiming at?"
        return CoachReply(intent: .raceGoal, text: text, mood: .ready)
    }

    // Use the data we have, but never push through warning signs. A recent hard
    // run or a spiking weekly load tilts every recommendation toward recovery.
    private static func ranHardRecently(_ c: TodayState) -> Bool {
        if let w = c.latestWorkout, w.type == "run", w.distanceMiles >= 5 { return true }
        if let l = c.weeklyLoad, l.loadTrend == "spiking" { return true }
        return false
    }

    // MARK: Intent + trend awareness
    //
    // The declared training phase and the honest "insufficient history" trend let
    // the offline coach mirror the LLM: affirm an intentional build instead of
    // reflexively advising rest, and abstain plainly when the data is too thin to
    // judge. A TRUE spike (new baseline classifier) or a recent hard effort always
    // wins over the build framing — real safety signals are unchanged.

    /// The current weekly-load trend, or "" when no weekly load is present.
    private static func trend(_ c: TodayState) -> String { c.weeklyLoad?.loadTrend ?? "" }

    /// True when the user declared they're in a build. Ground truth the numbers
    /// alone can't supply.
    private static func isBuilding(_ c: TodayState) -> Bool { c.profile?.trainingPhase == .building }

    /// True when there isn't enough history to judge the load trend honestly.
    private static func historyThin(_ c: TodayState) -> Bool { trend(c) == "insufficient" }

    // MARK: Intent replies

    private static func injuryReply(_ c: TodayState) -> CoachReply {
        let text = "I can't diagnose injuries, so let's play it safe. If the pain is sharp, persistent, or getting worse, see a clinician. For now, skip hard running. Rest, gentle walking, and light mobility are the right call until it settles, and we'll ease back in once you're pain-free."
        return CoachReply(intent: .injuryPain, text: text, mood: .concerned, safetyFlag: true)
    }

    private static func mileageReply(_ c: TodayState) -> CoachReply {
        // A genuine spike (baseline classifier) still wins, phase or not.
        if let l = c.weeklyLoad, l.loadTrend == "spiking" {
            let text = "Your weekly load is climbing fast, about \(miles(l.weeklyMileage)) mi this week. That's where injury risk creeps in, so let's hold steady or pull back about 10% next week and keep most runs easy. How's recovery feeling right now?"
            return CoachReply(intent: .mileageTooFast, text: text, mood: .concerned, safetyFlag: true)
        }
        // Not enough weeks logged to judge honestly. Say so instead of guessing.
        if historyThin(c) {
            let text = "Honest answer: I don't have enough weeks logged yet to tell if you're ramping too fast. I'm still learning your normal week. Keep recent runs easy and add mileage gradually, and once we've got a few weeks in I'll flag it clearly if anything climbs too quickly. How many days a week are you running right now?"
            return CoachReply(intent: .mileageTooFast, text: text, mood: .ready)
        }
        // A declared build with a modest, non-spiking rise is the plan working, not
        // a warning. Affirm it rather than nudging toward rest.
        if isBuilding(c) {
            let text = "You're in a build, and the numbers back it up. A steady climb of around 10% a week is the plan working, not a red flag. Keep most runs easy and let only the hard days be hard, and this is exactly how fitness comes without the injury tax. How are the legs handling the load?"
            return CoachReply(intent: .mileageTooFast, text: text, mood: .ready)
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
        // Thin history: don't hand out a confident yes/no. Defer to how they feel.
        if historyThin(c) {
            let text = "I'm still learning your training pattern, so I won't give you a hard yes or no. If you slept well and feel good, an easy run is fine. If you're at all unsure, a brisk walk is never the wrong call. How are the legs today?"
            return CoachReply(intent: .runOrRest, text: text, mood: .ready)
        }
        // In a build, today's easy run fits the plan — frame it that way.
        if isBuilding(c) {
            let text = "Since you're building, today's easy run fits the plan. Keep it conversational and controlled, not a test of fitness. If the legs feel heavy or sleep was short, swap in a brisk walk with no guilt. How are they feeling?"
            return CoachReply(intent: .runOrRest, text: text, mood: .ready)
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

    private static func generalReply(_ c: TodayState, asOf today: String) -> CoachReply {
        if ranHardRecently(c) {
            let text = "After that recent effort, today is an easy movement day. Go for 30 to 45 minutes of walking and some light mobility. That's how hard work turns into fitness instead of soreness. How are you feeling after it?"
            return CoachReply(intent: .general, text: text, mood: .recovery)
        }
        // Thin history: keep it simple and safe rather than inventing a verdict.
        if historyThin(c) {
            let text = "We're still early in your data, so I'll keep it simple and safe. Get some easy movement in today, a relaxed walk or gentle jog, nothing that leaves you wiped. Give it a couple weeks and I'll have a real read on your trends. What feels doable today?"
            return CoachReply(intent: .general, text: text, mood: .ready)
        }
        // A fresh user with a race on the calendar gets race-phase framing as their
        // "what should I do today" answer. Safety (recovery, above) still wins.
        if let clause = raceClause(c, asOf: today) {
            return CoachReply(intent: .general, text: clause, mood: .ready)
        }
        // In a declared build with no warning signs, affirm the trajectory.
        if isBuilding(c) {
            let text = "You're building, and it's going the right way. Today is about easy, consistent movement that supports the work, a relaxed walk or easy run with something left in the tank. Steady beats heroic every time. What are you leaning toward today?"
            return CoachReply(intent: .general, text: text, mood: .ready)
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
