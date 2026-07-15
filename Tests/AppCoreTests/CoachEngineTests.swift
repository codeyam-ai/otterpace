import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class CoachEngineTests: XCTestCase {

    // MARK: Helpers

    private func freshState(steps: Int = 6000, goal: Int = 10000) -> TodayState {
        TodayState(healthKitConnected: true, steps: steps, goalSteps: goal)
    }

    private func hardRunState() -> TodayState {
        var s = TodayState(healthKitConnected: true, steps: 5400, goalSteps: 10000)
        s.latestWorkout = LatestWorkout(type: "run", distanceMiles: 8.1, durationMinutes: 77,
                                        pace: "9:30/mi", date: "2026-06-21", source: "strava")
        s.weeklyLoad = WeeklyLoad(weeklyMileage: 22, daysRunThisWeek: 4, longestRunMiles: 8.1,
                                  restDaysThisWeek: 1, loadTrend: "spiking")
        return s
    }

    // MARK: classify

    // Genuine pain/injury wording routes to the injury intent regardless of other
    // words. Mild soreness is handled separately (see testClassifySorenessVsPain).
    func testClassifyInjuryWins() {
        XCTAssertEqual(CoachIntent.classify("My knee hurts after my run"), .injuryPain)
        XCTAssertEqual(CoachIntent.classify("sharp pain in my shin"), .injuryPain)
        XCTAssertEqual(CoachIntent.classify("I tweaked my ankle"), .injuryPain)
    }

    // Ordinary post-run soreness is normal training feedback, split out from real
    // pain: "sore/tight/stiff" routes to the calm soreness intent, while sharp or
    // worsening pain still routes to the full injury lockdown.
    func testClassifySorenessVsPain() {
        XCTAssertEqual(CoachIntent.classify("my legs are a little sore after Sunday's run"), .postRunSoreness)
        XCTAssertEqual(CoachIntent.classify("calves feel tight today"), .postRunSoreness)
        XCTAssertEqual(CoachIntent.classify("my shin is sore"), .postRunSoreness)
        XCTAssertEqual(CoachIntent.classify("sharp pain in my knee that's getting worse"), .injuryPain)
    }

    // Mileage-ramp wording routes to the mileage intent.
    func testClassifyMileage() {
        XCTAssertEqual(CoachIntent.classify("Am I increasing mileage too fast?"), .mileageTooFast)
        XCTAssertEqual(CoachIntent.classify("worried I might overtrain"), .mileageTooFast)
    }

    // Step-goal wording routes to the hit-10K intent.
    func testClassifySteps() {
        XCTAssertEqual(CoachIntent.classify("How do I get to 10K steps?"), .hit10K)
        XCTAssertEqual(CoachIntent.classify("need more steps today"), .hit10K)
    }

    // Run-vs-rest wording routes to the run-or-rest intent.
    func testClassifyRunOrRest() {
        XCTAssertEqual(CoachIntent.classify("Can I run today or should I rest?"), .runOrRest)
        XCTAssertEqual(CoachIntent.classify("is today a good day off"), .runOrRest)
    }

    // Reflection wording routes to the reflection intent.
    func testClassifyReflection() {
        XCTAssertEqual(CoachIntent.classify("How did my run go?"), .postRunReflection)
        XCTAssertEqual(CoachIntent.classify("rate my last run"), .postRunReflection)
    }

    // Anything unrecognized falls back to the general intent.
    func testClassifyGeneralFallback() {
        XCTAssertEqual(CoachIntent.classify("what should I do today?"), .general)
        XCTAssertEqual(CoachIntent.classify("hi buddy"), .general)
    }

    // MARK: reply — safety

    // An injury question is always safety-flagged, concerned, and never diagnoses.
    func testInjuryReplyIsSafetyFlagged() {
        let r = CoachEngine.reply(to: "my knee hurts", context: freshState())
        XCTAssertEqual(r.intent, .injuryPain)
        XCTAssertTrue(r.safetyFlag)
        XCTAssertEqual(r.mood, .concerned)
        XCTAssertTrue(r.text.lowercased().contains("clinician"))
        XCTAssertFalse(r.text.lowercased().contains("diagnos") && !r.text.lowercased().contains("can't"))
    }

    // Mild post-run soreness gets calm, normal-training reassurance: no safety
    // flag and not the concerned mood (the "too much safety mode" fix).
    func testSorenessReplyIsCalmNotFlagged() {
        let r = CoachEngine.reply(to: "my legs are a little sore after my run", context: freshState())
        XCTAssertEqual(r.intent, .postRunSoreness)
        XCTAssertFalse(r.safetyFlag)
        XCTAssertNotEqual(r.mood, .concerned)
        XCTAssertTrue(r.text.lowercased().contains("normal"))
    }

    // Genuine, worsening pain still triggers the full clinician-caution lockdown.
    func testRealPainStillLocksDown() {
        let r = CoachEngine.reply(to: "sharp pain in my knee, getting worse", context: freshState())
        XCTAssertEqual(r.intent, .injuryPain)
        XCTAssertTrue(r.safetyFlag)
        XCTAssertEqual(r.mood, .concerned)
        XCTAssertTrue(r.text.lowercased().contains("clinician"))
    }

    // A spiking weekly load makes the mileage answer cautionary and safety-flagged.
    func testMileageReplySpikingIsCaution() {
        let r = CoachEngine.reply(to: "am I ramping too fast?", context: hardRunState())
        XCTAssertEqual(r.intent, .mileageTooFast)
        XCTAssertTrue(r.safetyFlag)
        XCTAssertEqual(r.mood, .concerned)
    }

    // With a steady load the mileage answer is reassuring, not flagged.
    func testMileageReplySteadyIsReassuring() {
        let r = CoachEngine.reply(to: "am I ramping too fast?", context: freshState())
        XCTAssertEqual(r.intent, .mileageTooFast)
        XCTAssertFalse(r.safetyFlag)
    }

    // MARK: reply — run vs rest

    // After a hard run / spiking load, run-or-rest leans to recovery.
    func testRunOrRestAfterHardRunIsRecovery() {
        let r = CoachEngine.reply(to: "should I run or rest?", context: hardRunState())
        XCTAssertEqual(r.intent, .runOrRest)
        XCTAssertEqual(r.mood, .recovery)
        XCTAssertFalse(r.safetyFlag)
    }

    // When fresh, run-or-rest allows an easy run.
    func testRunOrRestWhenFreshAllowsRun() {
        let r = CoachEngine.reply(to: "should I run or rest?", context: freshState())
        XCTAssertEqual(r.mood, .ready)
    }

    // MARK: reply — steps

    // Below goal, the steps answer names the remaining steps and stays ready.
    func testStepsReplyBelowGoal() {
        let r = CoachEngine.reply(to: "how do I hit 10k steps?", context: freshState(steps: 6400, goal: 10000))
        XCTAssertEqual(r.intent, .hit10K)
        XCTAssertTrue(r.text.contains("3,600"))
        XCTAssertEqual(r.mood, .ready)
    }

    // At or past goal, the steps answer celebrates instead of nudging.
    func testStepsReplyGoalReachedCelebrates() {
        let r = CoachEngine.reply(to: "more steps?", context: freshState(steps: 11000, goal: 10000))
        XCTAssertEqual(r.mood, .celebrating)
    }

    // MARK: reply — reflection

    // Reflection with a logged workout cites the run and is upbeat.
    func testReflectionWithWorkout() {
        let r = CoachEngine.reply(to: "how did my run go?", context: hardRunState())
        XCTAssertEqual(r.intent, .postRunReflection)
        XCTAssertEqual(r.mood, .cheering)
        XCTAssertTrue(r.text.contains("8.1"))
    }

    // MARK: dailyNudge — the computed Today-dashboard nudge (no key required)

    // A recent GENUINELY hard run (a long effort) with no weekly-load spike, so
    // the recovery branch is reached without the spiking-load caution
    // short-circuiting it first. Distance clears the raised hard-effort bar.
    private func recentHardRunState() -> TodayState {
        var s = TodayState(healthKitConnected: true, steps: 5200, goalSteps: 10000)
        s.latestWorkout = LatestWorkout(type: "run", distanceMiles: 10.5, durationMinutes: 95,
                                        pace: "9:10/mi", date: "2026-06-21", source: "healthkit")
        return s
    }

    // An easy mid-distance run with no spike. Under the raised hard-effort bar
    // this is NOT "hard", so it must not force a recovery day.
    private func easyFiveMilerState() -> TodayState {
        var s = TodayState(healthKitConnected: true, steps: 6000, goalSteps: 10000)
        s.latestWorkout = LatestWorkout(type: "run", distanceMiles: 5.0, durationMinutes: 52,
                                        pace: "10:20/mi", date: "2026-06-21", source: "healthkit")
        return s
    }

    // Goal met → a celebratory nudge, never safety-flagged.
    func testDailyNudgeGoalMetCelebrates() {
        let n = CoachEngine.dailyNudge(for: freshState(steps: 11240, goal: 10000))
        XCTAssertEqual(n.recommendationType, "celebrate")
        XCTAssertEqual(n.buddyMood, "celebrating")
        XCTAssertFalse(n.safetyFlag)
        XCTAssertTrue(n.headline.lowercased().contains("crushed"))
    }

    // A spiking weekly load takes priority and yields a safety-flagged caution.
    func testDailyNudgeSpikingLoadIsCaution() {
        let n = CoachEngine.dailyNudge(for: hardRunState())
        XCTAssertEqual(n.recommendationType, "caution")
        XCTAssertTrue(n.safetyFlag)
        XCTAssertEqual(n.buddyMood, "recovery")
    }

    // A recent hard run with no spike → a recovery/rest nudge, not flagged.
    func testDailyNudgeRecentHardRunIsRest() {
        let n = CoachEngine.dailyNudge(for: recentHardRunState())
        XCTAssertEqual(n.recommendationType, "rest")
        XCTAssertEqual(n.buddyMood, "recovery")
        XCTAssertFalse(n.safetyFlag)
    }

    // Below goal with nothing else going on → a gentle walk nudge that names the
    // remaining steps, so the dashboard always has an honest, computed message.
    func testDailyNudgeBelowGoalNudgesWalk() {
        let n = CoachEngine.dailyNudge(for: freshState(steps: 6400, goal: 10000))
        XCTAssertEqual(n.recommendationType, "walk")
        XCTAssertEqual(n.buddyMood, "ready")
        XCTAssertTrue(n.headline.contains("3,600"))
    }

    // A walking-focused profile (onboarding shared, no other training) personalizes
    // the below-goal walk nudge: same recommendation + steps, but copy that treats
    // walking as their training. Stays safety-neutral (not flagged).
    func testDailyNudgeWalkingFocusedProfilePersonalizes() {
        var s = freshState(steps: 6400, goal: 10000)
        s.profile = CoachProfile(walkVolume: .mostDays, walkTime: .mornings, otherTraining: [])
        let n = CoachEngine.dailyNudge(for: s)
        XCTAssertEqual(n.recommendationType, "walk")
        XCTAssertFalse(n.safetyFlag)
        XCTAssertTrue(n.headline.contains("3,600"))
        XCTAssertTrue(n.body.lowercased().contains("walking is your training"))
    }

    // With no profile (or another-training profile), the walk nudge keeps its
    // original generic copy — the personalization is additive, not a rewrite.
    func testDailyNudgeWithoutWalkingFocusKeepsGenericCopy() {
        let plain = CoachEngine.dailyNudge(for: freshState(steps: 6400, goal: 10000))
        XCTAssertFalse(plain.body.lowercased().contains("walking is your training"))

        var withRunning = freshState(steps: 6400, goal: 10000)
        withRunning.profile = CoachProfile(walkVolume: .someDays, otherTraining: [.running])
        let n = CoachEngine.dailyNudge(for: withRunning)
        XCTAssertFalse(n.body.lowercased().contains("walking is your training"))
    }

    // MARK: intent-awareness + honest abstention (trustworthy coaching)

    // A declared build with a modest, non-spiking rise. No hard run and no spike,
    // so the phase-affirming branch is reached.
    private func buildingState() -> TodayState {
        var s = TodayState(healthKitConnected: true, steps: 7000, goalSteps: 10000)
        s.weeklyLoad = WeeklyLoad(weeklyMileage: 22, daysRunThisWeek: 4, longestRunMiles: 8,
                                  restDaysThisWeek: 2, loadTrend: "building")
        s.profile = CoachProfile(trainingPhase: .building)
        return s
    }

    // Too little history to judge: the honest "insufficient" trend, no hard run.
    private func insufficientState() -> TodayState {
        var s = TodayState(healthKitConnected: true, steps: 6000, goalSteps: 10000)
        s.weeklyLoad = WeeklyLoad(weeklyMileage: 9, daysRunThisWeek: 2, longestRunMiles: 3.5,
                                  restDaysThisWeek: 5, loadTrend: "insufficient")
        return s
    }

    // A declared build that is ALSO a genuine spike — safety must still win.
    private func buildingButSpikingState() -> TodayState {
        var s = TodayState(healthKitConnected: true, steps: 6000, goalSteps: 10000)
        s.weeklyLoad = WeeklyLoad(weeklyMileage: 34, daysRunThisWeek: 5, longestRunMiles: 12,
                                  restDaysThisWeek: 0, loadTrend: "spiking")
        s.profile = CoachProfile(trainingPhase: .building)
        return s
    }

    // A declared build with a modest rise affirms the build instead of advising
    // rest — the reported bug fixed — and is not safety-flagged.
    func testMileageReplyBuildingPhaseAffirms() {
        let r = CoachEngine.reply(to: "am I ramping too fast?", context: buildingState())
        XCTAssertEqual(r.intent, .mileageTooFast)
        XCTAssertFalse(r.safetyFlag)
        XCTAssertEqual(r.mood, .ready)
        XCTAssertTrue(r.text.lowercased().contains("build"))
    }

    // A genuine spike overrides the declared build: caution and the safety flag win.
    func testMileageReplyBuildingPhaseYieldsToSpike() {
        let r = CoachEngine.reply(to: "am I ramping too fast?", context: buildingButSpikingState())
        XCTAssertTrue(r.safetyFlag)
        XCTAssertEqual(r.mood, .concerned)
    }

    // With thin history the mileage answer abstains honestly rather than guessing,
    // and is not safety-flagged.
    func testMileageReplyInsufficientAbstains() {
        let r = CoachEngine.reply(to: "am I ramping too fast?", context: insufficientState())
        XCTAssertEqual(r.intent, .mileageTooFast)
        XCTAssertFalse(r.safetyFlag)
        XCTAssertTrue(r.text.lowercased().contains("enough"))
    }

    // Run-or-rest under thin history defers to how the user feels, not a hard verdict.
    func testRunOrRestInsufficientDefers() {
        let r = CoachEngine.reply(to: "should I run or rest?", context: insufficientState())
        XCTAssertEqual(r.intent, .runOrRest)
        XCTAssertEqual(r.mood, .ready)
        XCTAssertTrue(r.text.lowercased().contains("still learning"))
    }

    // The general "what should I do" answer under thin history keeps it simple and safe.
    func testGeneralReplyInsufficientKeepsSafe() {
        let r = CoachEngine.reply(to: "what should I do today?", context: insufficientState())
        XCTAssertEqual(r.intent, .general)
        XCTAssertEqual(r.mood, .ready)
    }

    // dailyNudge under thin history is an honest "still learning" nudge, never flagged.
    func testDailyNudgeInsufficientIsHonest() {
        let n = CoachEngine.dailyNudge(for: insufficientState())
        XCTAssertFalse(n.safetyFlag)
        XCTAssertTrue(n.headline.lowercased().contains("still learning"))
    }

    // dailyNudge in a declared, progressing build affirms the trajectory (a run-day
    // "on track" nudge), not a rest nudge, and is not flagged.
    func testDailyNudgeBuildingPhaseAffirms() {
        let n = CoachEngine.dailyNudge(for: buildingState())
        XCTAssertEqual(n.recommendationType, "run")
        XCTAssertFalse(n.safetyFlag)
        XCTAssertTrue(n.headline.lowercased().contains("build"))
    }

    // MARK: raised hard-run bar + turn-aware check-in (conversational coaching)

    // A routine easy 5-miler is no longer treated as a hard effort, so the general
    // answer stays go-ahead coaching instead of a forced recovery day.
    func testEasyFiveMilerIsNotHard() {
        let r = CoachEngine.reply(to: "what should I do today?", context: easyFiveMilerState())
        XCTAssertEqual(r.intent, .general)
        XCTAssertNotEqual(r.mood, .recovery)
    }

    // A genuinely hard (long) run with no spike still steers to recovery, so the
    // guardrail is dialed back, not removed.
    func testGenuinelyHardRunStillRecovers() {
        let r = CoachEngine.reply(to: "what should I do today?", context: recentHardRunState())
        XCTAssertEqual(r.intent, .general)
        XCTAssertEqual(r.mood, .recovery)
    }

    // The closing check-in question rotates across turns: a follow-up where the
    // coach already asked its first check-in must not repeat that same question.
    func testCheckInRotatesAcrossTurns() {
        let fresh = freshState()
        let first = CoachEngine.reply(to: "should I run or rest?", context: fresh)
        XCTAssertTrue(first.text.contains("How are the legs feeling?"))

        let history = [
            CoachTurn(role: .user, text: "should I run or rest?"),
            CoachTurn(role: .coach, text: first.text),
        ]
        let second = CoachEngine.reply(to: "and what about tomorrow?", context: fresh, history: history)
        XCTAssertFalse(second.text.contains("How are the legs feeling?"))
    }
}
