---
title: "Race Goals & Race-Aware Coaching"
mode: ui
createdAt: "2026-06-26T21:00:00Z"
source: manual
---

## Summary

Let users tell Otterpace about upcoming races — name, distance, date, and
location/site details — and feed that into Buddy's coaching so guidance becomes
goal-aware (build toward the distance early, taper near race day, race-day
framing, and a gentle "how'd it go?" after). Races are entirely optional: most
users don't have one, so the feature lives in a new **Races** card in Settings
and is surfaced by a single **dismissable banner** on the Today dashboard that
only appears when the user has no races yet and hasn't dismissed it. Races are
stored on-device (same UserDefaults pattern as `UserPreferences` /
`ReminderSettings`) and carried on `TodayState` so they flow, with zero new
plumbing, into all three coaching engines: the on-device `CoachEngine`, the
remote AI coach (`RemoteCoach` → `api/coach.ts`), and the `WeeklyReviewEngine`.

## Key Decisions

- **Carry races on `TodayState`, don't build a parallel context path.** The
  coaching context is already `model.today`: `AskCoachView` passes it to both
  `CoachEngine.reply` and `RemoteCoach.reply`, and `RemoteCoach` ships the whole
  `TodayState` to `api/coach.ts`, which stringifies it into the prompt. Adding
  `races: [RaceGoal]` to `TodayState` (default `[]`) means the AI coach gets race
  context "for free," and the on-device engines can read it directly — mirroring
  exactly how `workouts` already rides on `TodayState`.
- **Race-aware coaching = derive "the next race" + days-until, then branch.**
  Rather than scatter race logic, add one small pure helper (`RaceGoal.next(in:)`
  + a days-until computation against a passed-in "today" date) so `CoachEngine`,
  `WeeklyReviewEngine`, and the backend prompt all reason about the same notion
  of "soonest upcoming race." Keeps it pure/deterministic and unit-testable, in
  the spirit of the existing engines.
- **Presets + custom distance**, mirroring the daily-step-goal capsule + custom
  stepper already in `SettingsView` (`UserPreferences.goalOptions` + clampers).
  Distance presets: 5K, 10K, Half, Marathon, plus a Custom miles value.
- **Multiple races, list-based.** Users add/edit/delete; coaching keys off the
  soonest race whose date is today or later. Stored as a JSON array under one
  preference key (the flat `rb*` primitives can't hold a list — same reasoning as
  `rbWorkoutsJSON`).
- **Discovery via a dismissable Today banner, not a forced step.** Shown only
  when `races.isEmpty && !dismissed` (so it never nags users who don't race, and
  disappears once they add one). Dismissal persists via a tiny
  UserDefaults-backed flag modeled on the just-planned `OnboardingState`. Tapping
  the banner opens Settings (reusing the existing `onSettings` closure) — no new
  presentation surface needed.
- **Backend prompt change is additive and safety-preserving.** The race guidance
  is appended to the existing `SYSTEM_PROMPT` and explicitly subordinated to the
  existing hard safety rules (taper/goal advice never overrides pain/load
  caution), so race ambition can't push a user through warning signs.

## Implementation

### 1. Race domain model + on-device store

**New file**: `Sources/AppCore/RaceGoals.swift`

- `public struct RaceGoal: Codable, Equatable, Identifiable` with:
  `id: UUID`, `name: String`, `distanceMiles: Double`, `date: String` (ISO
  `yyyy-MM-dd`, matching `LatestWorkout.date`), `location: String` (city / venue),
  and optional `notes: String?` (the "site etc." details — start area, corral,
  goal time).
- A `RaceDistance` preset enum (`fiveK`, `tenK`, `half`, `marathon`, `custom`)
  with a `miles` value and a display label, used by the Settings editor and to
  round-trip a stored `distanceMiles` back to a preset selection. Reuse
  `UserPreferences.clampGoal`-style clamping for the custom-miles bounds (define
  `minMiles`/`maxMiles` here as the single source of truth).
