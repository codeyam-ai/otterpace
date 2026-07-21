---
title: "Elapsed-Aware Weekly View"
mode: ui
createdAt: "2026-07-21T00:00:00Z"
source: manual
---

## Summary

The weekly view treats a partial week as if it were finished. `ActivityHistory.groupByWeek` computes `restDays = max(0, 7 - activeDays)` against a hardcoded 7, so on a Tuesday with one run the app reports 6 rest days, and `WeeklyReviewEngine.isSparse` (`daysRunThisWeek <= 1`) then classifies the week as sparse and shows "A quiet week, that's okay". Future days that have not happened yet are being counted as rest days the user chose to take. The Monday reset compounds it: a strong Saturday and Sunday disappear from "this week" at midnight Monday, so the view can look empty right after a heavy weekend.

This plan makes the calendar week elapsed-aware (rest days and sparseness measured only over days that have actually happened, with copy that says "so far") and adds a trailing rolling-7-day rollup alongside it, so recent work is never invisible and the trend and sparseness judgments have a full window to reason over. It also strips em dashes out of user-facing copy across the app, starting with the weekly view where the density is highest.

## Key Decisions

- **Keep the Monday-start calendar week as the headline, add rolling 7 days beside it.** The fresh-start-on-Monday framing is worth keeping for motivation, so the fix is to stop pretending the week is over rather than to abandon the week concept. The rolling window covers the blind spot the Monday reset creates. Considered switching entirely to rolling 7 days; rejected because it removes the weekly reset the coaching copy is built around.
- **Elapsed days come from the existing `asOf` date, not `Date()`.** `ActivityHistory.weeklyLoad(from:asOf:)` already threads a reference date and `classifyTrend` already derives `daysElapsed` from it. Reuse that derivation rather than introducing a second clock, so everything stays pure and unit-testable and existing scenario captures stay deterministic.
- **`WeekGroup.restDays` becomes elapsed-aware only for the in-progress week.** Completed weeks in Activity History keep their honest `7 - activeDays`. Only the week containing `asOf` is capped at elapsed days. This means `groupByWeek` needs an `asOf` parameter with a `Date()` default so existing callers are unchanged.
- **Sparseness is judged over the rolling 7-day window, not the partial calendar week.** This is what actually stops the false "quiet week". A runner who ran Saturday, Sunday, and Monday is not having a quiet week on Tuesday, even though the calendar week only holds one run.
- **New fields are additive on `WeeklyLoad`, with defaults.** Adding `daysElapsedThisWeek`, `rolling7Miles`, `rolling7DaysRun` as init parameters with defaults keeps every existing construction site (tests, `RaceGoalsTests`, `CoachEngineTests`, scenario seeding) compiling untouched.
- **Em dash cleanup is scoped to string literals only.** Code comments and doc headers keep theirs; only copy the user reads gets rewritten. Roughly 55 string-literal occurrences across 20 files, concentrated in `WeeklyReviewEngine` (19) and `SettingsView` (10).

## Implementation

### 1. Make week rollups elapsed-aware

**File**: `Sources/AppCore/ActivityHistory.swift`

- Add `asOf: Date = Date()` to `groupByWeek`. For the bucket whose `weekStart` matches `asOf`'s week, compute `daysElapsed` (1 through 7, where Monday is 1) and set `restDays = max(0, daysElapsed - activeDays)`. All other buckets keep `max(0, 7 - activeDays)`.
- Add `daysElapsed: Int` to `WeekGroup` so the UI can label a partial week without recomputing the calendar. Give it a default of 7 in the initializer so existing constructions in tests still compile.
- In `weeklyLoad(from:asOf:)`, fall back to `restDaysThisWeek: current?.restDays ?? daysElapsed` instead of the hardcoded `7`, so a week with zero logged activity on a Tuesday reports 2 rest days, not 7.
- Extract the elapsed-days derivation currently inlined in `classifyTrend` (lines 177-178) into a small `daysElapsedInWeek(asOf:cal:) -> Int` helper and have both `groupByWeek` and `classifyTrend` call it. One definition of "how far into the week are we".
- Add a `rollingSevenDay(from:asOf:) -> (miles: Double, daysRun: Int, longestRunMiles: Double)` helper: filter workouts to the trailing 7 days inclusive of `asOf`, sum miles, count distinct run days, take the longest run. Uses the same `parser` and `calendar` as everything else so the date handling stays in one place.

### 2. Carry the new signals on WeeklyLoad

**File**: `Sources/AppCore/Model.swift`

