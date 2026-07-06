---
title: "Race Dead-State Fix"
mode: ui
createdAt: "2026-07-06T00:00:00Z"
source: manual
---

## Summary

Once a race's date passes, Otterpace falls into a **dead state around races**:

1. **The Today "add a race" banner never comes back.** `TodayDashboard.showRacePrompt`
   (`TodayView.swift:34-36`) gates on `model.today.races.isEmpty`. A finished
   (past-dated) race is still *a race*, so `races.isEmpty` is false and the banner
   stays hidden — even though the user has no *upcoming* race to train toward.
2. **Race coaching goes quiet, correctly, but with no way back.** Both
   `CoachEngine.raceClause` (`CoachEngine.swift:156`) and `WeeklyReviewEngine`
   (`WeeklyReviewEngine.swift:82`) use `RaceGoal.next(in:asOf:)`, which filters to
   `date >= today`. Once the race is past, `next` is nil and race-aware coaching
   stops — which is right on its own, but combined with (1) the user is stuck: the
   only remaining path to add a new race is buried in Settings, and the app gives
   no prompt to do so.
3. **You can create the problem yourself.** The Add/Edit Race sheet's date picker
   (`RaceEditorView.swift:106-108`) has no minimum, so a past date is freely
   selectable — you can save an already-expired "upcoming" race.

This change makes races self-healing: the Today banner reappears whenever there is
no *upcoming* race, and the editor won't let you create a past-dated one.

## Key Decisions

- **Re-gate the Today banner on "no upcoming race," not "no races at all."**
  `showRacePrompt` becomes `forceRacePrompt || (RaceGoal.next(in: races, asOf:
  todayISO) == nil && !racePromptDismissed)`. A past-only race set now shows the
  banner again, inviting the next goal. The `todayISO` value mirrors the existing
  `SettingsView.todayISO` pattern (`SettingsView.swift:447`).
- **Add a `hasUpcoming(in:asOf:)` helper on `RaceGoal`** (thin wrapper over the
  existing `next`/`upcoming`) so the banner gate reads cleanly and is unit-testable
  without a view. Keeps the pure-helper cluster that already lives in
  `RaceGoals.swift` the single source of truth for "is there an upcoming race?"
- **Enforce a minimum date of today in the race editor.** The `DatePicker` gets
  `in: todayFloor...`, so neither adding nor editing can land a race in the past.
  Editing a genuinely-past race therefore nudges its date forward — which is the
  desired recovery, not a regression.
- **Leave the coaching engines and the Settings races list untouched.** `next`'s
  future-only filter is correct (a finished race shouldn't drive taper/build
  coaching), and the Settings list already renders past races dimmed with
  edit/delete plus an always-present "Add a race" action. The dead-state is
  specifically the *Today discovery surface* + *past-date creation*, so the fix
  stays scoped to those two.
- **Goal-time (`RaceGoal.notes`) threading is explicitly OUT of scope.** It is
  confirmed unused by both engines, but wiring it into coaching is a separable
  feature, not part of unsticking the dead state. Noted for a future plan.

## Implementation

### 1. Add an `hasUpcoming` helper + tests

**File**: `Sources/AppCore/RaceGoals.swift`

Add a pure static helper beside `upcoming`/`next`:

```swift
/// True when at least one race is on or after `today`.
public static func hasUpcoming(in races: [RaceGoal], asOf today: String) -> Bool {
    next(in: races, asOf: today) != nil
}
```

**File**: `Tests/AppCoreTests/RaceGoalsTests.swift`

Add cases: empty → false; only a past race → false; a future race present → true;
a mix of past + future → true. This locks the banner-gate logic at the unit level.

### 2. Re-gate the Today "add a race" banner

**File**: `Sources/AppCore/TodayView.swift`

- Introduce a `todayISO` computed value (same `DateFormatter` shape as
  `SettingsView.todayISO`, UTC `yyyy-MM-dd`).
- Change `showRacePrompt` (lines 34-36) from `model.today.races.isEmpty` to
  `!RaceGoal.hasUpcoming(in: model.today.races, asOf: todayISO)`.
- Keep `forceRacePrompt` (the `rbShowRacePrompt` scenario seed) and the
  `!racePromptDismissed` term exactly as they are.
- Update the doc comment on `showRacePrompt` to say "no *upcoming* race" instead
  of "no races set."

### 3. Enforce a minimum date in the race editor

**File**: `Sources/AppCore/RaceEditorView.swift`

- Add a `todayFloor: Date` (start of today, UTC-consistent with the existing
  `isoFormatter`) computed once.
- Change the `DatePicker` (lines 106-108) to
  `DatePicker("", selection: $date, in: todayFloor..., displayedComponents: .date)`.
- When editing an existing race whose stored date is before today, clamp the
  initial `_date` to `todayFloor` in `init` so the bounded picker opens on a valid
  value (SwiftUI requires the selection to be inside the range).

## Scenarios (data states)

Production starts empty; each scenario seeds its own race set:

- **`today-race-prompt-banner`** (existing) — no races → banner shows. Day-one state.
- **`today-upcoming-race`** (existing/near — `today-race-prompt-banner` off + a
  future race) — banner hidden, race coaching active.
- **`today-past-race-banner-returns`** (NEW) — seed a single *past-dated* race →
  the banner should reappear (the bug's fix, made visible in the preview).
- **`settings-race-editor-min-date`** (NEW or fold into existing
  `settings-race-editor-custom-distance`) — the editor open, showing the date
  picker floored at today.

Existing `settings-races-list` continues to exercise the dimmed past-race row +
edit/delete, unchanged.