- A pure helper surface on the type:
  - `RaceGoal.upcoming(in races: [RaceGoal], asOf today: String) -> [RaceGoal]`
    — races with `date >= today`, sorted soonest-first (ISO date strings sort
    lexicographically, so plain string comparison is correct and keeps it
    dependency-free).
  - `RaceGoal.next(in:asOf:) -> RaceGoal?` — the soonest upcoming race.
  - `daysUntil(date:asOf:) -> Int?` — whole days between two ISO dates (used to
    drive taper vs build vs race-week messaging). Compute via `DateFormatter`/
    `Calendar` from the ISO strings; return nil on unparseable input.
- `public enum RaceStore` mirroring `UserPreferences`/`ReminderSettings`: a
  single JSON-array key `otterpaceRaces` in an injectable `UserDefaults`, with
  `load(_:) -> [RaceGoal]`, `save(_:_:)`, `add`, `update`, and `remove(id:)`
  helpers. Encode/decode with `JSONEncoder`/`JSONDecoder` exactly like
  `OtterpaceModel.readState` does for `rbWorkoutsJSON`.

### 2. Carry races on TodayState + load them into the model

**File**: `Sources/AppCore/Model.swift`

- Add `public var races: [RaceGoal]` (default `[]`) to `TodayState`, including the
  `init` parameter (defaulted, so all existing call sites keep compiling) and the
  `Codable` round-trip (it's part of the struct, so it's automatic — and it
  therefore appears in the JSON `RemoteCoach` sends to `api/coach.ts`).
- In `OtterpaceModel.readState`, decode an optional `rbRacesJSON` preference into
  `races` (same shape as the existing `rbWorkoutsJSON` block) so scenarios can
  seed races for capture.
- In the production `convenience init()` path (the non-seeded branch), populate
  `today.races` from `RaceStore.load()` so a real user's races reach coaching
  even though they aren't part of the HealthKit snapshot. Keep `.empty` as-is
  (empty races by default).
- Add model mutators so Settings edits apply immediately and persist:
  `addRace`, `updateRace`, `removeRace(id:)` — each writes through `RaceStore`
  and updates `today.races` (mirroring `setGoalSteps`). `@MainActor`-consistent
  with the other published mutations.

### 3. Make the on-device coach race-aware

**File**: `Sources/AppCore/CoachEngine.swift`

- Add a private `raceContext(_ c: TodayState, asOf:)` helper that resolves the
  next race and days-until, and a race-aware clause woven into the existing
  intent replies — **without** weakening the current safety bias (a recent hard
  run / spiking load still tilts toward recovery first; race framing is additive):
  - **Race week (≤7 days):** taper framing — "Your {name} is in {n} days. This is
    taper time: keep runs short and easy, trust the work you've banked, prioritize
    sleep." Mood `.ready`.
  - **Approaching (8–~21 days):** sharpen-but-don't-cram framing.
  - **Building (>21 days):** "plenty of runway — build gradually (~10%/week)
    toward {distance} mi."
  - **Race day (0 days):** brief, calm race-day encouragement.
- Thread an `asOf` "today" date (default to the context's `date`, falling back to
  the system date only at the call site) so the logic stays pure/deterministic
  and testable — consistent with how the engine already takes everything from
  `context`.
- Optionally add a new `CoachIntent.raceGoal` classified from keywords
  (`race`, `marathon`, `half`, `5k`, `10k`, `taper`, `goal race`) so direct race
  questions route to dedicated copy; keep injury/mileage classification first so
  safety routing is unchanged.

### 4. Make the Weekly Review race-aware

**File**: `Sources/AppCore/WeeklyReviewEngine.swift`

- When an upcoming race exists, fold a race line into `nextWeek` and bias the
  `focusArea` toward the race phase (taper vs build), reusing the same
  `RaceGoal.next`/`daysUntil` helpers from step 1. Preserve the spiking-load
  branch's precedence — a spiking week still produces the caution review; the
  race note rides alongside as "even with {race} coming up, this is the week to
  ease off." No change to `emptyReview` beyond an optional "and you've got
  {race} on the calendar — we'll build toward it" nudge when a race is set but no
  activity yet.

### 5. Race-aware AI coach prompt

**File**: `api/coach.ts`

