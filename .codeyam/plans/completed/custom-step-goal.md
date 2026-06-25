---
title: "Custom Step Goal in Settings"
mode: ui
createdAt: "2026-06-25T18:32:20Z"
source: manual
---

## Summary

The **Daily step goal** card in Settings currently offers only five fixed preset
capsules — `6k 8k 10k 12k 15k` (`UserPreferences.goalOptions`). Users who want a
target that isn't one of those (e.g. 9,500 or 20,000) can't set it. This adds a
**Custom** option to the same card: tapping it reveals an inline stepper to dial in
any goal within sensible bounds, rounded to a clean increment. The custom value
persists and syncs through the exact same path the presets already use
(`model.setGoalSteps` → `UserPreferences` + optional `accountSync.pushPreferences`),
so no new storage or sync schema is needed. When the active goal isn't one of the
presets, the card shows the Custom chip as selected (with the live value) and opens
the editor automatically.

## Key Decisions

- **Stepper, not a free-text field** — a `Stepper` with a fixed increment keeps
  input on-rail (no keyboard, no parsing/garbage values, bounds enforced by
  construction) and matches the card's existing tap-only, capsule-based feel.
  Decrement/increment by **500**.
- **Reuse the existing persistence + sync path** — `model.setGoalSteps(_:)` already
  writes `UserPreferences` and applies to the dashboard immediately, and
  `setGoal(_:)` in `SettingsView` already pushes to the account when settings sync
  is on. The custom value flows through these unchanged; `SyncablePreferences`
  stays `{ goalSteps: Int }`, so no migration and account sync "just works".
- **Clamp + round centrally in `UserPreferences`** — add `minGoal`, `maxGoal`,
  `goalIncrement`, and a `clampGoal(_:)` helper so the bounds live in one place and
  are unit-testable, rather than scattering magic numbers in the view. Bounds:
  **1,000 … 50,000**, rounded to the nearest **500**.
- **Presets stay** — Custom is additive; the five quick presets remain the fast
  path. A goal that happens to equal a preset still highlights that preset, not
  Custom (`isPreset` decides).

## Implementation

### 1. Goal bounds + clamp/preset helpers

**File**: `Sources/AppCore/Preferences.swift`

Extend `UserPreferences` with the bounds and helpers the custom editor needs:

- `public static let minGoal = 1000`
- `public static let maxGoal = 50000`
- `public static let goalIncrement = 500`
- `public static func clampGoal(_ value: Int) -> Int` — clamp to `minGoal…maxGoal`,
  then round to the nearest `goalIncrement`.
- `public static func isPreset(_ value: Int) -> Bool` — `goalOptions.contains(value)`.

Leave `goalSteps` / `setGoalSteps` / `goalOptions` / `defaultGoal` as-is.

### 2. Custom entry in the Daily step goal card

**File**: `Sources/AppCore/SettingsView.swift`

Reshape `goalCard` (currently just the preset capsule row, lines ~408–427):

- Keep the preset capsule row. Append a **Custom** capsule after the presets.
  It reads as *selected* when `!UserPreferences.isPreset(model.today.goalSteps)`,
  and its label shows the live value (e.g. `9.5k`) when custom, or just `Custom`
  when a preset is active.
- Tapping **Custom** toggles an inline editor (`customGoalExpanded`). When opened,
  seed `customGoalDraft` from the current goal (or `defaultGoal`). The editor is a
  `Stepper` stepping by `UserPreferences.goalIncrement` between `minGoal` and
  `maxGoal`, with a label showing the formatted draft value (reuse `formatted(_:)`
  from `Formatters.swift`).
- On each stepper change, call the existing `setGoal(UserPreferences.clampGoal(draft))`
  so it persists + syncs immediately, exactly like a preset tap.
- Add view state near the other `@State` fields: `@State private var
  customGoalExpanded = false` and `@State private var customGoalDraft =
  UserPreferences.defaultGoal`. In `.onAppear`, set `customGoalExpanded =
  !UserPreferences.isPreset(model.today.goalSteps)` so a returning custom user sees
  the editor already open.
- Accessibility: label the Custom chip "Custom step goal" + `.isSelected` trait when
  active; the stepper announces the current value via its formatted label.

Reuse the existing capsule styling and `setGoal(_:)` — do **not** add a parallel
persistence path.

### 3. Tests for clamp/round, bounds, and custom persistence

**File**: `Tests/AppCoreTests/ModelTests.swift`

Add cases alongside the existing goal tests (`testSetGoalStepsApplies`,
`testGoalDefaults`):

- `testClampGoalBoundsAndRounding` — bounds: `clampGoal(200) == 1000` (min),
  `clampGoal(99999) == 50000` (max). Rounding to nearest 500 (unambiguous values):
  `clampGoal(9740) == 9750`, `clampGoal(9700) == 9500`, `clampGoal(9800) == 10000`.
- `testIsPresetMatchesOptions` — `isPreset(10000) == true`, `isPreset(9500) == false`.
- `testSetCustomGoalPersistsAndApplies` — `model.setGoalSteps(9500)` updates
  `model.today.goalSteps` and `UserPreferences.goalSteps()` to `9500`
  (mirrors `testSetGoalStepsApplies` for a non-preset value).

## Reused existing code

- `model.setGoalSteps(_:)` from `Sources/AppCore/Model.swift` (lines 250–253) —
  persists + applies the goal; the custom editor calls it unchanged.
- `setGoal(_:)` in `Sources/AppCore/SettingsView.swift` (lines 431–435) — the
  existing local-apply + account-push wrapper; reused verbatim for custom values.
- `UserPreferences` from `Sources/AppCore/Preferences.swift` — `goalSteps`,
  `setGoalSteps`, `goalOptions`, `defaultGoal`; extended with the new helpers.
- `SyncablePreferences` / `accountSync.pushPreferences` from
  `Sources/AppCore/Account/AccountSyncService.swift` — unchanged; custom goals sync
  through the existing `{ goalSteps: Int }` payload. Covered by
  `AccountSyncTests.testPreferencesRoundTrip`.
- `formatted(_:)` from `Sources/AppCore/Formatters.swift` — formats the draft value
  in the stepper label.
- The capsule button style already in `goalCard` — the Custom chip mirrors it.

## Scenarios to Demonstrate

- **Default presets** — goal at `10000`; preset row shown, `10k` selected, Custom
  chip collapsed and unselected.
- **Custom value active** — goal at `9500` (not a preset); Custom chip selected
  showing `9.5k`, editor open with the stepper at 9,500.
- **High custom goal** — goal at `20000`, above the top preset, demonstrating the
  card handles values past `15k`.
- **At minimum bound** — goal at `1000`; stepper can't go lower.
- **At maximum bound** — goal at `50000`; stepper can't go higher.
- **Today dashboard reflects a custom goal** — the step ring's "of 9,500" caption
  and progress reflect the custom target (ties the Settings change to the visible
  outcome).