- Add `daysElapsedThisWeek: Int`, `rolling7Miles: Double`, `rolling7DaysRun: Int` to `WeeklyLoad`, all with defaults in the initializer (`7`, `0`, `0`) so existing call sites are untouched. `WeeklyLoad` is `Codable`, so defaulted properties also keep decoding of older persisted payloads working.
- Populate them in `ActivityHistory.weeklyLoad(from:asOf:)` from the helpers in step 1.
- Extend the scenario seeding block (around line 236) with `rbDaysElapsedThisWeek`, `rbRolling7Miles`, `rbRolling7DaysRun` so scenarios can drive the new states directly. Note the known hazard that omitted `rb*` keys persist across scenarios, so these must be seeded explicitly in every scenario that touches weekly load, not left to fall through.

### 3. Stop calling a partial week quiet

**File**: `Sources/AppCore/WeeklyReviewEngine.swift`

- Rewrite `isSparse(_:)` to take the whole `WeeklyLoad` and judge on the rolling window: sparse when `rolling7DaysRun <= 1`. A partial calendar week with recent weekend activity no longer trips it.
- Add an early-week branch ahead of the sparse check: when `daysElapsedThisWeek <= 2` and there is some activity, route to a new `earlyWeekReview` that recaps what has happened so far and explicitly frames the week as in progress ("Two days in", "one run in the bank, five days to go") rather than delivering a verdict on a week that has barely started. This is the direct fix for the reported Tuesday behavior.
- Make `sparseReview` and `solidReview` copy elapsed-aware: where they say "N rest days", say "N rest days so far" when `daysElapsedThisWeek < 7`. The `restDaysThisWeek` value itself is already correct after step 1, this is about the sentence not implying a finished week.
- Where the recap has a rolling figure that tells a better story than the calendar week (the runner ran hard over the weekend), mention the trailing 7 days: "across the last 7 days you covered X miles".
- Keep the ordering intact: spiking still wins over everything, then insufficient, then early-week, then sparse, then solid. The safety path must not be softened by any of this.

### 4. Surface both windows in the UI

**File**: `Sources/AppCore/WeeklyLoadCard.swift`

- When `load.daysElapsedThisWeek < 7`, change the card header from "This week" to "This week so far" and label the rest-days metric "rest so far", so a 1 on Tuesday reads correctly instead of looking like a suspiciously low number.
- Add a compact footer line under the metric row showing the rolling window: "Last 7 days: X mi, N run days". Keep it visually secondary (`Typography.caption`, `Palette.subtle`) so the calendar week stays the headline.
- Extend the existing per-metric `accessibilityLabel` treatment to the new footer so VoiceOver announces both windows.

**File**: `Sources/AppCore/ActivityWeekSection.swift`

- The in-progress week's rollup line should read "N rest so far" rather than "N rest", driven by `group.daysElapsed < 7`. Update both `rollup` and `spokenRollup`.

### 5. Reduce em dashes in user-facing copy

Rewrite em dashes out of string literals only. Code comments and doc headers are out of scope. Replace with a comma, a period and a new sentence, a colon, or by restructuring the sentence, whichever reads most naturally. Do not mechanically swap every one for the same substitute, or the copy picks up a new tic in place of the old one.

**Files**, in descending density:

- `Sources/AppCore/WeeklyReviewEngine.swift` (19) — the largest concentration, and already being rewritten in step 3
- `Sources/AppCore/SettingsView.swift` (10)
- `Sources/AppCore/TrendBadge.swift`, `Sources/AppCore/PuffyBuddy.swift`, `Sources/AppCore/Notifications/MovementReminders.swift`, `Sources/AppCore/CoachEngine.swift`, `Sources/AppCore/Auth/SignInView.swift`, `Sources/AppCore/Account/SyncConsent.swift`, `Sources/AppCore/Account/AccountSyncService.swift` (2 each)
- `Sources/AppCore/WeeklyReviewFocusCallout.swift`, `Sources/AppCore/Theming/ThemeSystem.swift`, `Sources/AppCore/Strava/StravaService.swift`, `Sources/AppCore/RaceGoals.swift`, `Sources/AppCore/Onboarding/OnboardingFlowView.swift`, `Sources/AppCore/Model.swift`, `Sources/AppCore/ConnectHero.swift`, `Sources/AppCore/CodeyamIsolated/AskCoachHeaderIsolated.swift`, `Sources/AppCore/AppIconArtwork.swift`, `Sources/AppCore/ActivityHistory.swift`, `Sources/AppCore/ActivityHeatmapSection.swift` (1 each)

