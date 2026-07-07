---
title: "Weekly Review Picks Up Profile & Live Data"
mode: ui
createdAt: "2026-07-06T20:07:45Z"
source: manual
---

## Summary

The Weekly Review tab reads as generic, one-size-fits-all copy that ignores the
personalization the rest of the app already uses. Two root causes: (1)
`WeeklyReviewEngine` never consumes `context.profile` — its three activity
builders even take the `context` parameter and never read it — so the recap is
identical regardless of the runner's onboarding profile, unlike `CoachEngine`
and the remote coach which both personalize off it; and (2) in production the
profile (and races) are silently dropped when live Health data loads, because
`HealthKitDataSource.loadToday()` returns a `TodayState` with no `races`/`profile`
and `connect()`/`refresh()` replace `model.today` wholesale. This plan makes the
Weekly Review reflect the user's profile and stops the live-data path from wiping
the on-device profile/races, so the recap picks up real app context in both
seeded scenarios and production.

## Key Decisions

- **Personalize the recap from `context.profile`, mirroring `CoachEngine`.**
  `CoachEngine` derives `walkingFocused = c.profile.map { !$0.isEmpty && $0.otherTraining.isEmpty }`
  (CoachEngine.swift:129) to reframe copy for walking-focused users. The Weekly
  Review should adopt the same signal (plus `walkVolume` / `otherTraining`
  awareness) so its framing matches the Today coach card rather than diverging
  from it. Chosen over inventing a new personalization scheme so the two engines
  stay consistent and the profile's meaning is defined in one place.
- **Keep the engine pure, deterministic, and safety-first.** Personalization only
  adjusts prose framing; it must not change the spiking→safety precedence, the
  empty/sparse/solid classification, `safetyFlag`, or `buddyMood`. The same
  `(profile, load, races)` context must still yield an identical review
  (`testDeterministic` must keep passing).
- **Preserve on-device context across live-data loads via a merge, not a wipe.**
  Rather than teach the data source about on-device stores, merge in the model
  layer: after `loadToday()`, keep the existing in-memory `races`/`profile` when
  the fresh snapshot doesn't carry them. This is safe for seeded scenarios
  (`SeededHealthDataSource.loadToday()` returns full `readState`, so its
  races/profile win) and fixes production (HealthKit snapshot has none, so the
  launch-loaded store values survive). Chosen over unconditionally re-reading
  `RaceStore`/`CoachProfileStore` in `refresh()`, which would clobber a seeded
  scenario's `rb*` races/profile with the empty non-`rb` store values.
- **Recompute weekly load on Strava ingest.** `ingestStravaWorkouts` sets
  `workouts`/`latestWorkout` but never `weeklyLoad`, so a Strava-only user lands
  on the empty "first week starts here" recap despite visible runs. Compute it
  from the ingested workouts with the same helper the Health path uses.

## Implementation

### 1. Personalize the Weekly Review from the profile

**File**: `Sources/AppCore/WeeklyReviewEngine.swift`

The three activity builders (`solidReview`, `spikingReview`, `sparseReview`)
already receive the `context` (`c`) but ignore it; `emptyReview()` takes no
context. Thread the profile through so each review's prose reflects it:

- Derive a small, pure helper from `context.profile` mirroring `CoachEngine`'s
  intent — e.g. `walkingFocused` (`profile.map { !$0.isEmpty && $0.otherTraining.isEmpty }`),
  and optionally note `otherTraining` (e.g. "alongside your strength work") and
  `walkVolume` where it reads naturally. Keep it a private helper so it's unit-
  testable and the two engines stay conceptually aligned.
- Apply it as **framing adjustments** to the existing section strings, not new
  sections: e.g. for a walking-focused runner, `solidReview`/`sparseReview`
  should speak to walks-as-training rather than assuming running mileage is the
  point; when `otherTraining` includes cross-training, the "what changed" / risk
  copy can acknowledge it. Do not alter `spikingReview`'s safety copy in a way
  that softens the caution — personalization rides alongside the warning, never
  replaces it (same rule as `applyRaceNote`).
- Pass `context` into `emptyReview()` too (currently `emptyReview()` with no
  args) so the first-week prompt can gently reference the profile when present
  (e.g. walk cadence), while staying identical to today's copy when
  `profile == nil` / `isEmpty` so existing empty-state scenarios/captures are
  unaffected.
