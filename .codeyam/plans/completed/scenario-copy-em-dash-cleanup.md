---
title: "Scenario Seed Copy: Em Dash Cleanup"
mode: ui
createdAt: "2026-07-21T00:00:00Z"
source: manual
---

## Summary

The "Elapsed-Aware Weekly View" feature stripped em dashes from user-facing string
literals in app source (36 strings across 13 files), but deliberately scoped that
sweep to `Sources/**.swift`. Roughly 59 scenario JSON files under
`.codeyam/scenarios/` still carry em dashes in their seeded demo copy — coach
headlines and bodies like `"10K crushed — nice work!"` and
`"So close — 820 to go!"`. These are demo fixtures, not shipped app strings, so
they have ZERO effect on the binary. But they render in captured scenario
screenshots and therefore in the README showcase gallery, where the em dashes are
now inconsistent with the in-app copy the sweep already normalized.

This is a non-blocking, presentation-only cleanup. It is intentionally its own
plan rather than folded into the feature, because rewriting seed copy invalidates
every affected screenshot and forces a full recapture cycle — the same ~40-scenario
sweep the feature already paid down once.

## Key Decisions

- **Scope is `.codeyam/scenarios/*.json` seed values only.** Specifically the
  `deviceState.preferences` string keys that hold user-facing copy: `rbCoachHeadline`,
  `rbCoachBody`, `rbAskSeedQuestion`, and any similar narrative seed. Do NOT touch
  keys that are data, not prose (dates, paces, booleans, numeric goals).
- **Contextual rewrites, not a blind character swap.** Match what the source sweep
  did: an em dash becomes a comma, a period, a colon, or parentheses depending on
  the sentence. A global `—` → `,` replace would read wrong in many places
  (`"So close — 820 to go!"` wants a comma; `"10K crushed — nice work!"` wants a
  period or comma; a mid-clause aside wants parens). Review each string.
- **Recapture is the expensive half and must use the verified method.**
  `recapture-stale` is unusable on this `swift-ios-swiftui` simulator stack (it warms
  an HTTP dev server that does not exist, 502s, and overwrites the PNG with the coral
  LaunchScreen splash). Use the manual sweep proven during the feature: per scenario,
  wipe the app defaults domain (so an omitted `rb*` key cannot leak from the prior
  scenario), pin `rbTheme` to the scenario's own theme (default unless the scenario
  seeds one), let `editor preview` seed and launch, settle ~10s past the splash
  WITHOUT a manual relaunch (a second launch resets page state), then
  `simctl io screenshot`. Verify each family against its committed original before
  installing — a faithful capture of a stale seed is still the wrong screen.
- **Verify seed correctness before recapturing, not just after.** The feature
  surfaced that six onboarding scenarios had drifted page indices; a recapture
  faithfully renders whatever the seed says. `OnboardingScenarioIndexTests` now
  guards page indices, but this plan should still eyeball each family's first frame.
- **Batch by family to keep the diff reviewable** (ask-coach, today, weekly-review,
  onboarding, settings, welcome), capturing to a staging dir and installing per family.

## Implementation

### 1. Inventory the affected seeds

- `grep -l "—" .codeyam/scenarios/*.json` for the file list (~59).
- For each, extract the em-dash-bearing `preferences` string keys. Confirm each is
  user-facing prose, not data.

### 2. Rewrite the seed copy

- Edit each scenario JSON's affected string values with a contextual replacement.
- Keep every file in canonical JSON form (the audit's `CANONICAL_JSON_FORM`
  invariant fires on hand-edits: raw unicode, 2-space indent, sorted keys where the
  writer uses them, trailing newline). Prefer re-writing via a small script that
  round-trips through the same serializer the tooling expects.

### 3. Recapture affected scenarios

- Run the verified manual sweep over exactly the scenarios whose copy changed.
- Verify one frame per family against its committed original.
- Install, then confirm `scenario-coverage` reports 0 stale / 0 missing and
  `seeded-capture-check` finds no NEW distinct-seed collisions beyond the known
  pre-existing ones.

### 4. Refresh the README gallery

- `readme-sync` so the showcase screenshots match the recaptured frames.

## Out of Scope

- App source strings (already swept).
- The ~7 pre-existing `seeded-capture-check` collisions among unrelated scenarios
  (`accessibility-large-text-today` etc.) — those are near-blank or ambient-state
  captures, tracked separately, not caused by this copy change.
- Code comments and doc headers (the source sweep left those; seed JSON has none).

## Verification

- `grep -c "—" .codeyam/scenarios/*.json` returns zero across the set.
- `codeyam-editor editor scenario-coverage` → 0 stale, 0 missing.
- No app source or test changes (this is fixtures + screenshots only), so the Swift
  suite is untouched; run it once to confirm no incidental breakage.
