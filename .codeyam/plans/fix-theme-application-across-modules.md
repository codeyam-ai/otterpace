---
title: "Fix theme application across all modules"
mode: ui
createdAt: "2026-07-15T00:00:00Z"
source: manual
---

## Summary

Selecting a non-default theme (Bolt, Orbit, Fieldnote, Garden) leaves parts of
the app looking unthemed: the Ask Coach "What should we do today?" text and some
Today modules render white, and the screen background doesn't match the chosen
light/dark look. The theme *tokens* are actually wired correctly at every call
site (`Palette.*` resolves to the selected theme). The breakage is at the
rendering layer: (1) `ContentView` hardcodes a light color scheme that overrides
the theme's scheme, forcing light system chrome under the dark themes; (2) the
Today dashboard paints no background of its own, so a `TabView`'s opaque system
background covers the theme gradient and shows through as system white/black;
(3) the Today dashboard doesn't observe `ThemeStore`, so a live switch can leave
its modules on stale colors; and (4) an onboarding chip hardcodes a white
background. Otter (Default) looks fine only because its theme *is* light + white,
which happens to match the buggy fallbacks — the other four don't. Fix all four
so every theme applies to every module.

## Key Decisions

- **Make the color scheme theme-driven, don't drop it.** `ContentView`'s
  `.preferredColorScheme(.light)` is a pre-theme-system leftover. It can't just
  be deleted (isolated-component captures and SwiftUI previews mount
  `ContentView` directly, *without* `ThemedAppRoot`, and rely on it pinning a
  scheme). Instead drive it from the selected theme, mirroring `ThemedAppRoot`.
- **Give the Today dashboard its own themed background**, matching what
  `AskCoachView` already does. Relying on `ContentView`'s ZStack gradient
  showing through the `TabView` is the actual defect — the `TabView`'s backing
  controller paints an opaque system background on top. Painting the gradient on
  the dashboard root is the parity fix that guarantees the Today surface matches
  the theme on every look (this is why even the *light* themes Fieldnote/Garden
  show a white Today background today).
- **Every screen root observes `ThemeStore`.** This is the app's established
  live-retheming pattern (Settings, Ask Coach, Weekly Review, Activity History,
  Sign In, Onboarding all do it). `TodayDashboard` is the one screen root that
  doesn't — bring it into line so switching themes repaints all Today modules
  without a navigation reset.
- **Route hardcoded whites through the palette** only where the white sits on a
  theme-variable surface. Whites that ride on a brand-colored fill (chat send
  button, user bubble, primary CTAs, capsule badges) are correct on every theme
  and stay as-is.

## Implementation

### 1. Make ContentView's color scheme follow the selected theme

**File**: `Sources/AppCore/ContentView.swift`

