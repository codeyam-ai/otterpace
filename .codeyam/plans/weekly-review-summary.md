---
title: "Weekly Review — Generated Training Summary"
mode: ui
createdAt: "2026-06-22T22:55:42Z"
---

mode: ui

## Goal

A weekly recap surface the AI coach generates from the same `TodayState` /
`WeeklyLoad` context: **what went well, what changed, training risk, suggested
next week, and one focus area.** Read-only, encouraging, never shame-based —
consistent with the coach's safety rules.

## What exists today

- `WeeklyLoad` domain type (`Sources/AppCore/Model.swift`) — weeklyMileage,
  daysRunThisWeek, longestRunMiles, restDaysThisWeek, loadTrend.
- `WeeklyLoadCard` (`Sources/AppCore/WeeklyLoadCard.swift`) — the compact Today
  snapshot of the same data.
- `CoachRecommendation` + curated/mock coach logic (added with Ask Coach).

## What to build

- A `WeeklyReview` value type (sections above) derived from `WeeklyLoad` +
  recent workouts via a deterministic, testable summarizer (pure function over
  context → curated/templated prose, same mock approach as the coach).
- A `WeeklyReviewCard` / screen presenting the five sections with a Buddy mood
  and a clear "one focus area" callout.
- Entry point reached from the Coach tab (added with Ask Coach).

## Scenarios (data states)

- **Solid week** — consistent runs, building load, positive recap.
- **Spiking load** — 40% week-over-week jump → risk callout + easy-week focus.
- **Sparse / mostly rest** — few sessions, gentle "ease back in" framing.
- **Empty** — no activity history yet → encouraging first-week prompt.

## Out of scope

- Real LLM generation, charts/graphs, Strava effort trends, notifications.