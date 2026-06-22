---
title: "Activity History — Recent Workouts & Load Basics"
mode: ui
createdAt: "2026-06-22T22:55:50Z"
---

mode: ui

## Goal

A scrollable history of recent workouts with **weekly mileage, run frequency,
and training-load basics** (Milestone 4), so the user can see their progress
beyond just today.

## What exists today

- `LatestWorkout` + `WeeklyLoad` domain types (`Sources/AppCore/Model.swift`).
- `WorkoutCard` (`Sources/AppCore/WorkoutCard.swift`) — single-workout card,
  reusable as a list row.
- Seed-driven scenario model (`rb*` UserDefaults keys) for injecting state.

## What to build

- Extend the model with a `workouts: [LatestWorkout]` history list (source-
  tagged healthkit/strava) plus a derived weekly rollup (mileage, run count,
  rest days).
- An `ActivityHistoryView` listing workouts grouped by week with a header
  rollup; rows reuse `WorkoutCard` styling.
- Reached from the Coach/Today navigation; production starts empty.

## Scenarios (data states)

- **Empty** — no workouts yet → day-one empty state.
- **Sparse** — 1–2 recent workouts.
- **Rich** — multiple weeks, mixed run/walk, enough to exercise grouping.
- **Long values** — very long run + high mileage week (layout/number edge).

## Out of scope

- Strava OAuth/import (Milestone 5), dedup, maps/routes, per-workout detail
  screen, editing workouts.