Line 121 currently pins `.preferredColorScheme(.light)`, which wins over
`ThemedAppRoot`'s `.preferredColorScheme(theme.isDark ? .dark : .light)` because
it's deeper in the view tree — so the whole window renders light even under Bolt
and Orbit (white tab bar, light system surfaces, "background doesn't match the
dark theme"). Change it to read the theme, using the `themeStore` this view
already observes (line 9):

```swift
.preferredColorScheme(themeStore.current.isDark ? .dark : .light)
```

Update the adjacent comment (the "Light-only design" note is now stale) to
explain that the scheme follows the theme and is pinned here so isolated-component
captures / previews that mount `ContentView` without `ThemedAppRoot` still get a
correct scheme.

### 2. Paint the Today dashboard's own themed background

**File**: `Sources/AppCore/TodayView.swift`

`TodayDashboard.body` (the outer `ZStack`, line 53) has no background, so the
Today tab shows the `TabView`'s opaque system background instead of the theme
gradient — system white on the light themes, system black on the dark ones,
never the theme's `bgTop → bgBottom`. Add the same themed gradient background
`AskCoachView` uses (see `AskCoachView.swift:93–97`) to the dashboard's root
`ZStack`, so the Today surface matches the selected theme on every look:

```swift
.background(
    LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                   startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
)
```

### 3. Have the Today dashboard observe ThemeStore

**File**: `Sources/AppCore/TodayView.swift`

Add the shared-store observation every other screen root already has, so a live
theme switch from Settings re-invokes `TodayDashboard.body` and all its child
modules (header, stat tiles, coach card, buddy summary, workout/weekly-load
cards) re-read `Palette` for the new theme instead of keeping stale colors:

```swift
public struct TodayDashboard: View {
    // Re-render this screen when the theme changes so Palette retints live.
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject var model: OtterpaceModel
    ...
```

### 4. Theme the onboarding choice-chip background

**File**: `Sources/AppCore/Onboarding/OnboardingFlowView.swift`

`choiceChip` (line 528) fills the unselected state with
`Color.white.opacity(0.7)`. The tour is replayable from Settings under the
current theme, so on Bolt/Orbit these chips render as white blocks. Route the
unselected fill through the palette so it matches the theme's surface. Use the
theme card/surface token (e.g. `Palette.card.opacity(0.7)` — matching the
selected/unselected contrast the design intends) and keep the existing stroke.

### 5. Verify remaining shared surfaces per theme (no expected changes)

**Files**: Today + Coach module components (already audited)

Confirm during the editor pass that these surfaces read correctly on all five
themes now that the scheme + Today background are fixed — no token edits are
expected, they already use `Palette.*`:
- Tab bar tint/appearance (`ContentView.connectedTabs`, `.tint(Palette.brand)`).
- `cardStyle()` cards on the dark themes (`ViewStyles.swift`) — dark card fill on
  dark gradient.
- Ask Coach input bar and chat bubbles (`AskCoachInputBar`, `ChatBubble`).
- Garden/Default pure-white cards now reading as proper cards over the (now
  correctly painted) tinted Today background rather than as "unthemed white."

## Reused existing code

- `Palette.bgTop` / `Palette.bgBottom` / `Palette.card` theme tokens from
  `Sources/AppCore/Theme.swift` (glossary: `Palette` — resolves via
  `ThemeStore.shared.current`).
- `ThemeStore.shared` + `theme.isDark` from
  `Sources/AppCore/Theming/ThemeSystem.swift` (glossary entries: `ThemeStore`,
  `Theme`, `ThemeID`).
- The self-painted themed gradient background pattern from
  `AskCoachView.swift:93–97` — copied to `TodayDashboard` for parity.
- The `@ObservedObject ThemeStore.shared` live-retheme pattern already used by
  `AskCoachView`, `SettingsView`, `WeeklyReviewView`, `ActivityHistoryView`,
  `SignInView`, and `OnboardingFlowView`.
- The scheme expression `themeStore.current.isDark ? .dark : .light` mirrors
  `ThemedAppRoot` in `ThemeSystem.swift:145`.

## Scenarios to Demonstrate

- **Bolt — Today dashboard**: dark background gradient, dark cards, white ink
  text, dark tab bar — nothing white/light bleeding through.
- **Bolt — Ask Coach empty state**: "What should we do today?" in white ink on
  the dark gradient, dark tab bar and input bar.
- **Orbit — Today dashboard**: cosmic-blue dark gradient background matches the
  theme (not system black), all modules retinted.
- **Fieldnote — Today dashboard**: warm cream background (not system white),
  cream cards, dark ink — light theme applied to every module.
- **Garden — Ask Coach + Today**: sage background, white cards reading as proper
  cards over the tinted surface.
- **Live switch from Settings**: change theme in the Appearance picker and return
  to Today — every module (header, stat tiles, coach card, buddy summary) has
  repainted to the new theme, no stale/white modules.
- **Onboarding "Choose your look" replay under a dark theme**: choice chips use
  the themed surface, not white blocks.
