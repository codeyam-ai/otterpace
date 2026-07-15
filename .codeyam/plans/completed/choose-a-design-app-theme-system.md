---
title: "Choose a Design — App Theme System"
mode: ui
createdAt: "2026-07-15T19:26:41Z"
source: manual
---

## Summary

Add a multi-theme system to Otterpace so a user can pick a whole-app visual
identity in onboarding and change it in Settings, with their choice becoming
their personal default until they change it. Ship **five themes**: **Default**
(the current coral / PuffyBuddy look, which stays the default) plus four
self-contained iOS-native alternates — **Bolt** (true-black, electric-aqua,
data-led), **Orbit** (icy cosmic blue, water-world planet), **Fieldnote** (warm
risograph paper + water-teal, river field-seal), and **Garden** (sage +
water-lily). Each theme retints every screen, subpage, and component with good
contrast, and each non-Default theme **replaces the PuffyBuddy otter with its own
abstract mark**; Default keeps PuffyBuddy everywhere. The approved visual source
of truth is committed at `.codeyam/design/project_mockups/` (04-neo-brutalist =
Bolt, 05-space-odyssey = Orbit, 06-offcatalog = Fieldnote, 02-gardener = Garden).

## Key Decisions

- **Theme drives the existing `Palette`, rather than rewriting 39 call sites.**
  Today ~39 files reference static `Palette.brand` / `Palette.bgTop` etc. Convert
  `Palette`'s members to computed properties that resolve from the currently
  selected theme (backed by a `ThemeStore`), so every existing call site is
  themed with no edit. The app root observes `ThemeStore` and applies
  `.id(theme.id)` to force a clean full re-theme on switch. This keeps the change
  tractable and consistent with the app's existing static-token design, while a
  SwiftUI `@Environment(\.theme)` is added for the few places that must *branch*
  on theme (the mascot/mark, per-theme background art).
- **Colors + mark differentiate; Typography and Layout stay shared.** All five
  mockups now use SF Pro on native iOS structure, so `Typography` and `Layout`
  remain one source of truth (optionally a theme may tweak a numeral weight).
  The heavy lifting is the color token set + the brand mark + background per
  theme. This keeps themes cohesive as one app, not five apps.
- **Mascot swap is centralized in one `BuddyView`.** Instead of editing every
  PuffyBuddy call site, introduce a themed `BuddyView(mood:size:)` that renders
  `PuffyBuddy` for Default and the theme's mark for the others. On surfaces that
  need emotion (Ask Coach), non-Default themes convey mood through the accent
  ring/label around the mark rather than a facial expression.
- **Persistence mirrors `CoachProfileStore`.** Store the selected theme id in
  `UserDefaults` (single key), with an injectable `defaults` for tests, exactly
  like `CoachProfileStore`. Add a scenario seed key `rbTheme` (read at launch,
  same pattern as `rbGoalSteps` / `rbCoachProfileJSON`) so each theme is
  capturable as a scenario.
- **Contrast is a first-class requirement.** Each theme's ink/subtle-on-surface
  pairs must clear WCAG AA (the existing `Palette.subtle` comment already tracks
  this); dark themes (Bolt, Orbit) define their own subtle/secondary tokens.

## Implementation

Organized by area. The editor build can sequence these; colors/model first,
then marks, then the pickers, then per-screen verification.

### 1. Theme model + the five token sets

**File**: `Sources/AppCore/Theme.swift` (extend) and/or **New file**:
`Sources/AppCore/Theming/Theme.swift`

Define a `Theme` value type carrying the full token set the app needs: `brand`
(accent), semantic `go` / `amber` / `gold` / `sky` / `lilac`, `ink`, `subtle`,
`card`, `bgTop`, `bgBottom`, plus `isDark`, `cardCorner` (if it varies), and a
`mark` identity. Define `ThemeID` enum: `.default`, `.bolt`, `.orbit`,
`.fieldnote`, `.garden`, each with a display name, one-line education blurb, and
its resolved `Theme`. Pull the exact hex values from the committed mockups
(e.g. Bolt bg `#000`, card `#1B1B1D`, aqua `#2FE3D0`; Orbit bg `#05070E`, ice
`#74D6FF`; Fieldnote paper `#EFE6D2`, orange `#E0562F`, teal `#1F7E8C`; Garden
bg `#ECEFE8`, sage `#4E6B54`, lily `#C98BA8`). Default = today's Palette values.

### 2. ThemeStore — selection + persistence + environment

**New file**: `Sources/AppCore/Theming/ThemeStore.swift`

An `ObservableObject` with `@Published var themeID` that loads/saves the chosen
id to `UserDefaults` (persisted personal default; changing it updates the store),
and reads the `rbTheme` seed key at launch for scenario previews. Mirror
`CoachProfileStore`'s injectable-`defaults` shape for tests. Add a SwiftUI
`EnvironmentKey` `\.theme` returning the resolved `Theme`. The app root
(`ContentView` / the app entry) owns the `@StateObject ThemeStore`, injects
`\.theme`, and keys the content on `themeID` so switching re-themes the whole
tree cleanly.

### 3. Make `Palette` resolve from the current theme

**File**: `Sources/AppCore/Theme.swift`

Convert `Palette`'s `static let`s to `static var` computed properties that read
`ThemeStore.shared.current` (a shared instance the root also drives). Keeps all
~39 existing `Palette.X` call sites working, now themed. `BuddyMood.accent` keeps
mapping to `Palette.*` and thus themes automatically.

### 4. The four theme marks as SwiftUI

**New file**: `Sources/AppCore/Theming/ThemeMarks.swift`

