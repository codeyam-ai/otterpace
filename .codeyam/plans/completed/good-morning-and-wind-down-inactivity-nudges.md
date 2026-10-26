---
title: "Good-morning and wind-down inactivity nudges"
mode: ui
createdAt: "2026-10-26T16:55:44Z"
source: manual
---

## Summary

The inactivity nudge ("Stretch your legs? It's been a little while since you moved.") counts sleep as stillness, so it tends to land first thing in the morning and again late in the evening. Both are times when "you haven't been moving" is the wrong thing to say. There are two causes. (1) The server cron (`api/cron/movement-nudge.ts`) holds the push during 9pm–8am quiet hours, so the first scan after 8am sees a 10+ hour "idle spell" and sends the push immediately. (2) The on-device nudge (`InactivitySchedule.fireDate`) has **no quiet hours at all**. An overnight spell is past due, so the nudge fires `pastDueBuffer` (60s) after the next HealthKit wake or app foreground, even at 6–7am. That can also mean a 1am fire. The fix: make the inactivity nudge aware of the time of day. In the morning window it becomes a warm "good morning" note. In the evening window it becomes a "winding down" note. Neither mentions how long you've been still. The device also gets the same overnight quiet window the server already has, and overnight fires are pushed to the morning. The 7pm step-goal nudge and the user-timed daily reminder are **out of scope** (the user confirmed that only the inactivity nudge bothers them).

## Key Decisions

- **Change the copy, don't suppress the nudge.** The user asked for good-morning and wind-down notifications, not silence. The nudge still fires under the same rules (idle past threshold, once per idle spell, fresh heartbeat). Only the words change by time of day.
- **Pick the copy from the local hour the nudge fires at**, not from how long the user has been idle. Device: the hour of `fireAt`. Server: the per-user `localHourIn(user.time_zone, now)` the cron already computes. Proposed windows: morning = quiet-end (8) up to 11am; evening = 7pm up to quiet-start (9pm); daytime = everything else (current copy unchanged). Keep these as named constants on both sides so they mirror each other the way `inactivityMaxAge` / `MAX_HEARTBEAT_AGE_MS` already do.
- **The device gets quiet hours that mirror `DEFAULT_QUIET_HOURS` (21→8).** If `InactivitySchedule.fireDate` lands inside the window, including the past-due clamp, it moves to the next 8:00 local. This removes the 1am fires and the "60s after I picked up my phone at 6:45" fires. Every overnight spell then resolves to a morning-window fire, so it gets the morning copy. The HealthKit observer already re-arms on new movement. So if the user walks at 7:30, the deferred 8am nudge is replaced by a normal daytime one.
- **Server and device copy stay identical.** Server and device already share copy so the two paths read the same and the local/server de-dup (`localNudgeArmedAt`) keeps hiding which path delivered. Define the three title/body pairs once per side and add a test on each side that pins the exact strings.
- **No new settings.** No UI to configure the windows. That can come later if wanted.

## Implementation

### 1. Device: time-of-day inactivity copy

**File**: `Sources/AppCore/Notifications/MovementReminders.swift`

