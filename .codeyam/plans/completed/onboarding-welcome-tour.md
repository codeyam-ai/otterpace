---
title: "First-Run Welcome Tour"
mode: ui
createdAt: "2026-06-26T18:33:44Z"
source: manual
---

## Summary

First-time users currently land straight on the Sign-in screen (`SignInView`)
with no introduction to what Otterpace is or who Buddy is. Add a **brief,
swipeable welcome carousel** that runs once on first launch — three short pages
introducing Buddy, the day-by-day movement coaching, and the Ask Coach chat —
then hands off to the existing Sign-in screen. The tour is remembered so it
never re-appears automatically, and a "Show welcome tour again" row in Settings
lets users replay it. The flow reuses the app's existing mascot (`PuffyBuddy`),
theme (`Palette`/`Typography`/`Layout`/`Motion`), and the capsule/gradient
button styling already used by `SignInView` and `ConnectHero`, so it feels native
to the app on day one. Scenario seeds (mirroring the existing
`rbStartScreen == "signin"` convention) let CodeYam capture each page.

## Key Decisions

- **Placement: a welcome carousel before Sign-in.** It slots in ahead of the
  `session.state == .undecided` branch in `ContentView`, keeping the tour
  self-contained and matching the visual language of `SignInView`/`ConnectHero`
  rather than layering coachmarks over the live dashboard (which would touch
  many existing views).
- **Presented as a top-of-`ZStack` overlay (like `SettingsView`), not a new
  branch in the if/else chain.** This is what makes the same view reusable for
  both first-launch and Settings-triggered replay without restructuring the
  launch gating. It sits at the highest `zIndex`, gated by `previewMode.isEmpty`
  exactly like Settings/Sign-in.
- **"Show once" persisted via a small `OnboardingState` enum**, modeled on
  `UserPreferences` (a UserDefaults-backed key with an injectable `UserDefaults`
  for testability) — not bolted onto `SessionStore`, since it's unrelated to
  Apple-credential lifecycle.
- **Scenario behavior mirrors `SignInView`:** skipped by default when a scenario
  is seeded (`HealthSource.isScenarioSeeded()`), but a scenario can opt in to
  preview it with `rbStartScreen = "onboarding"`, and seed `rbOnboardingPage` to
  start on a specific page for per-page captures.
- **Replay uses a closure, not UserDefaults polling.** `ContentView` passes an
  `onReplayTour` closure to `SettingsView`; the Settings row closes Settings and
  flips `ContentView`'s `showOnboarding` state — consistent with how
  `onSettings`/`onClose` already work. `markSeen()` is only written on finish,
  so a replay that's swiped away mid-way doesn't need special handling.
- **Brief by design:** three pages, a page-dot indicator, a "Skip" affordance,
  and a "Get started" CTA on the last page. Keeps with the user's "brief but
  useful" ask.

## Implementation

### 1. Onboarding persistence + show/skip logic

**New file**: `Sources/AppCore/Onboarding/OnboardingState.swift`

A small `public enum OnboardingState` mirroring `UserPreferences`:

- Key `otterpaceOnboardingSeen` (Bool) in `UserDefaults`.
- `hasSeen(_ d: UserDefaults = .standard) -> Bool` and
  `markSeen(_ d: UserDefaults = .standard)`.