- Preserve determinism and the classification order in `generate(from:asOf:)`:
  profile only changes wording within the already-selected branch.

### 2. Preserve races + profile when live data loads

**File**: `Sources/AppCore/Model.swift`

`connect()` (line ~273) and `refresh()` (line ~286) both do
`today = await source.loadToday()`, discarding the `races`/`profile` attached at
launch (init loads them from `RaceStore` / `CoachProfileStore`, lines 144–148).
Add a private merge helper and route both replacements through it:

- Helper (pure): given the freshly loaded `TodayState` and the current `today`,
  return the fresh state but fall back to the existing values where the snapshot
  is empty — `races`: `fresh.races.isEmpty ? current.races : fresh.races`;
  `profile`: `fresh.profile ?? current.profile`. This keeps launch-loaded
  production values across refresh while letting a seeded scenario's fuller
  `readState` win.
- Use it in `connect()` and `refresh()` so `model.today` never loses the
  on-device profile/races, and the Weekly Review (and Today coach card / race
  banner) keep reflecting them after Health connects or a pull-to-refresh.

### 3. Recompute weekly load on Strava ingest

**File**: `Sources/AppCore/Model.swift`

In `ingestStravaWorkouts` (line ~306), after setting `today.workouts` /
`today.latestWorkout`, also set
`today.weeklyLoad = ActivityHistory.weeklyLoad(from: workouts)` (nil-guard on an
empty list, matching `HealthKitDataSource.loadToday()`'s
`history.isEmpty ? nil : …` at HealthKitDataSource.swift:77) so a Strava-only
user gets a real recap instead of the empty first-week prompt.

### 4. Tests

**File**: `Tests/AppCoreTests/WeeklyReviewEngineTests.swift`

- Add a walking-focused profile (`CoachProfile(walkVolume: .mostDays, otherTraining: [])`)
  and assert the solid/sparse recap copy differs from the no-profile baseline in
  the expected framing, while a runner-with-other-training profile reads
  differently again.
- Assert the spiking review stays safety-flagged and its clinician/caution copy
  is unchanged regardless of profile (personalization must not soften safety).
- Extend `testDeterministic` coverage to a profile-bearing context.

**File**: `Tests/AppCoreTests/ModelTests.swift`

- Test that after `refresh()` (with a seeded source) an in-memory `profile`/`races`
  set before refresh survives when the source snapshot omits them.
- Test that `ingestStravaWorkouts` populates `weeklyLoad`, so the generated
  `WeeklyReview.hasActivity` is true for a Strava-only user.

## Reused existing code

- `walkingFocused` personalization pattern from `CoachEngine.reply`/nudge logic
  (`Sources/AppCore/CoachEngine.swift:129`) — mirror it in the Weekly Review
  (glossary entry: `CoachEngine`).
- `CoachProfile` + `isEmpty` + `otherTraining`/`walkVolume`/`walkTime`
  (`Sources/AppCore/Onboarding/CoachProfile.swift`) — the personalization inputs.
- `ActivityHistory.weeklyLoad(from:asOf:)`
  (`Sources/AppCore/ActivityHistory.swift:96`) — reuse for Strava ingest, same
  as `HealthKitDataSource.loadToday()` (glossary entry: `ActivityHistory`).
- `RaceStore.load` / `CoachProfileStore.load` (`Sources/AppCore/RaceGoals.swift`,
  `Sources/AppCore/Onboarding/CoachProfile.swift`) — already used in
  `OtterpaceModel.init()`; the merge preserves what they loaded.
- `applyRaceNote` / `RaceGoal.next` in `WeeklyReviewEngine`
  (`Sources/AppCore/WeeklyReviewEngine.swift:81`) — precedent for additive,
  non-safety-overriding context folding (glossary entry: `WeeklyReviewEngine`).

## Scenarios to Demonstrate

- Walking-focused profile, solid week — recap frames walks as the training,
  distinct from the generic copy.
- Runner profile with `otherTraining: [.strength]`, solid week — recap
  acknowledges cross-training.
- No profile (`nil`) — recap copy is unchanged from today's baseline
  (regression guard for existing captures).
- Spiking week with a profile — safety caution intact; personalization only
  rides alongside.
- Profile + upcoming race, then simulate a `refresh()` — profile and race
  survive the live-data load and still shape the recap (production-parity).
- Strava-only user with imported runs — Weekly Review shows a real recap, not
  the empty "first week starts here" prompt.
