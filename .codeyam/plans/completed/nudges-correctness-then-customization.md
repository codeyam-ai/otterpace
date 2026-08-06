---
title: "Nudges — Correctness First, Then Customization"
mode: ui
createdAt: "2026-07-30T19:09:00Z"
source: manual
order: 7
dependsOn: ["quiet-hours-timezone-fix"]
---

## Scope resolved for this build (2026-08-05)

The fleshing-out pass this draft asked for. **This cycle builds Phase 1 only.**
Phase 2 stays queued as written below.

1. **Scope — Phase 1 (correctness) only.** Confirmed with the user. Phase 2's
   customization and pacing families are explicitly NOT in this build.
2. **Goal nudge — extend the existing HealthKit observer.** Confirmed with the
   user. `MovementActivityMonitor` already runs an `HKObserverQuery` with hourly
   background delivery for step/distance and re-arms on new data; generalize it to
   re-evaluate the goal nudge and cancel it once the goal is met. **No
   `BGAppRefreshTask`** — it needs new `BGTaskSchedulerPermittedIdentifiers` and
   `App.swift` registration and still guarantees no cadence. Consequence to
   handle: the monitor today only starts when `inactivityEnabled` (see
   `MovementActivityMonitor.start`), so it must start when **goal OR inactivity**
   is on.
3. **Server staleness — max-age guard only.** *Assumption, not user-confirmed.*
   A staleness guard in the pure `shouldNudge` policy: when `lastMovementAt` is
   older than the max age, suppress rather than guess. Deliberately NOT pushing a
   health heartbeat on background wake — that uploads a health snapshot with the
   user outside the app and needs a `SyncConsent` copy review first. Accepted
   tradeoff: for a user who rarely opens the app the server nudge goes quiet,
   which is this plan's own "suppression is the safer default".
4. **Local/server de-dup — included, bounded.** *Assumption, not user-confirmed.*
   Cheapest honest fix: the health heartbeat carries the locally-armed inactivity
   fire time, so the server's existing `lastNudgeSentAt` de-dup covers both paths.
   **This is the first item to cut** if it needs more plumbing than that; the
   Phase 2 `NudgeBudget` arbiter is its natural long-term home.

Open questions deliberately left unresolved (all Phase 2 or out of scope): pacing
nudge selection, per-day-of-week schedules, user-editable quiet hours, goal-nudge
timing, `CoachProfile.trainingPhase` steering, and the widget / Live Activity
question (its own plan).

## Summary

**Draft — needs a fleshing-out pass before running.** This merges two earlier
drafts, `activity-freshness-and-smarter-nudge-suppression` and
`custom-movement-and-pacing-nudges`, which were separate plans that touched
**five of the same files** — `MovementReminders.swift`,
`MovementActivityMonitor.swift`, `api/_lib/nudge.ts`,
`api/cron/movement-nudge.ts`, and the Settings reminders card — and both extended
`MovementRemindersTests.swift`. Run separately, the second would have rewritten
the first's work on the same structs.

They are merged rather than resequenced because they are two phases of one
problem, and the ordering between them is not optional:

- **Phase 1 — correctness.** Stop sending nudges that are wrong. The app's
  picture of your activity must refresh without you opening it, and every nudge
  must re-verify against fresh data at fire time instead of trusting a decision
  made hours earlier.
- **Phase 2 — customization.** Let people choose their times, schedules, quiet
  hours, tone, and how many nudges a day is too many, and add pacing nudges that
  speak to training rather than step count.

Phase 2 makes Otterpace send *more* notifications. Landing more nudges on top of a
false-positive problem multiplies the annoyance and is how an app gets its
notifications turned off permanently. Phase 1 is a hard precondition for Phase 2,
not a preference.

The timezone bug that used to head the correctness list has been **extracted into
its own build-ready plan** (`quiet-hours-timezone-fix`, declared in `dependsOn`)
because it was small, self-contained, and did not need any of the open questions
below resolved. Do not re-implement it here.