- A pure, unit-testable `shouldShow(defaults:seeded:startScreen:) -> Bool` that
  encodes the launch decision:
  - `startScreen == "onboarding"` → `true` (preview/replay opt-in, regardless of
    `hasSeen`).
  - else `hasSeen` → `false`.
  - else `seeded` (scenario-seeded run) → `false` (scenarios skip by default,
    matching `SignInView`'s `seeded && !wantsSignInPreview`).
  - else → `true` (production first launch).
- `startPage(_ d: UserDefaults = .standard) -> Int` reading `rbOnboardingPage`
  (clamped to the valid page range) so scenarios can capture a specific page;
  defaults to `0`.

### 2. The welcome carousel view

**New file**: `Sources/AppCore/Onboarding/OnboardingFlowView.swift`

A `struct OnboardingFlowView: View` taking `onFinish: () -> Void` and an optional
`startPage: Int`.

- Full-screen background using the same `LinearGradient(colors: [Palette.bgTop,
  Palette.bgBottom], …)` as `ContentView`/`SettingsView`.
- A paged `TabView` (`.tabViewStyle(.page)`) bound to a `@State page` over three
  `OnboardingPage` models. Each page renders a `PuffyBuddy` mascot in a fitting
  `BuddyMood`, a `Typography.title` headline, and a one-sentence
  `Typography.callout` body (voice matched to existing `ConnectHero` copy):
  1. **Meet Buddy** — `mood: .ready` — "Hi, I'm Buddy! 🐾 Your friendly movement
     coach, here to cheer you on every day."
  2. **Day-by-day coaching** — `mood: .jogging` — "I turn your steps and runs
     into gentle, day-by-day guidance — toward 10,000 steps a day, without
     overdoing it."
  3. **Ask me anything** — `mood: .cheering` — "Tap the Coach tab to ask about
     your training, and get a friendly weekly review of how you're trending."
- A top-trailing **Skip** button (`Typography.caption`, `Palette.subtle`) that
  calls `onFinish`, present on every page except the last.
- On the last page, a primary **Get started** CTA reusing the gradient capsule
  button styling from `ConnectHero` (`LinearGradient([Palette.brand,
  Palette.brandDeep])`, white `Typography.headline`), calling `onFinish`.
- Respect Reduce Motion for any custom transitions (follow the `OverlayTransition`
  pattern in `ViewStyles.swift`); the `.page` style's own paging is fine.
- Accessibility: `PuffyBuddy` already exposes a label; mark decorative copy
  appropriately and give Skip/Get started clear labels.

Keep `OnboardingPage` (title/body/mood) as a small private model array so the
page count has one source of truth shared with `OnboardingState.startPage`
clamping.

### 3. Gate the tour at launch + wire replay into ContentView

**File**: `Sources/AppCore/ContentView.swift`

- In `init`, seed a new `@State private var showOnboarding` from
  `OnboardingState.shouldShow(defaults: .standard, seeded:
  HealthSource.isScenarioSeeded(), startScreen: UserDefaults.standard
  .string(forKey: "rbStartScreen") ?? "")`, and a `startOnboardingPage` from
  `OnboardingState.startPage()`.
- In `body`, after the existing `SettingsView` overlay block, add the tour as the
  top overlay:
  `if showOnboarding && previewMode.isEmpty { OnboardingFlowView(onFinish: …,
  startPage: startOnboardingPage).overlayTransition().zIndex(3) }`. `onFinish`
  calls `OnboardingState.markSeen()` then `withAnimation(Motion.overlay) {
  showOnboarding = false }`.
- Pass an `onReplayTour` closure into `SettingsView(...)` that runs
  `withAnimation(Motion.overlay) { showSettings = false; showOnboarding = true }`
  (page reset to 0).
- Fire analytics consistent with the existing `app_opened` capture, guarded by
  `previewMode.isEmpty`: `Analytics.shared.capture("onboarding_started")` when
  the tour appears and `"onboarding_completed"` on finish.

### 4. "Show welcome tour again" row in Settings

**File**: `Sources/AppCore/SettingsView.swift`

- Add `var onReplayTour: () -> Void = {}` to the view + its `init`.
- In the About (or Health-access) card, add an `actionRow("Show welcome tour
  again", icon: "sparkles", tint: Palette.sky) { onReplayTour() }` using the
  existing `actionRow` helper, so the styling matches every other Settings action.

## Reused existing code

- `PuffyBuddy` + `BuddyMood` from `Sources/AppCore/PuffyBuddy.swift` /
  `Theme.swift` (glossary entries: `PuffyBuddy`, `BuddyMood`) — the mascot for
  each page.
- `Palette`, `Typography`, `Layout`, `Motion` from `Sources/AppCore/Theme.swift`
  (glossary entry: `Typography`) — colors, fonts, spacing, and overlay easing.
- Gradient/capsule button styling and copy voice from `ConnectHero`
  (`Sources/AppCore/ConnectHero.swift`, glossary entry: `ConnectHero`) and
  `SignInView` (`Sources/AppCore/Auth/SignInView.swift`, glossary entry:
  `SignInView`).
- `ContentView` overlay/zIndex + `previewMode` gating pattern, and the
  `rbStartScreen` scenario-seed convention (glossary entry: `ContentView`).
- `HealthSource.isScenarioSeeded()` (glossary entry: `HealthSource`) — to skip
  the tour under scenario seeding by default.
- `UserPreferences` (glossary entry: `UserPreferences`) — the UserDefaults-backed,
  injectable-defaults pattern `OnboardingState` follows.
- `SettingsView.actionRow` + `card` helpers (glossary entry: `SettingsView`) —
  the replay row.
- `Analytics.shared.capture` from `Sources/AppCore/Analytics/Analytics.swift` —
  the onboarding events.
- `OverlayTransition` from `Sources/AppCore/ViewStyles.swift` — Reduce-Motion-safe
  overlay presentation.

### Tests

**New file**: `Tests/AppCoreTests/OnboardingStateTests.swift`

Pure-logic unit tests for `OnboardingState` against an injected `UserDefaults`
(suite name), mirroring `SessionStoreTests`/`ModelTests`:

- First launch (nothing seen, not seeded) → `shouldShow == true`.
- After `markSeen()` → `shouldShow == false`.
- Seeded scenario run, no opt-in → `shouldShow == false`.
- `startScreen == "onboarding"` forces `shouldShow == true` even when `hasSeen`.
- `startPage` reads/clamps `rbOnboardingPage` (negative → 0, beyond last → last,
  unset → 0).

The views (`OnboardingFlowView`, the Settings row) follow the existing
convention where presentational views like `SignInView`/`ConnectHero` carry no
unit tests and are exercised through scenarios instead.

## Scenarios to Demonstrate

- **Welcome — Meet Buddy** (`rbStartScreen="onboarding"`, `rbOnboardingPage=0`):
  page one with Buddy waving and the Skip affordance.
- **Welcome — Day-by-day coaching** (`rbOnboardingPage=1`): the middle page,
  page dots showing progress.
- **Welcome — Ask me anything** (`rbOnboardingPage=2`): the final page with the
  "Get started" CTA.
- **Welcome at large text** (`rbStartScreen="onboarding"`,
  `rbContentSize="accessibility3"`): a page rendered at an accessibility Dynamic
  Type size to confirm copy + button wrap gracefully.
- **Settings — replay row**: the Settings sheet showing the "Show welcome tour
  again" action row.
