---
title: "First-Run Clarity: Guided Tour, Tooltips, and Starter Questions"
mode: ui
createdAt: "2026-07-31T23:20:30Z"
source: manual
---

## Summary

A new user reported that after install they did not know what they were looking
at, what to do next, or what to ask the coach. Concretely: the mood chip under
Buddy just says "Ready" with no referent; "active min" reads `0` and looks like
a judgment rather than "no data yet"; "since moving" is unexplained (and on a
fresh install `movementLabel(0)` renders the cheerful-but-wrong "now"); the race
banner appears immediately, is unexplained, and its ✕ dismisses it permanently
on the first tap; and the Ask Coach screen offers a blank text field with no
idea of what a good question looks like.

This plan makes the first session self-explaining on all five fronts: a
Buddy-led scripted intro in the Coach tab with tappable starter questions, a
dismissible spotlight tour over the Today dashboard, tap-to-reveal `ⓘ` hints on
the ambiguous elements, honest "no data yet" stat tiles instead of misleading
zeroes, and a race banner that arrives later, explains itself, and snoozes
rather than self-destructing on the first ✕.

## Key Decisions

- **Tutorial is both a chat intro and a spotlight tour** — the two confusions
  are different. "What am I looking at?" is a Today-screen problem (spotlights),
  "what do I ask?" is a Coach-tab problem (scripted intro + starter chips).
  Doing only one leaves half the feedback unanswered.
- **The Today tour is NOT a new onboarding page.** `OnboardingScenarioIndexTests`
  pins every `rbOnboardingPage` seed against the step order; adding a step shifts
  every later index and silently recaptures the wrong screens
  (see `Tests/AppCoreTests/OnboardingScenarioIndexTests.swift:68`). The tour ships
  as its own overlay inside `TodayDashboard` with its own `TourState` gate, so
  `OnboardingState.introPageCount` / `personalizationStepCount` stay at 3 / 6 and
  no existing onboarding scenario moves. If the implementation ends up needing an
  onboarding step after all, it must update `expectedPage` and every
  `onboarding-*` / `welcome-*` seed in the same change.