In `ReminderCopy`, keep `inactivityTitle` / `inactivityBody` as the daytime pair. Add morning and evening pairs, plus a pure selector, e.g. `ReminderCopy.inactivity(at: Date, calendar:) -> (title: String, body: String)`, that buckets by local hour. Proposed copy (tweak in review, but keep Buddy's never-shame voice and say nothing about elapsed time):
- Morning: "Good morning ☀️" / "Buddy's up and stretching. Whenever you're ready, an easy start to the day is plenty."
- Evening: "Winding down 🌙" / "Hope today was a good one. A gentle stretch before bed is a nice way to close it out, or just rest."

Add the window constants (morning end 11, evening start 19, quiet 21→8) next to `ReminderSettings.goalHour` or in a small `NudgeDaypart` enum. Keep them free of UserNotifications types so they unit-test in the macOS build.

### 2. Device: quiet-hours deferral in `InactivitySchedule.fireDate`

**File**: `Sources/AppCore/Notifications/MovementReminders.swift`

After computing the candidate (or the `now + pastDueBuffer` clamp), check whether it falls in the 21→8 local window. If so, return the next 8:00 local (same day if before 8, next day if after 21). Add a `calendar: Calendar = .current` parameter, like `GoalNudgeSchedule.fireDate`, so tests can pin it. Callers (`OtterpaceModel.rearmInactivity` in `Sources/AppCore/Model.swift`, `MovementActivityMonitor.rearm` in `Sources/AppCore/Notifications/MovementActivityMonitor.swift`) need no signature change. `armedInactivityFireAt` automatically reports the deferred time to the server through the heartbeat.

### 3. Device: scheduler uses the daypart copy

**File**: `Sources/AppCore/Notifications/MovementReminders.swift`

In `MovementReminderScheduler.armInactivity`, replace the fixed `ReminderCopy.inactivityTitle/Body` with `ReminderCopy.inactivity(at: fireAt)`.

### 4. Server: per-user daypart copy

**File**: `api/_lib/nudge.ts`

Add `MORNING_END_HOUR` / `EVENING_START_HOUR` constants and a pure `nudgeCopyFor(localHour, quiet = DEFAULT_QUIET_HOURS): { title, body }` that returns the same three pairs as `ReminderCopy`. Move `NUDGE_TITLE`/`NUDGE_BODY` here as the daytime pair.

**File**: `api/cron/movement-nudge.ts`

`buildAps(NUDGE_TITLE, NUDGE_BODY)` is currently built once before the loop. Build it per user inside the loop from `nudgeCopyFor(localHour)`, after `shouldNudge` returns true. Update the header comment so it describes the time-of-day copy.

### 5. Tests

**File**: `Tests/AppCoreTests/MovementRemindersTests.swift`. Add: fireDate at 23:30 (or past-due at 06:45) moves to 08:00 that morning or the next; a daytime candidate is unchanged; `ReminderCopy.inactivity(at:)` returns morning at 8:00/10:59, daytime at 11:00/18:59, and evening at 19:00/20:59; the morning and evening bodies don't contain "while since you moved".

**File**: `test/api/nudge.test.ts`. Add `nudgeCopyFor` bucket tests and a parity test that pins the strings to the Swift copy.

**File**: `test/api/cron-handler.test.ts`. Add: a user whose local hour is 8 gets `buildAps` called with the morning title, while a user in another zone in the same scan gets the daytime title. This proves the copy is chosen per user, not once per scan.

## Reused existing code

- `localHourIn`, `isQuietHour`, `DEFAULT_QUIET_HOURS`, `shouldNudge` from `api/_lib/nudge.ts` (glossary entries: `isQuietHour`, `shouldNudge`)
- `todayAt` (on `GoalNudgeSchedule`) from `Sources/AppCore/Notifications/MovementReminders.swift` (glossary entry: `GoalNudgeSchedule`). Reuse it for "next 8:00 local" in the deferral math.
- `InactivitySchedule` and `ReminderCopy` from `Sources/AppCore/Notifications/MovementReminders.swift`
- `buildAps` from `api/_lib/apns.ts`
- Existing test harnesses: `Tests/AppCoreTests/MovementRemindersTests.swift` (XCTest; the `SpyScheduler` fake already captures `armCalls`), `test/api/nudge.test.ts` and `test/api/cron-handler.test.ts` (vitest via `npm test`, with `buildAps` already mocked so its call arguments can be asserted)

## Scenarios to Demonstrate

Notifications aren't rendered in-app, so the scenario value is low. The behavior is proven by the unit tests above. If a scenario is wanted, the Settings → Reminders card (`settings-health-sync-on`) can show a short caption under "Inactivity nudge": "Says good morning / good night instead of nudging overnight". This is optional and should only be added if the copy is approved.

- Morning: idle since 9:30pm, phone picked up 6:45am → nudge armed for 8:00 with "Good morning ☀️"
- Morning, already walking: user moves at 7:30 → deferred nudge replaced with a daytime one at 10:30
- Midday: idle 3h at 2pm → unchanged "Stretch your legs?"
- Evening: idle 3h, fires 8:15pm → "Winding down 🌙"
- Late: would fire 11pm → pushed to 8:00 next morning (morning copy)
- Server: two users in different zones in one scan → each gets their own daypart copy