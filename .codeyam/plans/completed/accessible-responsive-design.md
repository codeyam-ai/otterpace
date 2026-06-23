---
title: "Accessible & Responsive Design — Contrast, Dynamic Type, Layout"
mode: ui
createdAt: "2026-06-23T17:10:00Z"
source: manual
---

## Summary

Raise the whole RunBuddy UI to WCAG AA contrast and make every surface scale
with the user's text-size setting and screen size. Today the captions and
labels everywhere use `Palette.subtle` (a #737A8A grey ≈ 3.4:1 on the white
cards and the cream/tan gradient — below the 4.5:1 AA floor, worst on the
11–14pt labels), body copy is dimmed further with `ink.opacity(0.8/0.85)`, and
every view hard-codes `.font(.system(size:))` so text ignores Dynamic Type.
Fixed frames (`StepRing` 150×150) and the 3-up `StatsRow` HStack clip at large
text sizes or on small phones, and most controls lack accessibility labels.
The fix is centralized: introduce a scalable typography scale + an accessible
text color in `Theme.swift`, then adopt those tokens across the section
components so the whole app inherits contrast, Dynamic Type, and reflow at once.

## Key Decisions

- **Centralized tokens over per-view patches** — the same fixed fonts and grey
  recur across ~15 files, so a shared `Typography` scale and a darkened
  `Palette.subtle` give one source of truth and fix everything consistently.
  Targeted patches were rejected as they'd leave the inconsistency in place.
- **Dynamic Type via relative fonts, not raw point sizes** — replace
  `.font(.system(size: N, …))` with `.font(.system(.textStyle, design:…))` (or
  `size:relativeTo:`) so text scales with the user's setting while keeping the
  rounded, heavy display look the brand uses. Use `@ScaledMetric` for the few
  geometry constants that must track text size (e.g. `StepRing` diameter).
- **Darken `subtle`, stop dimming body text** — change `Palette.subtle` to a
  darker grey that clears 4.5:1 on both `Palette.card` (white) and `bgTop`
  (cream), and drop the `ink.opacity(0.8/0.85)` on body/coach/chat copy so it
  renders at full ink. Keep the warm brand accents (coral/gold/amber/etc.)
  unchanged — they're decorative tints, not text.
- **Reflow, don't truncate** — let `StatsRow` switch from a fixed 3-up HStack to
  a wrapping/adaptive layout at accessibility text sizes, and let `StepRing`
  scale with `@ScaledMetric`, so large type and small screens never clip.
- **Labels describe state, not decoration** — give the meaningful controls
  (`StepRing` progress, stat tiles, mood chip, trend badge, send button)
  accessibility labels/values; mark purely decorative shapes as hidden.

## Implementation

### 1. Add accessible color + a scalable typography scale

**File**: `Sources/AppCore/Theme.swift`

- Darken `Palette.subtle` from `(0.45, 0.47, 0.54)` to a value that clears
  ~4.5:1 on both white and the `bgTop` cream (around `(0.34, 0.36, 0.43)` —
  verify against both backgrounds). Leave the brand/go/sky/amber/gold/lilac
  accents and `ink` as-is.
- Add a `Typography` enum (or a set of `Font` helpers) exposing the app's
  roles — e.g. `largeTitle`, `title`, `headline`, `body`, `caption`,
  `captionStrong` — each built from a SwiftUI text style with the rounded
  design and weights already in use, so they scale with Dynamic Type. This is
  the single place point-sizes map to relative styles.

### 2. Make shared card chrome scale-aware

**File**: `Sources/AppCore/ViewStyles.swift`

Keep `cardStyle()` but ensure corner radius/shadow read fine at large type;
no behavioral change required beyond confirming padding comes from callers.
(Most reflow happens in the section components below.)

### 3. Adopt typography tokens + accessible color across section components