## Phase 1 — Correctness

Two false-positive paths remain in the code, and the file comments in each admit
the limitation:

1. **The goal nudge can't see your steps.** It's a pre-scheduled 7pm calendar
   notification — `UNCalendarNotificationTrigger` can't read live HealthKit data
   at fire time, so it fires whether you're at 3,000 steps or 14,000. The copy
   hedges around it ("Already done? Nice, consider this a wave from Buddy"),
   which is the tell.
2. **The server nudge runs on a possibly-stale heartbeat.**
   `api/cron/movement-nudge.ts` decides from `lastMovementAt` in the account
   health row. That row only updates when health sync is on *and* the app pushes
   it — so for a user who moved all afternoon without opening the app, the server
   still believes they've been still since morning, and sends "Stretch your legs?"
   to someone mid-walk.

The local inactivity nudge is already the good pattern — `MovementActivityMonitor`
observes real HealthKit step/distance data via background delivery and re-arms
`InactivitySchedule` from actual last-movement time. Phase 1 generalizes it.

### Key decisions (provisional)

- **Verify at fire time, don't just schedule better.** The durable fix for the
  goal nudge is not a smarter 7pm; it's not being a fixed 7pm calendar trigger at
  all. Options to evaluate: a `BGAppRefreshTask` that checks progress and either
  cancels or re-arms the pending request; or converting it to the
  `MovementActivityMonitor` pattern (observer wakes the app, app decides, app
  schedules a near-term trigger only if the nudge is still true).
- **One freshness contract, used everywhere.** A single pure `ActivityFreshness`
  type answering "how old is this data, and is it fresh enough to act on?" —
  consumed by the local scheduler, the health-sync push, and (as a
  `lastMovementAt` age check) the server policy. Every nudge asks it first. Stale
  data should mean **suppress**, never guess.
