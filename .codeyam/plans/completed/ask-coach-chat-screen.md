---
title: "Ask Coach — Chat Screen (Mock Coach, Milestone 2)"
mode: ui
createdAt: "2026-06-22T22:58:59Z"
---

mode: ui

## Goal

Add an **Ask Coach** chat screen where the user types a fitness question and
Buddy replies with a practical, **injury-aware** answer. Mock mode: answers are
**curated by intent** from the user's own activity context — deterministic, so
scenarios are stable. This is Milestone 2's chat surface; the Coach *card* on
Today already exists.

## What exists today

- `CoachCard` (`Sources/AppCore/CoachCard.swift`) — read-only Today
  recommendation, brand/gold normally, amber + shield when `safetyFlag`.
- `CoachRecommendation` + `TodayState` (`Sources/AppCore/Model.swift`) — the
  context (steps, weekly mileage, last run, rest days, load trend).
- `Palette` + `BuddyMood` (`Sources/AppCore/Theme.swift`) — 7 moods, accent +
  caption. Reused for bubble tint.
- `ContentView` — root branches: scenario showcase / `TodayDashboard` /
  `ConnectHero`. Seed-driven via flat `rb*` UserDefaults keys.

## What to build

- **CoachEngine** (`Sources/AppCore/CoachEngine.swift`) — pure, testable logic:
  - `CoachIntent`: classify a question → `runOrRest`, `hit10K`,
    `mileageTooFast`, `injuryPain`, `postRunReflection`, `general`.
  - `reply(to:context:) -> CoachReply` — curated, context-aware, safety-aware
    answer text + a `BuddyMood` + `safetyFlag`. Obeys the coach safety rules:
    never diagnoses; injury/pain → ease off + see a clinician for sharp/
    persistent/worsening pain; prefers walk/rest when data suggests fatigue.
- **AskCoachView** (`Sources/AppCore/AskCoachView.swift`) — chat screen:
  message bubbles, a **blank text input + send button** (no suggestion chips).
  On send: append the user bubble, run `CoachEngine`, append Buddy's reply
  tinted by mood and shield-marked when `safetyFlag`.
- **Navigation — both entry points:** the connected branch of `ContentView`
  becomes a **tab bar (Today / Coach)**; a seed key (`rbStartTab`) picks the
  launch tab. The Today `CoachCard` gets an **"Ask Buddy" button** that switches
  to the Coach tab.

## How it's shown (scenarios)

Seed-driven, consistent with the existing `rb*` model. A scenario seeds
`rbStartTab="coach"` to land on the chat, and an optional seeded opening
question (`rbAskSeedQuestion`) so a populated conversation renders
deterministically in the screenshot. Production (no seed) → normal Today flow,
empty by default.

- **Empty chat** — coach tab, no messages yet (day-one chat state).
- **Run vs rest** — "Can I run or should I rest?" after a hard run yesterday →
  easy/rest answer, `concerned`/`recovery` Buddy.
- **Hit 10K** — "How do I get to 10K without overdoing it?" mid-day step gap →
  gentle walk suggestion.
- **Injury/pain** — "My knee hurts after my run" → safety-flagged,
  non-diagnostic, see-a-clinician reply.
- **Mileage spike** — "Am I increasing mileage too fast?" with 40% week jump →
  caution answer.

## Out of scope

- Real LLM / BYO-API-key generation (Milestone 3), suggestion chips, persisting
  chat history, HealthKit/Strava wiring, the Weekly Review and Activity History
  screens (queued separately).