Note that `CoachEngineTests` and `WeeklyReviewEngineTests` assert on copy in places, so any test asserting a phrase that contained an em dash needs its expectation updated in the same pass.

### 6. Tests

**File**: `Tests/AppCoreTests/ActivityHistoryTests.swift`

- Update `testWeeklyLoadRollsUpCurrentWeek`: with `asOf` Wednesday 2026-06-24 and active days Mon and Wed, `restDaysThisWeek` should now be 1 (3 elapsed minus 2 active), not 5. The existing comment "7 - 2 active days" documents exactly the bug.
- Update `testWeeklyLoadEmptyIsRestWeek`: no workouts as of Wednesday should report 3 rest days, not 7.
- New: rest days never exceed elapsed days for the in-progress week, across Monday through Sunday reference dates.
- New: a completed prior week still reports `7 - activeDays`, so only the current week is capped.
- New: `rollingSevenDay` picks up the previous weekend from a Tuesday reference date, and excludes a workout 8 days back.
- New: rest days never go negative when two workouts land on the same day.

**File**: `Tests/AppCoreTests/WeeklyReviewEngineTests.swift`

- New, the reported bug as a regression guard: a Tuesday with one run and a busy preceding weekend must not produce the "quiet week" headline.
- New: a genuinely quiet rolling window (one run across 7 days) still produces the sparse review, so the fix does not just delete the state.
- New: early-week copy says "so far" and does not deliver a finished-week verdict.
- New: spiking still wins over the early-week branch, so the safety path is unchanged.

## Reused existing code

- `ActivityHistory.calendar` and `ActivityHistory.parser` from `Sources/AppCore/ActivityHistory.swift` (glossary entry: `ActivityHistory`) — the fixed ISO-8601 Monday-start UTC calendar and date parser. The heatmap already shares these; the rolling-window helper must too.
- `ActivityHistory.classifyTrend`'s existing `daysElapsed` derivation (lines 177-178) — already solves "how far into the week are we", just needs extracting so the rest-day math shares it.
- `ActivityHistory.groupByWeek` (glossary entry: `ActivityHistory`, test `Tests/AppCoreTests/ActivityHistoryTests.swift`) — the single bucketing path all week rollups flow through, so fixing rest days here fixes both Today and Activity History.
- `WeeklyReviewEngine.walkingFocused` / `crossTrainingClause` from `Sources/AppCore/WeeklyReviewEngine.swift` (glossary entry: `WeeklyReviewEngine`) — the existing additive-framing helpers; the new early-week review should use the same walking-focused wording rules.
- `WeeklyLoadCard.loadMetric` from `Sources/AppCore/WeeklyLoadCard.swift` (glossary entry: `WeeklyLoadCard`) — the metric cell with its accessibility treatment; reuse rather than hand-rolling the rolling-window row.
- `Typography.caption` / `Palette.subtle` from `Sources/AppCore/Theme.swift` — the established secondary-text treatment for the rolling-window footer.
- `ActivityHistory.loadHistory` (glossary entry: `ActivityHistory`) — the coach-facing multi-week series, unchanged by this plan but worth confirming stays consistent with the new rollups.

No constrained files. `codeyam-editor-dev editor classify-constrained-files` over the full candidate list returned an empty set, so there is no lean-contract or agent-config hazard here.

## Scenarios to Demonstrate

- **Tuesday with a strong weekend behind it** — the reported bug. One run logged Monday, plus runs Saturday and Sunday of the prior calendar week. Must show "This week so far", 1 rest day, a rolling-7-day line carrying the weekend miles, and must NOT say "quiet week".
- **Tuesday with genuinely nothing** — no activity in the trailing 7 days. Shows 2 rest days so far, and the sparse or gathering framing is honest here.
- **Sunday, week complete** — 7 days elapsed, header reads "This week" with no "so far", rest days computed against the full 7, calendar and rolling figures converge.
- **Monday morning, zero elapsed activity** — the fresh-start edge case. 1 day elapsed, at most 1 rest day, copy frames the week as just beginning rather than empty.
- **Spiking load mid-week** — high mileage across the rolling window on a Wednesday. The safety caution still wins over the early-week framing and the amber risk treatment still renders.
- **Two workouts on the same day, mid-week** — rest days must not go negative or double-count the day.
- **Weekly Review with the em dash pass applied** — a solid week recap that reads naturally with the em dashes removed, as a copy-quality check across all five sections.
- **Activity History with an in-progress top week** — the newest week shows "rest so far" while completed weeks below it show plain "rest".