- **Suppression is the safer default in both directions.** A nudge that doesn't
  fire is a missed encouragement; a nudge that fires wrongly teaches the user the
  app is dumb. When freshness is unknown, stay quiet. (Note the deliberate
  contrast with the timezone plan's UTC fallback: an unknown *timezone* is a
  rollout gap where suppressing would silently disable the feature; unknown
  *freshness* is a real signal that we don't know enough to speak.)
- **Keep the pure-policy split.** `api/_lib/nudge.ts` deliberately holds the
  decision logic free of Supabase/APNs so it unit-tests directly. Every new rule
  goes there, not in the cron handler.
- **Don't ask for more permissions than needed.** HealthKit background delivery
  is already enabled for step/distance when the inactivity reminder is on.
  Whether to widen that (and to broaden `BGTaskSchedulerPermittedIdentifiers`) is
  a real cost/benefit call, not automatic.

### Open questions

- **`BGAppRefreshTask` vs. widening HealthKit background delivery vs. both.** iOS
  gives no guaranteed cadence for either; the design has to be correct when
  neither fires for hours. What does the app do on a 6-hour gap?
- **How fresh is "fresh enough"?** Probably different per nudge — a goal nudge
  needs today's steps within ~30 minutes; an inactivity nudge tolerates more.
- **Should the health heartbeat push on background wake?** That would fix the
  server's stale-`lastMovementAt` problem directly — but it means uploading a
  health snapshot without the user in the app, which needs a careful look at the
  existing health-sync consent copy (`Sources/AppCore/Account/SyncConsent.swift`)
  before it's acceptable.
- **Should local and server nudges de-duplicate against each other?** A user with
  both paths active can currently receive two "stretch your legs" nudges.
- **Widget or Live Activity?** A widget would let people see progress without
  opening the app at all — arguably the truest read of "a better way to update vs.
  manually checking." Probably its own plan rather than part of this one.

### Implementation sketch

1. **New** `Sources/AppCore/Notifications/ActivityFreshness.swift` — the pure
   freshness contract (age of last known movement, per-nudge thresholds,
   `shouldSuppress`), XCTest-covered in the `InactivitySchedule` style.
2. **`MovementActivityMonitor.swift`** — extend the observer to re-evaluate *all*
   pending reminders on new data, not just the inactivity one; cancel any request
   whose premise no longer holds.
3. **`MovementReminders.swift`** — convert the goal nudge off a fixed calendar
   trigger to a verified-then-armed request; add the cancel path.
4. **New** background refresh registration (`App/App.swift` +
   `MovementActivityMonitor`) if `BGAppRefreshTask` is chosen — with the no-op
   stub for non-iOS that `AppCore` already uses for platform glue.
5. **`api/_lib/nudge.ts`** — a max-age guard on `lastMovementAt`. (The timezone
   parameter already exists by this point, from the prerequisite plan.)
6. **`api/cron/movement-nudge.ts`** — skip candidates whose heartbeat is too old
   rather than nudging on stale state.
7. **Tests** — `MovementRemindersTests.swift`, a new `ActivityFreshnessTests.swift`,
   and `test/api/nudge.test.ts` for the staleness rules.

## Phase 2 — Customization and pacing

Today Otterpace ships three fixed reminders (`daily` at a time you pick, `goal`
hard-coded to `ReminderSettings.goalHour = 19`, `inactivity` after 2/3/4 hours)
with fixed copy, one schedule, and no awareness of *how* you run. Phase 2 opens
that up in two directions: **customization** — user-chosen times, per-day-of-week
schedules, quiet hours, tone, and a daily cap — and **pacing** — nudges that speak
to your training ("that was a hard one, tomorrow's an easy day", "you're 2k from
your goal with an hour of daylight left", "third day on — how about a rest day").

### Key decisions (provisional)

- **Extend `ReminderSettings`, don't replace it.** The existing struct already has
  the UserDefaults-backed, injectable, unit-tested shape. New fields default to
  today's behavior so an existing user's reminders don't change under them on
  update — the same additive-with-defaults discipline `TodayState` uses.
- **Keep every scheduling *decision* pure.** `InactivitySchedule.fireDate` is the
  model: platform glue stays thin, the decision is an XCTest-covered pure
  function. Every new nudge type gets the same treatment.
- **A hard daily cap, set by the user.** More nudge types must not mean more
  nudges by default. A per-day ceiling (default low, e.g. 2) with a priority order
  deciding which nudge wins is a first-class part of the design, not a follow-up.
- **Every new nudge passes the freshness check from Phase 1.** This is the
  structural reason the phases are ordered — a pacing nudge fired on stale data is
  a worse false positive than the ones Phase 1 just fixed, because it makes a
  specific claim about your training.
- **Copy stays in `ReminderCopy`, in Buddy's voice.** Never-shame, never a streak
  threat. Tone variants (quieter / warmer / more direct) are a user setting, not a
  reason to loosen the voice rules.
- **Local-first.** Prefer `UNUserNotificationCenter` scheduling on-device; reach
  for the server/APNs path only for nudges that genuinely can't be decided
  locally.

### Open questions

- **Which pacing nudges earn a notification?** Candidates: post-run recovery
  ("yesterday was hard — easy today"), goal-proximity ("2,100 steps to go"),
  streak-adjacent-but-not-shaming ("day three — a rest day is training too"), race
  taper (`RaceGoal` data is already on `TodayState`), and weekly-review ready.
  Each needs a "would a real user thank us for this at 6pm?" test.
- **Per-day-of-week schedules** — genuinely useful (weekends differ) but it
  multiplies the settings UI. Worth it, or is one schedule + quiet hours enough?
- **User-editable quiet hours.** The window is now correct per-timezone, but still
  fixed at 21→8 and server-side only. Should the local scheduler honor it too, and
  should the user be able to move it?
- **Goal nudge timing.** Make it user-set, or adaptive to when the user typically
  closes their goal (which needs `dailySteps` on `TodayState`)? Note Phase 1 may
  already have converted this nudge off a fixed trigger entirely, which changes
  the answer.
- **Does `CoachProfile.trainingPhase` steer nudges?** It already steers the coach;
  reusing it would keep a "recovering" user from being nudged to move more, at no
  new data cost.
- **How much is capturable?** Notification delivery isn't scenario-capturable; the
  Settings UI and any in-app nudge surfaces are.

### Implementation sketch

1. **`MovementReminders.swift`** — extend `ReminderSettings` (per-nudge times, day
   mask, quiet-hours window, daily cap, tone); extend `ReminderCopy` with the new
   nudge families; add pure `PacingSchedule` decision functions alongside
   `InactivitySchedule`.
2. **New** `Sources/AppCore/Notifications/NudgeBudget.swift` — the pure priority +
   daily-cap arbiter every nudge passes through before scheduling.
3. **`Sources/AppCore/SettingsView.swift`** — rework the reminders card into a
   fuller schedule editor (likely its own sub-screen once per-day schedules land).
4. **`MovementActivityMonitor.swift`** — re-arm the new pacing nudges on the same
   HealthKit background-delivery signal it already observes.
5. **`api/_lib/nudge.ts` / `api/cron/movement-nudge.ts`** — mirror any new
   server-decided nudge and its cap policy, keeping the pure-policy split.
6. **Tests** — extend `MovementRemindersTests.swift` and `test/api/nudge.test.ts`;
   new tests for `NudgeBudget` and each pacing rule.

## Reused existing code

- `ReminderSettings`, `ReminderCopy`, `ReminderID`, `InactivitySchedule`,
  `MovementReminderScheduling` —
  `Sources/AppCore/Notifications/MovementReminders.swift`.
- `MovementActivityMonitor` —
  `Sources/AppCore/Notifications/MovementActivityMonitor.swift` — the existing
  HealthKit observer + background-delivery pattern Phase 1 generalizes.
- `shouldNudge`, `isQuietHour`, `DEFAULT_QUIET_HOURS`, `NudgeState`, and
  `localHourIn` (added by the prerequisite plan) — `api/_lib/nudge.ts`, extended
  in place, kept pure.
- `listNudgeCandidates` / `stampNudgeSent` / `mirrorMovement` — `api/_lib/account.ts`.
- `buildAps` / `sendPush` / `providerToken` — `api/_lib/apns.ts`;
  `PushRegistrationService` — `Sources/AppCore/Account/PushRegistrationService.swift`.
- `HealthDataSource` / `HealthKitDataSource` —
  `Sources/AppCore/Health/HealthDataSource.swift` — the read seam, with its seeded
  mock keeping any new logic testable offline.
- `AccountSyncService` health heartbeat —
  `Sources/AppCore/Account/AccountSyncService.swift`.
- `CoachProfile.trainingPhase` and `RaceGoal` on `TodayState` — existing signals a
  pacing nudge can read with no new plumbing.

## Scenarios to Demonstrate

*(Provisional — pure logic and Settings surfaces are capturable; delivery is not.)*

**Phase 1**
- Settings — reminders with a data-freshness indicator showing fresh data.
- Settings — the same row showing stale data and what the app does about it.
- Suppression explainer copy ("we won't nudge you when we can't tell").
- Unit: goal nudge suppressed at 11,240 steps; goal nudge sent at 3,100.
- Unit: server nudge skipped on a 9-hour-old heartbeat.

**Phase 2**
- Reminders settings — default (today's three, mostly off) — the no-regression
  guard for an existing user.
- Reminders settings — fully customized, several nudges on, cap visible.
- Per-day schedule editor, weekday/weekend split.
- Quiet-hours editor.
- Daily-cap explainer.
- Reminders settings under large text.
