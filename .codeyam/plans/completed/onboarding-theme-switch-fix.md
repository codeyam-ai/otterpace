---
title: "Onboarding Theme Switch Fix"
mode: ui
createdAt: "2026-07-24T00:00:00Z"
source: manual
---

## Summary

Two onboarding bugs around theming:

1. **Theme picker jumps back to the start of onboarding.** On the "Choose your
   look" step, selecting a theme sends the user back to the first intro page
   instead of retinting the current step in place.

2. **The brand mark appears to change color from one onboarding screen to the
   next.** Most visible on the natural green/parchment themes (Garden and
   Fieldnote): the logo reads as a different color per screen as you move
   through the flow.

Neither should happen. Picking a theme should recolor the app live and keep the
user exactly where they are (they only go back if they tap Back). The brand mark
should hold one consistent color across every onboarding screen within a theme.

## Root Cause

**Bug 1 — the whole view tree is re-keyed on theme change.**
`ContentView.swift:125` applies `.id(themeStore.themeID)` to the entire root
`ZStack`. That identity is deliberately changed on a theme switch so the
main-content *leaf cards* (which read the static `Palette` but do not observe
`ThemeStore`) get torn down and rebuilt with the new colors. But the onboarding
and Settings overlays are siblings inside that same `ZStack`, so they are torn
down too — and `OnboardingFlowView`'s `@State page` re-initializes to
`startPage` (0). Result: picking a theme rebuilds onboarding from scratch and
drops you on page 1.

The overlays don't need the `.id` rebuild: they already retint live. Each holds
`@ObservedObject private var themeStore = ThemeStore.shared`, and `BuddyView`
reads `@Environment(\.theme)`, which `ThemedAppRoot` (`App/App.swift:70`) injects
from `themeStore.current` while observing the store. So the overlays recolor on
their own the moment the theme changes.

**Bug 2 — the mark's halo color is driven by mood, which varies per screen.**
`BuddyView` (`ThemeMarks.swift`) renders the abstract theme mark inside a halo
`Circle().fill(mood.accent…)`. `BuddyMood.accent` (`Theme.swift:108`) maps
`ready → brand`, `jogging → go`, `cheering → go`, etc. The onboarding screens each
pass a different mood (`OnboardingFlowView.swift:188` intro pages, `:428` step
scaffold): intro 1 `ready`, intro 2 `jogging`, intro 3 `cheering`, and the steps
alternate `ready`/`jogging`/`cheering`. The mark's *fill* is a constant theme
color, but the *halo* behind it shifts — brand → go → go across the flow. On
Fieldnote that is terracotta (`#E0562F`) → teal (`#1F7E8C`), a jarring swing; on
Garden it is green (`#4E6B54`) → green-teal (`#6F9E8B`), subtler but visible. For
a face mascot (Default's `PuffyBuddy`) a mood-colored halo is intended
personality; for an abstract brand *mark* it reads as the logo changing color.

## Key Decisions

- **Scope the re-key, don't remove it.** Keep `.id(themeStore.themeID)` on the
  main-content branch only (the background gradient + the `if/else` content
  switch that renders `ConnectHero` / `HealthDeniedView` / `connectedTabs` /
  `SignInView` / `BuddyPreviewHost`). Move the Settings and Onboarding overlays
  *outside* the keyed subtree so they keep their state across a theme switch and
  retint via their own `ThemeStore` observation. This also fixes the same class
  of state-loss in the Settings theme picker.
- **Preserve app state above the `.id`.** `model`/`session` already live above
  the `.id` (they're `@StateObject`s on `ContentView`), so nothing about
  hoisting the overlays changes app-level state survival. Scenario captures pin a
  single theme at launch, so the `.id` is constant during a capture and never
  triggers a rebuild — unchanged by this edit.
- **Fix Bug 2 in the onboarding call sites, not globally.** `BuddyView`'s
  mood-colored halo is the intended design on mood surfaces (Today, Coach,
  weekly review) where mood must read through color without a face. Render the
  onboarding brand mark with a consistent, non-mood presentation
  (`showHalo: false`, or a fixed brand-tinted halo) so the logo holds one color
  per theme across every onboarding screen, while leaving mood-halo behavior
  everywhere else untouched. `PuffyBuddy` (Default) still conveys mood through
  its face, so the intro carousel keeps its personality.
- **Confirm the exact remedy visually before finalizing.** Capture the intro
  pages under Garden and Fieldnote to verify the mark color is stable
  screen-to-screen, and re-verify the existing "Choose Your Look" per-theme
  scenarios still render correctly.

## Implementation

### 1. Scope the theme re-key (Bug 1)
- In `ContentView.swift`, wrap only the gradient + main-content `if/else` chain
  (lines ~70–88) in a container carrying `.id(themeStore.themeID)`.
- Leave the `showSettings` and `showOnboarding` overlay blocks as siblings of
  that container in the outer `ZStack`, without the `.id`.
- Keep `.preferredColorScheme`, `DynamicTypeOverride`, and the lifecycle
  modifiers on the outer view as they are. Update the explanatory comment.

### 2. Make the onboarding mark color-consistent (Bug 2)
- In `OnboardingFlowView.swift`, render the brand mark with a consistent
  presentation at both call sites (`:188` intro, `:428` step scaffold) — e.g.
  `BuddyView(mood:…, showHalo: false)` — so the halo no longer recolors per
  screen. Confirm `PuffyBuddy` still renders acceptably with the chosen option.

### 3. Tests
- Add/extend coverage asserting onboarding page state is preserved across a
  theme change (guard against the re-key regression at the logic level where
  feasible), alongside the existing `OnboardingStateTests` /
  `OnboardingScenarioIndexTests` / `ThemeStoreTests`.

### 4. Scenarios (data states)
- Reuse the existing per-theme "Choose Your Look" scenarios (Fieldnote, Garden,
  Orbit, Otter) and the per-step onboarding scenarios.
- Add intro-page scenarios under **Garden** and **Fieldnote** (intro pages
  0/1/2, which carry moods `ready`/`jogging`/`cheering`) so the fix is
  demonstrable: the mark holds one color across all three. Production DB stays
  empty; each scenario carries its own seed (`rbStartScreen=onboarding`,
  `rbOnboardingPage`, `rbTheme`).

## Out of Scope

- `BuddyView`'s mood-halo behavior on non-onboarding surfaces (Today, Coach,
  weekly review) — intentionally unchanged.
- Redesigning any theme's palette or the marks themselves — the mark fills are
  already correct; only the onboarding halo presentation and the re-key scope
  change.
- Adding or renaming themes.

## Verification

- Live: enter onboarding, reach "Choose your look", pick a theme → the app
  retints and stays on that step; tap Back → goes to the prior step as before.
- Live: swipe the intro carousel under Garden and Fieldnote → the brand mark is
  the same color on every screen.
- Live: open Settings, switch theme → Settings retints without losing place.
- Swift test suite green; new/updated onboarding + theme tests pass.
- New Garden/Fieldnote intro-page scenarios captured; `scenario-coverage`
  reports 0 stale / 0 missing.
