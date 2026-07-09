---
title: "Trustworthy, Intent-Aware Coaching"
mode: ui
createdAt: "2026-07-09T15:43:39Z"
source: manual
---

## Summary

The AI coach gives bad advice because it reasons off a pre-chewed, naive verdict instead of the real picture. `ActivityHistory.weeklyLoad` derives `loadTrend` from a single 2-point ratio (this week's mileage ÷ *last* week's; ≥1.3× = `"spiking"`), so a deliberate ramp — or any normal week following a cutback week — trips "spiking." The backend prompt (`api/coach.ts`) then tells the model *"When training load is spiking, bias toward rest,"* and hands it `loadTrend: "spiking"` in the context JSON, so it dutifully advises rest even when the user is intentionally building. The coach also has no way to know the user's intent, and no way to say "I don't have enough to judge" — so it emits confident, wrong advice instead of staying quiet. This plan makes coaching trustworthy on three fronts: (1) let the user **declare a training phase** the coach respects, (2) replace the 2-week ratio with a **multi-week baseline** so "spiking" means a genuine deviation, and (3) feed both coaches a **multi-week mileage series** and rewrite the prompt so the model *reasons* from the trajectory and **honestly abstains** when data is thin — honoring "no coaching over bad coaching."

## Key Decisions

- **Declared training phase, not just inference** (user choice) — a deliberate build is invisible in the numbers alone (a ramp and an over-reach look identical week-to-week). Adding an explicit, user-settable phase directly fixes the reported failure and gives the coach ground truth it can never derive. Phase is optional; when unset the coach falls back to data inference.
- **Overhaul the trend calc, not just the prompt** (user choice: "do both") — the naive 2-point ratio is the root defect and also feeds the offline nudge and the Weekly Review, so fixing only the LLM would leave the offline coach and the Weekly Load card still crying "spiking." Replace it with an acute-vs-chronic style baseline (this week vs. the trailing multi-week average), which distinguishes a sustained ~10%/week build (healthy) from a true one-week spike.
- **Honest abstention over confident-but-wrong** (user's stated preference) — when history is too thin to judge (e.g. < 2–3 weeks of data) or signals conflict, both the prompt and the offline engine should say so plainly rather than defaulting to rest. This is the "no coaching beats bad coaching" rule, made explicit.
- **Reuse the existing profile transport** — training phase rides on `CoachProfile` (already carried on `TodayState` into both the on-device `CoachEngine` and `api/coach.ts` with no new transport), preserving the `isEmpty` / nil-means-not-shared semantics so existing scenarios and captures are unaffected.
- **Phase is editable in Settings, not just onboarding** — a training phase changes across a season (base → build → taper → recover), so it must be adjustable any time, unlike the largely-static walk habits.

## Implementation

### 1. Add a training phase to the coach profile

**File**: `Sources/AppCore/Onboarding/CoachProfile.swift`

Add a `TrainingPhase` enum (`base`, `building`, `maintaining`, `recovering`) with a human `label` (following the existing `WalkVolume` / `TrainingKind` pattern), and add an optional `trainingPhase: TrainingPhase?` field to `CoachProfile` (nil => not shared, exactly like `walkVolume`). Include it in `init`, and update `isEmpty` to also require `trainingPhase == nil` so an all-skipped profile still stays out of the coach context. The existing `CoachProfileStore` JSON round-trip needs no change (Codable picks up the new field); a stored profile written before this change decodes with `trainingPhase == nil`.

### 2. Replace the 2-week ratio with a multi-week baseline

**File**: `Sources/AppCore/ActivityHistory.swift`

Rework the trend logic inside `weeklyLoad(from:asOf:)`. Instead of comparing only the current week to the immediately previous week, compare the current week's mileage to the trailing **multi-week average** (the prior ~3–4 completed weeks from `groupByWeek`). Classify:
- `"spiking"` only when this week meaningfully exceeds the recent baseline (e.g. acute:chronic ratio past a threshold like ~1.5×) — so a steady ~10%/week climb reads as `"building"`, not `"spiking"`.
- `"building"` for a modest, healthy rise above baseline.
- `"recovering"` for a deliberate down week.
- `"steady"` otherwise.
- With too little history to form a baseline (fewer than ~2–3 prior weeks), return a new, honest `"insufficient"` (or keep `"building"`/`"steady"` but expose an `hasEnoughHistory` signal — see decision in the editor step) so downstream coaching can abstain rather than guess.

Keep the function pure and deterministic on the same Monday-start UTC weeks. Note the mid-week caveat: the current partial week is compared against *completed* weeks, so avoid calling a partial week "recovering" purely because it's not finished yet (guard on day-of-week or scale the comparison).

**Blast radius (accepted):** `WeeklyReviewEngine`, `WeeklyLoadCard`, and `TrendBadge` all key off `loadTrend`. Verify their copy still reads correctly under the new semantics, and handle the new "insufficient / not enough history" case in `WeeklyReviewEngine` (it currently branches spiking / solid / sparse) so the weekly review can say "still gathering your baseline" rather than forcing a verdict.

### 3. Add a multi-week mileage series to the coach context

**File**: `Sources/AppCore/Model.swift`

Add a lightweight, coach-facing weekly series to `TodayState` (e.g. `loadHistory: [WeeklyLoadPoint]` where each point is `{ weekStartISO, miles, daysRun }`), derived from `ActivityHistory.groupByWeek` (reuse the existing `WeekGroup` rollups — no new math). Populate it wherever `weeklyLoad` is populated (the production HealthKit/Strava assembly path and `readState` for seeded scenarios; add an optional `rbLoadHistoryJSON` seed key mirroring `rbWorkoutsJSON`). Keep it small (cap to the last ~6–8 weeks) so it stays well under `MAX_CONTEXT_BYTES` on the backend. Default empty `[]` so existing scenarios and `.empty` are unaffected.

### 4. Rewrite the backend coach prompt to reason and abstain

**File**: `api/coach.ts`

Rewrite `SYSTEM_PROMPT` so the model reasons from the trajectory instead of obeying a flag:
- Tell it the context includes a **`loadHistory`** weekly series and an optional **`profile.trainingPhase`**. Instruct it to look at the *shape* of the last several weeks, not just this week's `loadTrend`, and to treat a declared `building` phase as intentional: a modest, progressive rise is the plan working, not a red flag — do NOT default to rest for it.
- Keep the hard safety rules, but scope the load-based caution to a **genuine** spike relative to the multi-week baseline (or a real over-reach given the declared phase), not merely "above average this week."
- Add an explicit **honesty / abstention** rule: when `loadHistory` is too thin to judge (few weeks of data) or signals genuinely conflict, say so plainly and ask a clarifying question rather than inventing a confident rest/go verdict. Honor "no coaching over bad coaching."
- Keep the em-dash ban, the 2–4 sentence style, the mood enum, and the race-awareness / personalization sections. `profile.trainingPhase` NEVER overrides the hard safety rules or a true spike.

No change to `FORMAT`, the request validation, or the response shape is required (the richer context flows through the existing `context` field automatically).

### 5. Mirror intent-awareness and abstention in the offline engine

**File**: `Sources/AppCore/CoachEngine.swift`

So the offline/no-key coach doesn't contradict the LLM:
- In `dailyNudge`, `mileageReply`, `runOrRestReply`, and `generalReply`, when `profile?.trainingPhase == .building` and the load is a *modest* rise (not a true spike under the new classifier), frame it as "the build is working, keep runs easy" rather than "ease up." A **true** spike (new baseline classifier) still wins and still advises caution.
- Add an honest branch for the new "insufficient history" case: instead of a confident recommendation, acknowledge it's still learning the user's baseline and give safe, phase-appropriate movement guidance without a hard rest/go verdict.
- `ranHardRecently` and injury/pain routing are unchanged — real safety signals always win.

### 6. Let the user set (and change) their training phase

**File**: `Sources/AppCore/SettingsView.swift`

Add a training-phase control to the AI Coach card (or a new small "Training" card, following the `racesCard` pattern) that reads/writes `CoachProfile.trainingPhase` via `CoachProfileStore` and updates `model.today.profile` so it reaches coaching immediately (mirror how `model.addRace` refreshes state). Include a "Not set / let Buddy decide" option so phase stays optional. Add a scenario seed hook consistent with the existing `rb*` seeding so the control can be captured in a chosen state.

**File**: `Sources/AppCore/Onboarding/OnboardingFlowView.swift` (and `OnboardingState.swift`)

Add an optional onboarding step to capture the initial training phase alongside the existing walk-habit questions, skippable like the others (skipped => `nil`).

## Reused existing code

- `ActivityHistory.groupByWeek` and `WeekGroup` from `Sources/AppCore/ActivityHistory.swift` (glossary: `groupByWeek`) — supplies the per-week mileage rollups for both the new baseline trend and the `loadHistory` series; no new week math.
- `CoachProfile` / `CoachProfileStore` from `Sources/AppCore/Onboarding/CoachProfile.swift` (glossary: `CoachProfile`, `CoachProfileStore`) — existing optional, on-device, `TodayState`-carried transport that already flows into both coaches; extend rather than add a new channel.
- `TodayState` + `readState` `rb*` seeding in `Sources/AppCore/Model.swift` (glossary: `TodayDashboard` area) — the established way context reaches the coaches and scenarios.
- `RemoteCoach.reply` / `CoachConfig` from `Sources/AppCore/Coach/RemoteCoach.swift` — encodes the whole `TodayState`, so the new `loadHistory` and `trainingPhase` reach `api/coach.ts` with no transport change.
- `handler` in `api/coach.ts` (glossary: `handler`, test `test/api/coach.test.ts`) — prompt/context change only; validation and response shape reused as-is.
- Settings `racesCard` + `model.addRace`/`updateRace` pattern in `Sources/AppCore/SettingsView.swift` — the template for the new editable phase control and its state refresh.
- `CoachEngine` intent replies and `ranHardRecently` in `Sources/AppCore/CoachEngine.swift` (glossary: `CoachEngine`, test `Tests/AppCoreTests/CoachEngineTests.swift`) — extend the existing branches; keep safety routing intact.

## Scenarios to Demonstrate

- **The reported bug, fixed** — a user mid-ramp with `trainingPhase = building` and a clean ~10%/week `loadHistory`: the coach affirms the build and keeps runs easy instead of advising rest.
- **A genuine spike still caught** — flat baseline for weeks, then a sudden ~1.6× jump with no declared build: coach advises caution, `safetyFlag = true`.
- **Deliberate down week** — mileage drops after a build block (`recovering`): coach frames it as smart recovery, not underperformance.
- **Honest abstention (thin data)** — only one week of history, no phase set: coach says it's still learning the user's baseline and gives safe movement guidance without a hard rest/go call — "no coaching over bad coaching" in action.
- **Phase overridden by real safety** — `trainingPhase = building` but a recent hard/long run or reported pain: safety wins, coach steers to recovery regardless of the build intent.
- **Setting the phase** — Settings training-phase control: change from "Not set" to "Building" and see it persist and reach the coach.
- **Weekly Review under new semantics** — a steady progressive build now reads as a healthy "building" week in the Weekly Load card / review, not a false "spiking" alarm.
