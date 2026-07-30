---
title: "Activity Freshness — Stop Nudging People Who Already Moved"
mode: ui
createdAt: "2026-07-30T18:27:30Z"
source: manual
---

## Summary

**Draft — to be fleshed out before running.** Otterpace currently sends nudges
that are wrong when the user moved but didn't open the app. The fix is to make
the app's picture of your activity refresh **without you checking in**, and to
make every nudge re-verify against fresh data at fire time instead of trusting a
decision made hours earlier. Three concrete false-positive paths already exist in
the code, and the file comments in each one admit the limitation:

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
3. **Quiet hours are computed in UTC.** `api/cron/movement-nudge.ts` uses
   `now.getUTCHours()` with a `// per-user timezone is a future refinement` note.
   For a US user that shifts the 21:00–08:00 quiet window by 5–8 hours — the
   overnight guard protects the wrong hours. **This one is a plain bug and is
   probably the cheapest, highest-impact fix in the plan.**

The local inactivity nudge is already the good pattern — `MovementActivityMonitor`
observes real HealthKit step/distance data via background delivery and re-arms
`InactivitySchedule` from actual last-movement time. This plan generalizes that
approach to everything else.

## Key Decisions

*(Provisional — revisit when fleshing out.)*

- **Verify at fire time, don't just schedule better.** The durable fix for the
  goal nudge is not a smarter 7pm; it's not being a fixed 7pm calendar trigger at
  all. Options to evaluate: a `BGAppRefreshTask` that checks progress and either
  cancels or re-arms the pending request; or converting it to the
  `MovementActivityMonitor` pattern (observer wakes the app, app decides, app
  schedules a near-term trigger only if the nudge is still true).
- **One freshness contract, used everywhere.** A single pure
  `ActivityFreshness` type answering "how old is this data, and is it fresh
  enough to act on?" — consumed by the local scheduler, the health-sync push, and
  (as a `lastMovementAt` age check) the server policy. Every nudge asks it first.
  Stale data should mean **suppress**, never guess.
- **Suppression is the safer default in both directions.** A nudge that doesn't
  fire is a missed encouragement; a nudge that fires wrongly teaches the user the
  app is dumb and gets notifications turned off permanently. When freshness is
  unknown, stay quiet.
- **Fix quiet-hours timezone before anything else.** Store a per-user UTC offset
  (or IANA zone) on the account row and use it in `shouldNudge`. It's a small,
  self-contained change to already-pure, already-tested code.
- **Keep the pure-policy split.** `api/_lib/nudge.ts` deliberately holds the
  decision logic free of Supabase/APNs so it unit-tests directly. Every new rule
  goes there, not in the cron handler.
- **Don't ask for more permissions than needed.** HealthKit background delivery
  is already enabled for step/distance when the inactivity reminder is on.
  Whether to widen that (and to broaden `BGTaskSchedulerPermittedIdentifiers`) is
  a real cost/benefit call, not automatic.

## Open Questions

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
- **Timezone storage.** Add a column to the account row, or derive from the
  device on each heartbeat? DST makes an IANA zone safer than a fixed offset.
- **Should local and server nudges de-duplicate against each other?** A user with
  both paths active can currently receive two "stretch your legs" nudges.
- **Widget or Live Activity?** A widget would let people see progress without
  opening the app at all — arguably the truest read of "a better way to update
  vs. manually checking." Possibly its own plan.
- **How is any of this verifiable in the codeyam loop?** Background wakes and
  push aren't scenario-capturable; the pure freshness/policy functions and the
  Settings surfaces are. Expect a device-verification checklist to sit alongside
  the tests.

## Implementation

*(Sketch only — expand during the fleshing-out pass.)*

1. **New** `Sources/AppCore/Notifications/ActivityFreshness.swift` — the pure
   freshness contract (age of last known movement, per-nudge thresholds,
   `shouldSuppress`), XCTest-covered in the `InactivitySchedule` style.
2. **`Sources/AppCore/Notifications/MovementActivityMonitor.swift`** — extend the
   observer to re-evaluate *all* pending reminders on new data, not just the
   inactivity one; cancel any request whose premise no longer holds.
3. **`Sources/AppCore/Notifications/MovementReminders.swift`** — convert the goal
   nudge off a fixed calendar trigger to a verified-then-armed request; add the
   cancel path.
4. **New** background refresh registration (App/`App.swift` +
   `MovementActivityMonitor`) if `BGAppRefreshTask` is chosen — with the no-op
   stub for non-iOS that `AppCore` already uses for platform glue.
5. **`api/_lib/nudge.ts`** — a per-user timezone in `shouldNudge` (replacing the
   UTC assumption) plus a max-age guard on `lastMovementAt`.
6. **`api/cron/movement-nudge.ts`** — pass the stored timezone through; skip
   candidates whose heartbeat is too old rather than nudging on stale state.
7. **`api/_lib/account.ts`** — persist the timezone alongside the health
   heartbeat; extend `listNudgeCandidates` to return it.
8. **Tests** — `Tests/AppCoreTests/MovementRemindersTests.swift` and a new
   `ActivityFreshnessTests.swift`; `test/api/nudge.test.ts` for the timezone and
   staleness rules (including a DST boundary case).

## Reused existing code

- `MovementActivityMonitor` — `Sources/AppCore/Notifications/MovementActivityMonitor.swift`
  — the existing HealthKit observer + background-delivery pattern this plan
  generalizes.
- `InactivitySchedule.fireDate` and `MovementReminderScheduling` —
  `Sources/AppCore/Notifications/MovementReminders.swift` — the pure-decision /
  thin-glue split every new rule follows.
- `shouldNudge`, `isQuietHour`, `DEFAULT_QUIET_HOURS`, `NudgeState` —
  `api/_lib/nudge.ts` — extended in place, keeping them pure.
- `listNudgeCandidates` / `stampNudgeSent` — `api/_lib/account.ts`.
- `HealthDataSource` / `HealthKitDataSource` —
  `Sources/AppCore/Health/HealthDataSource.swift` — the read seam, with its
  seeded mock keeping any new logic testable offline.
- `AccountSyncService` health heartbeat — `Sources/AppCore/Account/AccountSyncService.swift`
  — what would need to fire on background wake if that route is taken.

## Scenarios to Demonstrate

*(Provisional — pure logic and Settings surfaces are capturable; delivery is not.)*

- Settings — reminders with a "last updated / data freshness" indicator showing
  fresh data.
- Settings — the same row showing stale data and what the app does about it.
- Today — a fresh-data state versus a stale one, if freshness surfaces in the UI.
- Suppression explainer copy ("we won't nudge you when we can't tell").
- Unit-level (not captures): goal nudge suppressed at 11,240 steps; goal nudge
  sent at 3,100; server nudge skipped on a 9-hour-old heartbeat; quiet hours
  correct for a UTC−5 user across a DST boundary.