Reproduce each mockup mark as SwiftUI shapes: **Bolt** lightning-bolt glyph,
**Orbit** icy water-world planet (radial-gradient sphere, ice bands, thin ring,
glow), **Fieldnote** field-seal (double ring + tick marks + two-color river
route), **Garden** water-lily monogram (an "O" ring with a sprig). Each takes a
size and reads theme colors. These are the app-icon-scale brand marks and the
Buddy replacement.

### 5. Themed BuddyView + Ask Coach mood rework

**Files**: `Sources/AppCore/PuffyBuddy.swift` (add wrapper) and the Ask Coach
surfaces `Sources/AppCore/AskCoachView.swift`, `Sources/AppCore/ChatBubble.swift`,
`Sources/AppCore/AskCoachHeader.swift`

Add `BuddyView(mood:size:)` that renders `PuffyBuddy(mood:size:)` for Default and
the theme mark for the others. Swap the direct PuffyBuddy usages (Today hero if
any, onboarding "Meet Buddy", the moods gallery, the loader, and the chat/mood
avatar) to `BuddyView`. For non-Default themes the chat avatar shows the mark
inside the mood accent ring (mood via color, not face). The "Meet Buddy"
onboarding intro shows the selected theme's mark when not Default.

### 6. Per-theme background

**Files**: `Sources/AppCore/ContentView.swift` (line ~68) and
`Sources/AppCore/AskCoachView.swift` (line ~92)

The `LinearGradient(colors: [Palette.bgTop, Palette.bgBottom])` already themes via
Palette, but dark themes want a flat/near-flat or subtly radial background and
the risograph theme wants its dot texture. Add an optional `theme.background`
view the two top-level surfaces use instead of the hardcoded gradient.

### 7. Onboarding "Choose your look" step

**Files**: `Sources/AppCore/Onboarding/OnboardingFlowView.swift` and
`Sources/AppCore/Onboarding/OnboardingState.swift`

Add a `chooseLook` case to the personalization `Step` enum with its own step
view: a horizontal, sw, live-previewing selector of the five themes (each a
mini phone-frame or a swatch + mark + name + one-line education), writing the
pick to `ThemeStore`. Bump `OnboardingState.personalizationStepCount` 5 → 6 (and
thus `stepCount`). Skippable like the other steps and leaves **Default**.

### 8. Settings Appearance / Theme picker

**File**: `Sources/AppCore/SettingsView.swift`

Add an **Appearance** section with a "Theme" row that opens a picker listing the
five themes with the same education copy and a live preview, updating
`ThemeStore` immediately. Reuse the settings row / sheet patterns already in the
file.

### 9. Education copy

One short, human blurb per theme (shared between the onboarding step and the
settings picker), e.g. Default "Warm and friendly — meet Buddy.", Bolt "Dark and
focused, built for training.", Orbit "Cool, calm, cosmic.", Fieldnote "Warm,
analog, field-guide.", Garden "Quiet and natural." Keep in the `ThemeID` model.

### 10. Scenario seeding

Wire `rbTheme` into the launch-seed path so scenarios can pin a theme, enabling a
captured Today (and Ask Coach) per theme. Register the new scenarios in the
editor's scenario steps.

## Reused existing code

- `Palette`, `Typography`, `Layout`, `Motion` from `Sources/AppCore/Theme.swift`
  (glossary: `Typography`) — Palette becomes theme-resolved; the rest stay shared.
- `BuddyMood` from `Sources/AppCore/Theme.swift` (glossary: `BuddyMood`) — accent
  mapping reused, themes automatically via Palette.
- `PuffyBuddy` / `HappyArc` / `PuffyBuddyGallery` from
  `Sources/AppCore/PuffyBuddy.swift` (glossary: `PuffyBuddy`) — kept for Default,
  wrapped by the new `BuddyView`.
- `PuffyBuddyLoader` / `BouncingDots` from `Sources/AppCore/PuffyBuddyLoader.swift`
  (glossary: `PuffyBuddyLoader`) — themed via the mark for non-Default.
- `OnboardingFlowView` + `OnboardingState` (glossary: `OnboardingState`,
  test `OnboardingStateTests`) — the step enum + `stepCount` extend here.
- `SettingsView` (glossary: `SettingsView`) — the Appearance row/picker lands here.
- `CoachProfileStore` (glossary: `CoachProfileStore`, test `CoachProfileTests`) —
  the UserDefaults-JSON + injectable-`defaults` + `rb*` seed pattern to copy for
  `ThemeStore`.
- `CoachCard`, `ChatBubble`, `TrendBadge`, `ConnectHero`, `WeeklyReviewView`,
  `ActivityHistoryView` — already read `Palette`, so they retint for free; verify
  contrast per theme.

## Scenarios to Demonstrate

- **Today — each theme**: five captures of the Today dashboard (goal-crushed
  state) seeded `rbTheme` = default / bolt / orbit / fieldnote / garden, showing
  the retinted ring, cards, stats, coach card, tab bar, and the per-theme mark.
- **Onboarding — Choose your look**: the new step with the five options and one
  selected, education visible.
- **Settings — Appearance picker**: the theme picker open, live preview.
- **Ask Coach in a non-Default theme**: e.g. Bolt or Orbit — the mark replaces
  Buddy in the chat/mood avatar, mood conveyed by the accent, chat legible.
- **Ask Coach in Default**: PuffyBuddy still present and emoting (unchanged).
- **Contrast / readability edge**: a dark theme (Bolt) and a light theme (Garden)
  each showing captions/labels clearing AA on their surfaces.
- **Persistence**: pick a theme, relaunch (seeded), it persists as the personal
  default.