- **The scripted coach intro is app-authored copy, not a fabricated model reply.**
  It renders in both the locked (no key) and unlocked empty states, because it
  never claims to be a generated answer. This preserves the existing honesty rule
  in `AskCoachLockedState.swift:3` ("invites them to connect one rather than
  faking a reply").
- **Starter questions are tappable only when the chat is unlocked.** With no key
  connected they render as non-tappable examples under the connect CTA, so the
  user learns what to ask without the app pretending to answer.
- **Starter questions are derived from `CoachIntent`, not hardcoded prose.** Each
  suggestion is written so `CoachIntent.classify` routes it to the intent it was
  written for, and a test asserts that. Race and post-run suggestions only appear
  when `today.races` / `today.latestWorkout` make them meaningful.
- **Hints are tap-to-reveal inline captions, not `.popover` / `.help()`.** The
  macOS test build targets macOS 12 and `.help()` is macOS-only; an inline
  disclosure compiles everywhere, captures deterministically in a scenario, and
  needs no anchor math.
- **Race banner dismissal becomes a snooze, then permanent.** The current
  `RacePromptState.markDismissed` writes one forever-flag on the first ✕
  (`Sources/AppCore/RaceGoals.swift:200`), which is exactly what the user did by
  reflex. Two snoozes, then permanent, and it does not appear at all on day one.
- **Zero is replaced with `—` only when the day genuinely has no data**, not
  whenever a metric is zero. A real zero-step morning (`today-zero-step-morning`)
  must keep reading `0`.

## Implementation

### 1. Reusable hint affordance

**New file**: `Sources/AppCore/InfoHint.swift`

A small `ⓘ` button that toggles an inline explanatory caption beneath its host.
Takes a `HintTopic`, animates with `Motion.overlay`, and carries an
`accessibilityLabel` ("Explain <topic>") plus `accessibilityHint`. No popover, no
anchor math — it renders a `Text` in the host's own layout so it works inside
cards, the stats row, and at accessibility text sizes.

Provide a `hinted(_:)` view modifier so hosts can attach a hint without
restructuring their layout.

**New file**: `Sources/AppCore/HintCopy.swift`

Pure, SwiftUI-free copy table (same spirit as `Formatters.swift`):

```
enum HintTopic: String, CaseIterable {
    case buddyMood, stepRing, activeMinutes, distance, sinceMoving,
         coachCard, checkIn, weeklyLoad
}
```

with `title` and `body` per topic. Copy answers the literal questions raised:

- `buddyMood` — "Buddy's read on today. It changes with your steps, your latest
  run, and how hard your week has been. 'Ready' means nothing is holding you back."
- `activeMinutes` — "Minutes Apple Health scored as brisk movement today. It
  fills in through the day, so it starts at zero every morning."
- `sinceMoving` — "How long since Apple Health last recorded you moving. Useful
  for spotting a long sit."
- plus `stepRing`, `distance`, `coachCard`, `checkIn`, `weeklyLoad`.

No em dashes in user-facing strings (matches the `scenario-copy-em-dash-cleanup`
convention already applied across the app's copy).

### 2. Today: name what Buddy's mood refers to

**File**: `Sources/AppCore/BuddySummaryCard.swift`

Add a leading caption row above the Buddy/ring pair: `Text("Buddy's read on today")`
in `Typography.caption` + `InfoHint(.buddyMood)`. The mood word now has a visible
referent instead of floating under the mascot.

**File**: `Sources/AppCore/MoodChip.swift`

No behavior change; confirm the existing `accessibilityLabel` ("Buddy mood: …")
still reads correctly once the card caption is present, and avoid duplicating the
caption for VoiceOver (the card already sets `accessibilityElement(children: .ignore)`
on the Buddy column at `BuddySummaryCard.swift:17`).

### 3. Today: honest stat tiles instead of misleading zeroes

**File**: `Sources/AppCore/Formatters.swift`

Add pure helpers next to `movementLabel`:

- `hasDayData(steps:activeMinutes:distanceMiles:) -> Bool` — true when any of the
  three is above zero.
- `statValue(_ value: String, hasData: Bool) -> String` — returns `"—"` when the
  day has no data at all, else the value.
- `movementDisplay(minutes: Int, hasData: Bool) -> String` — returns `"—"` when
  there is no recorded movement to measure from, else delegates to `movementLabel`.
  This fixes the fresh-install case where `movementLabel(0)` currently renders
  "now" (`Formatters.swift:21`) even though nothing has been recorded.

**File**: `Sources/AppCore/StatsRow.swift`

Compute `hasData` once from `today`, route all three tiles through the helpers,
and when `!hasData` swap the tile labels to a "no data yet" caption. Relabel
`"since moving"` to `"since you moved"` (the abbreviation was read as a fragment).
Attach `InfoHint(.activeMinutes)`, `.distance`, `.sinceMoving` to the tiles.

**File**: `Sources/AppCore/StatTile.swift`

Add an optional `hint: HintTopic?` and an optional `subtitle`, so the tile can
render the `ⓘ` and the "no data yet" line without the callers wrapping it.
Keep the existing `accessibilityElement(children: .ignore)` + combined label, and
extend the label so VoiceOver says "no active minutes recorded yet" rather than
"— active min".

### 4. Ask Coach: Buddy-led intro + starter questions

**New file**: `Sources/AppCore/Coach/CoachTutorial.swift`

Pure and testable, like `CoachEngine`:

- `CoachTutorial.openingTurns(for context: TodayState, connected: Bool) -> [String]`
  returns the scripted welcome. Two or three short Buddy turns: who Buddy is, what
  data it can actually see (today's steps, recent runs, weekly load, your journal
  check-ins, any races you have added), what it cannot see, and an invitation to
  tap a question below or type your own. When `connected == false` the last turn
  names the connect step instead of the invitation.
- Copy adapts to a day-one state (`context.workouts.isEmpty`) so it does not
  promise run analysis the app cannot do yet.

**New file**: `Sources/AppCore/StarterQuestions.swift`

Pure derivation of the ice-breaker chips:

- `StarterQuestions.suggestions(for context: TodayState) -> [StarterQuestion]`
  where `StarterQuestion` carries `text` and the `CoachIntent` it targets.
- Always offered: `runOrRest` ("Should I run today or rest?"), `hit10K`
  ("How do I get to 10,000 steps today?"), `general` ("What should I focus on
  this week?").
- Conditional: `postRunReflection` when `context.latestWorkout != nil`;
  `raceGoal` when `context.races` has an upcoming entry; `mileageTooFast` when
  `context.loadHistory` has at least two points.
- Capped at four so the chip row never dominates the screen.

**File**: `Sources/AppCore/AskCoachEmptyState.swift`

Replace the single static prompt with the scripted intro: Buddy, the
`CoachTutorial.openingTurns` rendered as `ChatBubble`s (reuse
`Sources/AppCore/ChatBubble.swift`), then a wrapping chip row of
`StarterQuestions.suggestions`. Takes `context: TodayState`, `connected: Bool`,
and `onPick: (String) -> Void`.

**File**: `Sources/AppCore/AskCoachLockedState.swift`

Below the existing connect CTA, render the same suggestions as non-tappable
example chips under a caption ("Once you connect a key, you can ask things
like…"), so an unconnected user still learns the shape of a good question.

**File**: `Sources/AppCore/AskCoachView.swift`

- Pass `model.today` and `chatUnlocked` into `AskCoachEmptyState`, and wire
  `onPick` to the existing `submit(_:)` so a tapped chip travels the exact same
  path as a typed question (real coach when a key is connected, deterministic
  `CoachEngine` fallback otherwise).
- Keep the `rbAskSeedQuestion` seeding path untouched.
- Capture `starter_question_tapped` with the target intent's raw value (no PII).

### 5. Today spotlight tour

**New file**: `Sources/AppCore/Tour/TourStep.swift`

Pure enum of the tour's steps in order — `buddy`, `stats`, `coachCard`,
`checkIn`, `history` — each with `title`, `body`, and an `anchorID`. Mirrors the
`HintCopy` style so the copy is testable without a view.

**New file**: `Sources/AppCore/Tour/TourState.swift`

UserDefaults-backed gate, modeled directly on `OnboardingState`
(`Sources/AppCore/Onboarding/OnboardingState.swift`) so the two behave alike:

- `seenKey = "otterpaceTodayTourSeen"`, `hasSeen` / `markSeen` / `clearSeen`
  (the last so Settings can replay it).
- `shouldShow(defaults:seeded:startScreen:healthConnected:)` — pure and
  deterministic: forced when `rbStartScreen == "tour"`; never when already seen;
  never under a scenario seed unless opted in; never before Health is connected
  (so it cannot fire over `ConnectHero`); otherwise show.
- `startStep(_:)` reading `rbTourStep`, clamped into range, exactly like
  `OnboardingState.startPage`.

**New file**: `Sources/AppCore/Tour/TodayTourOverlay.swift`

Scrim + themed callout card naming the highlighted element, with a step-dot
indicator, "Next" / "Got it" primary and a "Skip tour" secondary. Uses
`anchorPreference` / `overlayPreferenceValue` (available on the macOS 12 test
build) to position the callout near the highlighted section; falls back to a
centered card when no anchor is resolved, so a launch-seeded capture is never
blank. Reuses `Palette` / `Typography` / `Motion.overlay` and the gradient
capsule button styling already used by `RacePromptBanner` and the onboarding
primary button.

**File**: `Sources/AppCore/TodayView.swift`

- Add `@State private var tourStep: Int?` initialized in `init` from
  `TourState.shouldShow(...)` + `TourState.startStep(...)`, matching how
  `showHistory` / `showJournalEditor` are seeded so a capture renders the tour
  complete on the first frame (`TodayView.swift:31-39`).
- Tag `BuddySummaryCard`, `StatsRow`, `CoachCard`, `CheckInCard`, and
  `ActivityHistoryButton` with the tour anchor preference.
- Present `TodayTourOverlay` at the top of the existing `ZStack` (above the
  history and journal overlays), advancing through `TourStep.allCases` and
  calling `TourState.markSeen()` on finish or skip.
- Analytics: `tour_started`, `tour_step_viewed` (with the step name),
  `tour_completed`, `tour_skipped`.

**File**: `Sources/AppCore/SettingsView.swift`

Add a "Show the Today tour again" action row beside the existing "Show welcome
tour again" row (`SettingsView.swift:903`), calling a new `onReplayTodayTour`
closure that clears `TourState` and closes Settings.

**File**: `Sources/AppCore/ContentView.swift`

Pass `onReplayTodayTour` through to `SettingsView`, following the existing
`onReplayTour` wiring (`ContentView.swift:113`).

### 6. Race banner: arrive later, explain itself, snooze instead of vanishing

**File**: `Sources/AppCore/RaceGoals.swift`

Extend `RacePromptState` (currently a single boolean at line 200) into a pure,
testable snooze:

- Keys: `otterpaceRacePromptSnoozedUntil` (ISO date), `otterpaceRacePromptDismissCount`,
  `otterpaceRacePromptFirstEligible` (ISO date, stamped the first time the banner
  would qualify).
- `shouldShow(asOf:races:defaults:) -> Bool` — false when an upcoming race exists;
  false while snoozed; false until the user has been eligible for at least one
  day (so it never lands in the confusing first session); false once the dismiss
  count reaches 2.
- `snooze(asOf:defaults:)` — bumps the count and sets the snooze date 14 days out;
  at count 2 it becomes permanent.

**File**: `Sources/AppCore/RacePromptBanner.swift`

- Keep the `forceRacePrompt` scenario override so `today-race-prompt-banner` and
  `today-past-race-banner-returns` still capture.
- Rewrite the body copy to say what actually happens: "Add your race and I will
  shape your weeks around it: long runs, taper, and race week."
- Replace the bare ✕ with an explicit "Not now" text button alongside an "Add a
  race" primary, so dismissal is a considered tap rather than a reflex. Keep a
  ✕-equivalent accessibility action.

**File**: `Sources/AppCore/TodayView.swift`

Route `showRacePrompt` through `RacePromptState.shouldShow(asOf: todayISO, races: model.today.races)`
(replacing the inline `!hasUpcoming && !racePromptDismissed` at line 69-71) and
call `snooze` from the dismiss handler. Capture `race_prompt_snoozed` with the
dismiss count.

### 7. Tests

**New**: `Tests/AppCoreTests/TourStateTests.swift` — gating matrix (first run vs.
seen vs. seeded vs. Health not connected vs. `rbStartScreen="tour"`), step-index
clamping, and a scenario-index guard in the style of
`OnboardingScenarioIndexTests` asserting every `tour-*` scenario's seeded
`rbTourStep` matches the step it is named for.

**New**: `Tests/AppCoreTests/StarterQuestionsTests.swift` — day-one vs. rich
state produce the right suggestions; conditional suggestions appear only when
their data exists; the list is capped and duplicate-free; and every suggestion
round-trips through `CoachIntent.classify` to the intent it declares.

**New**: `Tests/AppCoreTests/CoachTutorialTests.swift` — the opening turns are
non-empty for both connected and locked, adapt to a day-one context, and contain
no em dashes.

**New**: `Tests/AppCoreTests/HintCopyTests.swift` — every `HintTopic` has a
non-empty title and body, and no copy contains an em dash.

**Extend**: `Tests/AppCoreTests/FormattersTests.swift` — `hasDayData`,
`statValue`, and `movementDisplay`, specifically that a genuine zero-step morning
still renders `0` while a no-data install renders `—`.

**Extend**: `Tests/AppCoreTests/RaceGoalsTests.swift` — banner suppressed on day
one, suppressed while snoozed, returns after the snooze window, permanent after
the second dismissal, and always suppressed while an upcoming race exists.

**Extend**: `Tests/AppCoreTests/OnboardingStateTests.swift` — assert the
onboarding step counts are unchanged, so the tour work cannot quietly shift the
`rbOnboardingPage` seeds.

## Reused existing code

- `OnboardingState` from `Sources/AppCore/Onboarding/OnboardingState.swift`
  (glossary entry: `OnboardingState`) — the exact pattern `TourState` mirrors:
  UserDefaults-backed, injectable defaults, pure `shouldShow` / clamped
  `startPage`.
- `CoachIntent` / `CoachEngine.classify` and `CoachEngine.reply` from
  `Sources/AppCore/CoachEngine.swift` (glossary entry: `CoachEngine`, tested by
  `Tests/AppCoreTests/CoachEngineTests.swift`) — starter questions target these
  intents and tapped chips answer through the existing path.
- `ChatBubble` from `Sources/AppCore/ChatBubble.swift` (glossary entry:
  `ChatBubble`) — renders the scripted tutorial turns.
- `BuddyView` / `BuddyMood` from `Sources/AppCore/Theme.swift` (glossary entry:
  `BuddyMood`, tested by `Tests/AppCoreTests/BuddyMoodTests.swift`) — mascot and
  mood captions in the intro and the tour callouts.
- `Formatters` helpers (`movementLabel`, `formatted`, `miles`) from
  `Sources/AppCore/Formatters.swift`, tested by
  `Tests/AppCoreTests/FormattersTests.swift` — the new no-data helpers live
  beside them and stay SwiftUI-free.
- `RacePromptState` / `RaceGoal.hasUpcoming` from `Sources/AppCore/RaceGoals.swift`
  (glossary entries: `RacePromptState`, `RacePromptBanner`) — extended rather
  than replaced.
- `SettingsActionRow` from `Sources/AppCore/SettingsActionRow.swift` (glossary
  entry: `SettingsActionRow`) — the "Show the Today tour again" row.
- `Motion.overlay`, `Palette`, `Typography`, `cardStyle()` from
  `Sources/AppCore/Theme.swift` / `Sources/AppCore/ViewStyles.swift` — so every
  new surface retints across all five themes.
- `Analytics.shared.capture` from `Sources/AppCore/Analytics` — same PII-free
  event convention as `onboarding_step_skipped` / `race_prompt_dismissed`.

## Scenarios to Demonstrate

- `tour-step-buddy` — the spotlight tour's first step over the Buddy card on a
  populated Today.
- `tour-step-stats` — the tour explaining the three stat tiles.
- `tour-step-coach-card` — the tour pointing at the coach card and the Coach tab.
- `today-day-one-no-data` — fresh install, Health connected, no movement yet:
  all three tiles read `—` with "no data yet", no race banner.
- `today-zero-step-morning` (existing, re-verify) — a real zero-step morning
  still reads `0`, not `—`, so the honest-empty change did not swallow a true zero.
- `today-hint-active-minutes-open` — the `ⓘ` expanded on the active-minutes tile.
- `today-hint-buddy-mood-open` — the `ⓘ` expanded on "Buddy's read on today".
- `ask-coach-tutorial-intro` — the scripted Buddy intro plus four starter chips,
  key connected.
- `ask-coach-tutorial-locked` — the connect CTA with the same suggestions shown
  as non-tappable examples.
- `ask-coach-starter-day-one` — starter chips on a day-one state: no post-run or
  race suggestion offered.
- `ask-coach-starter-race-week` — starter chips including the race question when
  an upcoming race exists.
- `today-race-prompt-explained` — the rewritten banner with "Add a race" and
  "Not now".
- `accessibility-large-text-tour` — the tour callout and the hint captions at an
  accessibility text size, confirming nothing clips.