- Append a **Race awareness** section to `SYSTEM_PROMPT` instructing Buddy to use
  `context.races` when present: identify the soonest upcoming race, reason about
  days-until (taper in the final week, build gradually before that, calm
  encouragement on race day), reference distance/location naturally, and — stated
  explicitly — **never let race ambition override the hard safety rules** (pain,
  spiking load, and the ~10% rule still win). No schema change: races arrive
  inside the already-stringified `context`, and the reply shape is unchanged.
- This is the only backend change. `RemoteCoach`/`api` request/response shapes
  stay as-is because races travel inside the existing `TodayState` context.

### 6. Races card in Settings (add / edit / delete)

**File**: `Sources/AppCore/SettingsView.swift`

- Add a `racesCard` to the existing card stack (e.g. just below `coachCard`,
  since races feed the coach), built from the existing `card`/`row`/`actionRow`
  helpers so styling matches.
- Empty state: a one-line explainer ("Add a race and Buddy will tailor your
  coaching — building toward it, then easing off as it nears.") + an "Add a race"
  `actionRow`.
- Populated: a row per race (name, distance label, formatted date, location) with
  edit/delete affordances. Sort upcoming-first via `RaceGoal.upcoming`; show past
  races dimmed or omit them.
- Add/edit presents a lightweight editor (a `.sheet`, consistent with the
  existing `showHealthConsent` sheet pattern) with: name `TextField`, a distance
  **capsule row of presets + a Custom stepper** (clone the `goalCard` capsule +
  `Stepper` UI, swapping step-goal values for `RaceDistance` presets/miles), a
  `DatePicker` (date only) writing back the ISO `date` string, a location
  `TextField`, and an optional notes field. Save calls `model.addRace` /
  `model.updateRace`; delete calls `model.removeRace`.
- If settings sync is on, races are local-only for now (out of scope for account
  sync — call this out so the editor workflow doesn't infer a backend sync
  requirement). The daily-goal sync path is untouched.

### 7. Dismissable "add a race" banner on Today

**New file**: `Sources/AppCore/RacePromptBanner.swift`

- A small `RacePromptBanner` view in Buddy's voice ("Got a race coming up? Tell
  Buddy and I'll tailor your training.") with a primary tap action and an
  explicit dismiss (✕) affordance. Style it on the brand/gold gradient card look
  used by `WeeklyReviewFocusCallout` so it reads as a native callout, using
  `Palette`/`Typography`/`Layout`.

**File**: `Sources/AppCore/RaceGoals.swift` (or a tiny sibling enum)

- Add a `RacePromptState` UserDefaults flag (`otterpaceRacePromptDismissed`),
  modeled on `OnboardingState`: `isDismissed(_:)` / `markDismissed(_:)`, with an
  injectable `UserDefaults` for tests.

**File**: `Sources/AppCore/TodayView.swift`

- Render the banner near the top of the dashboard `VStack` (e.g. just under
  `StatsRow`), gated by `model.today.races.isEmpty && !RacePromptState.isDismissed()`
  and `previewMode`-safe like the other Today seeds. Tapping it calls the
  existing `onSettings` closure (opening Settings, where the Races card lives);
  the ✕ sets `markDismissed()` and hides it with `withAnimation(Motion.overlay)`.
- Allow a scenario seed (`rbShowRacePrompt`) to force the banner visible for
  capture even under seeding, mirroring the `rbShow*` overlay-seed convention in
  this file.

### 8. Analytics (optional, consistent with existing events)

**File**: `Sources/AppCore/SettingsView.swift` / `TodayView.swift`

- Fire `Analytics.shared.capture("race_added")` on save and
  `"race_prompt_dismissed"` on banner dismiss, guarded by `previewMode.isEmpty`
  the same way `strava_connected` / `app_opened` are. Keep it light; no PII in
  properties.

## Reused existing code

- `TodayState` + `OtterpaceModel.readState` / `convenience init()` and the
  `rbWorkoutsJSON` JSON-array seed pattern, plus the `setGoalSteps` mutator shape
  (`Sources/AppCore/Model.swift`).
- `CoachEngine` + `CoachIntent` + `CoachReply` and its "safety bias wins"
  structure (`Sources/AppCore/CoachEngine.swift`, glossary entry: `CoachEngine`)
  — races extend, never override, the existing replies.
- `WeeklyReviewEngine` / `WeeklyReview` (`Sources/AppCore/WeeklyReviewEngine.swift`).
- `RemoteCoach` (`Sources/AppCore/Coach/RemoteCoach.swift`) and `api/coach.ts`
  `SYSTEM_PROMPT` + the `TodayState`-as-context contract — unchanged transport;
  races ride the existing context.
- `SettingsView` `card` / `row` / `actionRow` helpers, the `goalCard`
  preset-capsule + custom `Stepper` UI, and the `.sheet` (`healthConsentSheet`)
  presentation pattern (`Sources/AppCore/SettingsView.swift`, glossary entry:
  `SettingsView`).
- `UserPreferences` (glossary entry: `UserPreferences`) and `ReminderSettings`
  (`Sources/AppCore/Notifications/MovementReminders.swift`) — the
  UserDefaults-backed, injectable-defaults persistence pattern `RaceStore` /
  `RacePromptState` follow.
- The `OnboardingState`-style dismissal flag (planned in
  `onboarding-welcome-tour.md`) — the precedent for a persisted "shown once /
  dismissed" UserDefaults flag.
- `WeeklyReviewFocusCallout` (`Sources/AppCore/WeeklyReviewFocusCallout.swift`,
  glossary entry: `WeeklyReviewFocusCallout`) — gradient callout styling for the
  banner.
- `TodayDashboard` overlay/seed conventions + `onSettings` closure
  (`Sources/AppCore/TodayView.swift`).
- `Analytics.shared.capture` (`Sources/AppCore/Analytics/Analytics.swift`),
  `Palette`/`Typography`/`Layout`/`Motion` (`Sources/AppCore/Theme.swift`),
  and `Formatters` (`Sources/AppCore/Formatters.swift`) for date/distance display.

## Tests

- **New** `Tests/AppCoreTests/RaceGoalsTests.swift` — pure-logic tests against an
  injected `UserDefaults` and fixed `asOf` dates: `RaceStore` round-trip
  (add/update/remove/JSON load), `upcoming`/`next` ordering and the
  today-or-later boundary, `daysUntil` math (including unparseable input → nil),
  and `RaceDistance` preset↔miles round-trip + custom clamping. Mirrors
  `ModelTests` / `ReminderSettings`-style suites.
- **New / extend** `Tests/AppCoreTests/CoachEngineTests.swift` — race-week (taper)
  vs building vs race-day branches with a fixed `asOf`, and a regression
  asserting that a spiking load / injury question still produces the
  safety-flagged reply even when a race is set (race framing never overrides
  safety).
- **Extend** the Weekly Review tests (if present) for the race-aware `nextWeek` /
  `focusArea` additions, keeping the spiking-load precedence assertion.
- The backend `api/coach.ts` change is prompt-only; if the api vitest harness has
  a coach test, add a case asserting a `context.races` payload is accepted and the
  response shape is unchanged (no schema regressions). Presentational views
  (`RacePromptBanner`, the Settings races card/editor) follow the existing
  convention of being exercised through scenarios rather than unit tests.

## Scenarios to Demonstrate

- **Today — race prompt banner**: no races set, banner visible
  (`rbShowRacePrompt=1`), inviting the user to add a race.
- **Today — banner hidden after a race exists**: `rbRacesJSON` seeded with one
  upcoming race → banner absent, normal dashboard.
- **Settings — empty Races card**: the explainer + "Add a race" action.
- **Settings — Races list**: two seeded races (e.g. a 10K in 5 days, a marathon
  in 10 weeks) sorted soonest-first with distance/date/location.
- **Settings — add/edit race editor**: the sheet open with presets + custom miles
  stepper, date picker, and location field.
- **Ask Coach — taper week**: race in 4 days seeded; ask "should I run today?" →
  Buddy gives taper guidance referencing the race.
- **Ask Coach — building phase**: race in 10 weeks; "am I increasing mileage too
  fast?" → gradual-build-toward-distance framing.
- **Ask Coach — safety still wins**: spiking weekly load **and** a race in 5 days;
  ask "should I run today?" → caution/recovery reply with the safety flag, race
  acknowledged but not overriding.
- **Weekly Review — race-aware**: a solid week with an upcoming race → `nextWeek`
  / `focusArea` reflect the race phase.
- **Race day**: a race dated today → calm race-day encouragement in the coach.
