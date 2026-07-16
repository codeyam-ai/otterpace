---
title: "Onboarding Theme Preview Live-Updates on Selection"
mode: ui
createdAt: "2026-07-16T01:43:31Z"
source: manual
---

## Summary

Verify — and fix if broken — that selecting a different look on the onboarding
**"Choose your look"** step updates the preview live so the user sees the theme
applied before continuing. The wiring looks correct on inspection
(`OnboardingFlowView` holds `@ObservedObject ThemeStore.shared`, tapping a row
sets `themeStore.themeID = id`, and `Palette.*` reads `ThemeStore.shared.current`
dynamically, so the scaffold background and text should retint on tap). But this
is exactly the class of behavior the recent "fix theme application across all
modules" pass was cleaning up, so it warrants an end-to-end confirmation on the
onboarding surface specifically, plus regression scenarios.

## Key Decisions

- **Verify first, then fix only if needed** — the mechanism appears sound, so the
  first task is to drive the onboarding flow live (simulator), tap each theme on
  the Choose-your-look step, and confirm the step's background/text retints
  immediately. Only implement a fix if the live preview does NOT update.
- **Most likely failure mode if broken** — the paged carousel
  (`TabView(.page)` / `PageTabViewStyle`) or the `stepScaffold` background may
  cache the palette and not re-evaluate on the `@Published themeID` change, or
  the background gradient is applied outside the observed body. The fix would be
  to ensure the choose-look step (and its scaffold background) re-reads `Palette`
  when `ThemeStore` changes — e.g. key the scaffold on `themeStore.themeID`, or
  move the gradient inside the observed body — without resetting carousel/nav
  identity.
- **Add regression coverage** — capture the Choose-your-look step under each of
  the five themes so the step's themed rendering is pinned as scenarios, and add
  a note that the live-tap retint is verified by driving the app (scenarios seed
  a theme at launch via `rbTheme`; they can't simulate the in-flow tap, so the
  live-update itself is a runtime verification, not a captured scenario).

## Implementation

### 1. Verify the live preview end-to-end

**Files (read/verify only)**: `Sources/AppCore/Onboarding/OnboardingFlowView.swift`
(`chooseLookStep`, `themeOptionRow`, the `@ObservedObject themeStore`),
`Sources/AppCore/Theme.swift` (`Palette` → `ThemeStore.shared.current`),
`Sources/AppCore/Theming/ThemeSystem.swift` (`ThemeStore`, `ThemedAppRoot`)

Run the app to the onboarding Choose-your-look step and tap each theme row.
Confirm: the selection check moves, and the **step background + text retint
immediately** (not just after Continue). Note the actual observed behavior.

### 2. Fix only if the preview does not update live

**File**: `Sources/AppCore/Onboarding/OnboardingFlowView.swift`

If step 1 shows the preview does NOT retint on tap, apply the minimal fix:
ensure the choose-look scaffold re-evaluates `Palette` on the
`@Published themeID` change (e.g. `.id(themeStore.themeID)` on the scaffold, or
relocating the `Palette.bgTop`/`bgBottom` gradient into the observed body), being
careful not to reset the carousel page or navigation identity. Keep the existing
`themeStore.themeID = id` selection handler and `onboarding_theme_selected`
analytics. If step 1 shows it already works, this section is a no-op and the plan
delivers only the regression scenarios below.

### 3. Regression scenarios for the themed step

Capture the Choose-your-look step per theme (seeded via `rbTheme`) so the themed
rendering is pinned. There is already an `onboarding-choose-your-look` scenario;
add per-theme variants (mirrors the existing `today-goal-crushed-*-theme`
scenarios).

## Reused existing code

- `OnboardingFlowView` (`Sources/AppCore/Onboarding/OnboardingFlowView.swift`,
  glossary: `OnboardingState` area) — `chooseLookStep`, `themeOptionRow`.
- `ThemeChoiceRow` (`Sources/AppCore/Theming/ThemeSwatch.swift`, glossary:
  `ThemeChoiceRow`) — the onboarding-styled selectable row, already wired to an
  `onSelect` closure.
- `ThemeStore` (`Sources/AppCore/Theming/ThemeSystem.swift`, glossary:
  `ThemeStore`) — `@Published themeID`, `rbTheme` scenario seeding.
- `Palette` (`Sources/AppCore/Theme.swift`) — computed tokens reading
  `ThemeStore.shared.current`.
- Existing `onboarding-choose-your-look` scenario and the
  `today-goal-crushed-<theme>-theme` per-theme scenario pattern.

## Scenarios to Demonstrate

- **Onboarding Choose-Your-Look — Default** (existing, confirm)
- **Onboarding Choose-Your-Look — Bolt**
- **Onboarding Choose-Your-Look — Orbit**
- **Onboarding Choose-Your-Look — Fieldnote**
- **Onboarding Choose-Your-Look — Garden**

(The live-tap retint is verified by driving the app in the simulator, since a
seeded scenario can't simulate the in-flow selection tap.)
