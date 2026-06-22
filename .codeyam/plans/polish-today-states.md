---
title: "Polish Today — Empty States, Edge Cases & Buddy Moods"
mode: ui
createdAt: "2026-06-22T22:55:57Z"
---

mode: ui

## Goal

Refine the existing Today dashboard without adding a new screen: tighten the
**empty/day-one state, numeric edge cases, and Buddy mood expressiveness** so
the surface feels finished and never shame-based.

## What exists today

- `TodayDashboard` + section components (header, `BuddySummaryCard`,
  `StatsRow`, `CoachCard`, `WorkoutCard`, `WeeklyLoadCard`).
- 8 Today/Buddy scenarios already captured (Day One, Fresh Start, Almost There,
  Midday Nudge, Goal Crushed, Recovery Caution, Buddy moods/loader).

## What to build

- Polish the day-one `ConnectHero` empty state copy and spacing.
- Handle numeric edges: 0 steps, goal exceeded (>100%), very long pace/distance
  strings, missing optional sections.
- Audit Buddy mood mapping for the safety-sensitive `concerned`/`recovery`
  reads and ensure tone stays encouraging.
- Accessibility labels on key stats and the Buddy mascot.

## Scenarios (data states)

- **Day one (empty)** — refreshed connect hero.
- **Zero-step morning** — connected but 0 steps, gentle nudge.
- **Goal crushed** — >100% ring, celebrating Buddy.
- **Long-content edge** — long pace/distance/headline strings.

## Out of scope

- New screens (Ask Coach, Weekly Review, History), HealthKit/Strava wiring,
  new domain types.