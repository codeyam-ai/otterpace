# Buddy Mascot & Loader — Style/Branding Variations

mode: ui

## Goal

Explore **3 distinct visual directions** for the Buddy mascot and a matching
loader for each, so we can compare them side-by-side in the Live Preview and
pick a winner (or mix-and-match). This is a design-exploration feature — the
output is a comparison set to react to, not one finalized design.

## What exists today

- `BuddyView` (`Sources/AppCore/BuddyView.swift`) — a SwiftUI shape-drawn dog
  mascot with 7 moods, used in `ConnectHero` (size 140) and `BuddySummaryCard`
  (size 92, with `MoodChip`).
- `Theme.swift` — shared `Palette` (coral brand + go/sky/amber/gold/lilac) and
  `BuddyMood` enum (`.accent`, `.caption`). Every variation reuses these tokens.
- **No loader/splash component exists.** The loader is net-new.

## Three directions (all SwiftUI shapes — no image assets)

- **A — Refined Pup**: today's dog, polished. Softer gradients, rounder
  proportions, a gentle drop shadow. Brand continuity / lowest risk.
  Loader: run-in-place with motion puffs + a bouncing ground shadow.
- **B — Geometric Minimal**: flat, modern, 2-tone Buddy from clean circles and
  arcs. Reads great at small sizes (tab bar / nav). Icon/sticker feel.
  Loader: orbiting paw-print/dot ring around a minimal Buddy face.
- **C — Energetic Sticker**: bold outlined, high-saturation, expressive eyes,
  thick strokes (playful, Duolingo-ish).
  Loader: squash-and-stretch hop with a dust trail.

Each direction renders across all 7 moods (resting / ready / jogging / cheering
/ concerned / celebrating / recovery) and exposes its loading state.

## How it's shown

Buddy and the loader are **pure presentational** views driven by the `mood`
enum — no DB rows, so production stays empty (CodeYam default). Variations are
shown via scenarios that seed which direction + mood to render, consistent with
the existing seed-driven (`rbBuddyMood`, …) scenario model.

## Scenarios (visual states)

- **Default** — each direction at `ready` mood (everyday state).
- **Mood variants** — each direction across cheering / concerned / resting /
  celebrating / recovery / jogging (expressiveness, incl. the safety-sensitive
  "concerned" read).
- **Loading state** — each direction's loader animation.
- **Small-size edge** — each direction at ~28pt (tab-bar legibility).

## Out of scope

- Wiring a final choice into `ConnectHero` / `BuddySummaryCard` app-wide — that
  happens after you pick a direction.
- New moods, Strava/HealthKit, the Ask Coach screen.