**Files**:
- `Sources/AppCore/TodayHeader.swift`
- `Sources/AppCore/StatTile.swift` / `Sources/AppCore/StatsRow.swift`
- `Sources/AppCore/CoachCard.swift`
- `Sources/AppCore/WeeklyLoadCard.swift`
- `Sources/AppCore/WorkoutCard.swift`
- `Sources/AppCore/BuddySummaryCard.swift`
- `Sources/AppCore/ConnectHero.swift`
- `Sources/AppCore/MoodChip.swift`
- `Sources/AppCore/TrendBadge.swift`
- `Sources/AppCore/AskCoachHeader.swift`
- `Sources/AppCore/AskCoachEmptyState.swift`
- `Sources/AppCore/AskCoachInputBar.swift`
- `Sources/AppCore/ChatBubble.swift`

For each: replace `.font(.system(size: N, …))` with the matching `Typography`
role, replace `Palette.subtle` captions with the new darker token, and remove
`Palette.ink.opacity(0.8/0.85)` on body/coach/chat text so it renders at full
ink. Add `lineLimit`/`minimumScaleFactor` only where a value must stay on one
line (e.g. capsule pills); prefer wrapping for sentences.

### 4. Reflow the quick-stats row for large type / small screens

**File**: `Sources/AppCore/StatsRow.swift` (and `StatTile.swift`)

At accessibility text sizes the fixed 3-up `HStack` overflows. Switch to a
layout that wraps to a vertical/2-column arrangement when
`@Environment(\.dynamicTypeSize)` is an accessibility size (e.g. swap HStack →
adaptive `Grid`/`ViewThatFits`), so tiles never clip.

### 5. Scale the step ring with text size

**File**: `Sources/AppCore/StepRing.swift`

Replace the hard `.frame(width: 150, height: 150)` and fixed inner fonts with
`@ScaledMetric` diameter + `Typography` roles so the ring grows with Dynamic
Type. Add `accessibilityElement(children: .ignore)` with a label like
"Daily steps" and an `accessibilityValue` of the count / goal percentage.

### 6. Add accessibility labels to meaningful controls

**Files**: `StatTile.swift`, `MoodChip.swift`, `TrendBadge.swift`,
`AskCoachInputBar.swift`, `CoachCard.swift`

- `StatTile`: combine icon+value+label into one element with a spoken label
  (e.g. "Active minutes, 42").
- `MoodChip` / `TrendBadge`: expose the caption/trend as a label; hide the
  decorative glyph.
- `AskCoachInputBar`: label the send button ("Send message") and the field
  ("Ask Buddy a question"); ensure the 40×40 tap target is preserved.
- `CoachCard`: label the "Ask Buddy" button.

## Reused existing code

- `Palette` and `BuddyMood` from `Sources/AppCore/Theme.swift` (glossary entry:
  `BuddyMood`) — extended in place; accents reused unchanged for tints.
- `cardStyle()` from `Sources/AppCore/ViewStyles.swift` — shared card chrome,
  unchanged.
- Existing accessibility pattern from `Sources/AppCore/PuffyBuddy.swift`
  (glossary entry: `PuffyBuddy`) and `PuffyBuddyLoader` (glossary entry:
  `PuffyBuddyLoader`) — `accessibilityElement(children: .ignore)` +
  `accessibilityLabel` — extended to the remaining controls.
- Section components already composed by `TodayDashboard` (glossary entry:
  `TodayDashboard`) and `AskCoachView` (glossary entry: `AskCoachView`) — only
  their fonts/colors/labels change, not their composition.
- `StatTile` / `StatsRow` / `StepRing` / `WeeklyLoadCard` / `WorkoutCard` /
  `CoachCard` glossary entries — the surfaces being made accessible.

## Scenarios to Demonstrate

- **Default text size** — Today + Ask Coach look unchanged in layout but with
  AA-passing captions/labels (visual baseline).
- **Accessibility XXL text** — largest Dynamic Type size: all text scales,
  `StatsRow` reflows, `StepRing` grows, nothing clips or truncates a sentence.
- **Small screen (e.g. iPhone SE)** — 3-up stats and cards fit without
  horizontal clipping at default and large type.
- **Contrast audit state** — a side-by-side of the old grey vs. new darker
  caption color on both the white card and the cream `bgTop` background.
- **Safety-flagged coach reply** — amber/shield chat bubble still reads clearly
  at full ink and large type (the safety-sensitive surface stays legible).
- **VoiceOver labels** — step ring, stat tiles, mood chip, and send button
  expose meaningful spoken labels/values.
