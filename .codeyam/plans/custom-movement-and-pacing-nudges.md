---
title: "Custom Movement & Pacing Nudges"
mode: ui
createdAt: "2026-07-30T18:27:00Z"
source: manual
---

## Summary

**Draft — to be fleshed out before running.** Today Otterpace ships three fixed
reminders (`daily` at a time you pick, `goal` hard-coded to 7pm, `inactivity`
after 2/3/4 hours) with fixed copy, one schedule, and no awareness of *how* you
run. This plan opens that up in two directions: **customization** — user-chosen
times, per-day-of-week schedules, quiet hours, tone, and how many nudges a day
is too many — and **pacing** — nudges that speak to your training, not just your
step count ("that was a hard one, tomorrow's an easy day", "you're 2k from your
goal with an hour of daylight left", "third day on — how about a rest day").

Direction is settled; the specifics below are open questions for the fleshing-out
pass.

> **Sequencing note:** this plan makes Otterpace send *more* notifications. The
> companion plan **`activity-freshness-and-smarter-nudge-suppression`** fixes the
> false-positive problem (nudges that fire because the app didn't know you'd
> already moved). Landing more nudges on top of a stale-data problem multiplies
> the annoyance — strongly prefer running that plan first, or at minimum
> including its freshness check as a precondition on every new nudge here.

## Key Decisions

*(Provisional — revisit when fleshing out.)*

- **Extend `ReminderSettings`, don't replace it.** The existing struct
  (`Sources/AppCore/Notifications/MovementReminders.swift`) already has the
  UserDefaults-backed, injectable, unit-tested shape. New fields default to
  today's behavior so an existing user's reminders don't change under them on
  update — the same additive-with-defaults discipline `TodayState` uses.
- **Keep every scheduling *decision* pure.** `InactivitySchedule.fireDate` is the
  model: platform glue stays thin, the decision is an XCTest-covered pure
  function. Every new nudge type gets the same treatment, so pacing rules are
  testable without a device.
- **A hard daily cap, set by the user.** More nudge types must not mean more
  nudges by default. A per-day ceiling (default low, e.g. 2) with a priority
  order deciding which nudge wins is a first-class part of the design, not a
  follow-up.
- **Copy stays in `ReminderCopy`, in Buddy's voice.** Never-shame, never a streak
  threat. Tone variants (quieter / warmer / more direct) are a user setting, not
  a reason to loosen the voice rules.
- **Local-first.** Prefer `UNUserNotificationCenter` scheduling on-device;
  reach for the server/APNs path (`api/cron/movement-nudge.ts`,
  `api/_lib/apns.ts`, `PushRegistrationService`) only for nudges that genuinely
  can't be decided locally.

## Open Questions

- **Which pacing nudges earn a notification?** Candidates: post-run recovery
  ("yesterday was hard — easy today"), goal-proximity ("2,100 steps to go"),
  streak-adjacent-but-not-shaming ("day three — a rest day is training too"),
  race taper (`RaceGoal` data is already on `TodayState`), and weekly-review
  ready. Each needs a "would a real user thank us for this at 6pm?" test.
- **Per-day-of-week schedules** — a genuinely useful ask (weekends differ) but it
  multiplies the settings UI. Worth it, or is one schedule + quiet hours enough?
- **Quiet hours on-device.** The server has `DEFAULT_QUIET_HOURS` (21→8) in
  `api/_lib/nudge.ts`; the local scheduler has no equivalent. Unify them, and
  decide whether quiet hours are user-editable.
- **Goal nudge timing.** It's hard-coded to `ReminderSettings.goalHour = 19`.
  Make it user-set, or make it adaptive to when the user typically closes their
  goal (which needs the per-day step series — `dailySteps` on `TodayState`)?
- **How much of this can be captured as scenarios?** Notification delivery isn't
  scenario-capturable, but the Settings UI and any in-app nudge surfaces are.
- **Does the `CoachProfile` `trainingPhase` steer nudges?** It already steers the
  coach; reusing it would keep the "recovering" user from being nudged to move
  more, at no new data cost.

## Implementation

*(Sketch only — expand during the fleshing-out pass.)*

1. **`Sources/AppCore/Notifications/MovementReminders.swift`** — extend
   `ReminderSettings` (per-nudge times, day mask, quiet-hours window, daily cap,
   tone); extend `ReminderCopy` with the new nudge families; add pure
   `PacingSchedule` decision functions alongside `InactivitySchedule`.
2. **New** `Sources/AppCore/Notifications/NudgeBudget.swift` — the pure
   priority + daily-cap arbiter every nudge passes through before scheduling.
3. **`Sources/AppCore/SettingsView.swift`** — rework the reminders card into a
   fuller schedule editor (likely its own sub-screen once per-day schedules land).
4. **`Sources/AppCore/Notifications/MovementActivityMonitor.swift`** — re-arm the
   new pacing nudges on the same HealthKit background-delivery signal it already
   observes.
5. **`api/_lib/nudge.ts` / `api/cron/movement-nudge.ts`** — mirror any new
   server-decided nudge and its quiet-hours/cap policy, keeping the pure-policy
   split that file already establishes.
6. **Tests** — extend `Tests/AppCoreTests/MovementRemindersTests.swift` and
   `test/api/nudge.test.ts`; new tests for `NudgeBudget` and each pacing rule.

## Reused existing code

- `ReminderSettings`, `ReminderCopy`, `ReminderID`, `InactivitySchedule`,
  `MovementReminderScheduling` — `Sources/AppCore/Notifications/MovementReminders.swift`
- `MovementActivityMonitor` — `Sources/AppCore/Notifications/MovementActivityMonitor.swift`
- `shouldNudge`, `isQuietHour`, `DEFAULT_QUIET_HOURS` — `api/_lib/nudge.ts`
- `buildAps` / `sendPush` / `providerToken` — `api/_lib/apns.ts`;
  `PushRegistrationService` — `Sources/AppCore/Account/PushRegistrationService.swift`
- `CoachProfile.trainingPhase` and `RaceGoal` on `TodayState` — existing signals a
  pacing nudge can read with no new plumbing.

## Scenarios to Demonstrate

*(Provisional — the Settings surfaces are capturable; delivery is not.)*

- Reminders settings — default (today's three, mostly off).
- Reminders settings — fully customized, several nudges on, cap visible.
- Per-day schedule editor, weekday/weekend split.
- Quiet-hours editor.
- Daily-cap explainer.
- Reminders settings under large text.
