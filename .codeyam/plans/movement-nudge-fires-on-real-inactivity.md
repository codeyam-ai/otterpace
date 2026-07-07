---
title: "Movement Nudge Fires on Real Inactivity"
mode: ui
createdAt: "2026-07-07T15:43:23Z"
source: manual
---

## Summary

The "It's been a little while since you moved" reminder is wrong: it's a local
timer armed when the app **backgrounds** (`applyBackground` schedules a
`UNTimeIntervalNotificationTrigger` for N hours) and **cancelled the moment the
app reopens** (`applyForeground` removes it). So it measures "the app has been
closed for N hours," never touches HealthKit at fire time, and resets every time
the user opens or refreshes the app — firing based on app usage instead of real
movement. This plan makes the nudge fire relative to the user's **actual last
movement**: a HealthKit background-delivery observer wakes the app when new
step/distance data lands and reschedules the inactivity notification to fire
`inactivityHours` after the latest movement sample. Purely on-device, no account
required, works for guests too. (A separate opt-in, server-driven variant for
signed-in users is planned in `movement-nudge-server-push`, which depends on this.)

## Key Decisions

- **Reschedule relative to last-movement time, not "now".** The fire time becomes
  `lastMovementDate + inactivityHours`. If the user keeps moving, each new sample
  pushes the notification out; when they go still, the last-scheduled one fires
  the right number of hours after their final movement. This is the honest fix
  the existing file comment already anticipates ("true HealthKit inactivity …
  would need background processing").
- **Use HealthKit background delivery + an observer query, registered at launch.**
  `enableBackgroundDelivery(for:frequency:)` (`.hourly`, the finest iOS allows for
  cumulative types — plenty for an "it's been a while" nudge) plus a long-lived
  `HKObserverQuery` whose update handler recomputes and reschedules, then calls
  the completion handler. iOS relaunches the app in the background to run it, so
  the nudge stays correct even while the app is closed — which is exactly the
  case that's broken today.
- **Keep the pure scheduling math cross-platform and unit-tested; keep HealthKit
  glue iOS-only.** A pure function computes the fire date from
  `(lastMovement, inactivityHours, now)` — including the "already moved recently /
  fire date in the past" edge (fire soon or skip) — so it's testable in the macOS
  test build without a HealthKit entitlement, matching how the rest of
  `HealthKitDataSource` is treated as device-verified glue.
- **Foreground stops blindly cancelling.** On foreground we re-arm from the real
  last-movement time instead of removing the reminder outright, so opening the app
  no longer silently resets the "have you moved" clock. (Opening the app is not
  movement.)
- **Additive capability, off unless the user enabled the reminder.** Background
  delivery is only requested when the inactivity reminder is ON (prefs default
  OFF), so scenarios/previews still schedule nothing and prompt nothing.

## Implementation

### 1. Add a last-movement read to the health source

**File**: `Sources/AppCore/Health/HealthDataSource.swift`

Add `func lastMovementDate() async -> Date?` to the `HealthDataSource` protocol.
Implement it on `SeededHealthDataSource` by returning a value derived from the
seeded state (e.g. a new `rbLastMovementMinutesAgo` / reuse
`rbMinutesSinceMovement` → `now - minutes`, or the newest seeded workout date) so
scenarios can drive the nudge deterministically.

**File**: `Sources/AppCore/Health/HealthKitDataSource.swift`

Implement `lastMovementDate()` with a `HKSampleQuery` (or `HKStatisticsQuery`)
for the most recent `.stepCount` / `.distanceWalkingRunning` sample (limit 1,
sorted by end date descending), returning its end date. Reuses the same
`readTypes` already authorized. Add the `.unavailable`/stub implementation to the
non-iOS `HealthKitDataSource` stub so the package still compiles.

### 2. Schedule the inactivity nudge at an absolute fire date

**File**: `Sources/AppCore/Notifications/MovementReminders.swift`

- Add a pure helper (cross-platform, e.g. `InactivitySchedule.fireDate(lastMovement:hours:now:)`)
  that returns the `Date` the nudge should fire, or `nil` when the user has moved
  so recently that it should simply be deferred, plus the clamp for a
  past-due date (fire almost immediately vs. skip). Keep it free of UN/HealthKit
  types so `AppCore` tests cover it.
- Extend `MovementReminderScheduling` with an absolute-time arm, e.g.
  `armInactivity(fireAt: Date?, settings: ReminderSettings)`, and change the iOS
  `MovementReminderScheduler` to schedule the inactivity id with a
  `UNCalendarNotificationTrigger` (or a `UNTimeIntervalNotificationTrigger` of
  `fireAt - now`) instead of the fixed "N hours from background." A `nil` fireAt
  removes any pending inactivity request.
- Update `applyBackground` / `applyForeground` so the inactivity reminder is
  (re)armed from the computed fire date rather than a fixed interval, and
  foreground no longer just deletes it.

### 3. Observe real movement in the background

**New file**: `Sources/AppCore/Notifications/MovementActivityMonitor.swift`

An iOS-only coordinator that, when the inactivity reminder is enabled and
notifications are authorized:
- calls `store.enableBackgroundDelivery(for: .stepCount / .distanceWalkingRunning, frequency: .hourly)`,
- runs a long-lived `HKObserverQuery` whose update handler reads
  `lastMovementDate()`, recomputes the fire date via the pure helper, calls
  `armInactivity(fireAt:settings:)`, then invokes the observer completion handler,
- disables background delivery + tears down the query when the reminder is turned
  off. Provide a no-op stub on non-iOS so `AppCore` compiles/tests.

### 4. Register the monitor at launch and on lifecycle changes

**File**: `App/App.swift`

Add an `@UIApplicationDelegateAdaptor` app delegate that, on
`didFinishLaunchingWithOptions`, starts the `MovementActivityMonitor` when the
inactivity reminder is enabled (so background deliveries wake the app even from
cold launch). Keep the isolation-host branch untouched.

**File**: `Sources/AppCore/ContentView.swift`

In the existing `scenePhase` handler (currently calling
`applyForeground`/`applyBackground` at ContentView.swift:130/132), route through
the new last-movement-based arming so foreground re-arms from real movement
instead of cancelling.

**File**: `Sources/AppCore/SettingsView.swift`

Where enabling the inactivity toggle currently calls `applyForeground`
(SettingsView.swift:589–593), also start/stop the `MovementActivityMonitor` and
request HealthKit background delivery so turning the reminder on begins real
observation.

### 5. Capability + usage strings

**File**: `App/App.entitlements`

Add `com.apple.developer.healthkit.background-delivery` so background delivery is
permitted on a signed device build. (Call this out for the TestFlight signing
checklist in `docs/testflight-prep.md`.)

**File**: `App/Info.plist`

Confirm/keep `NSHealthShareUsageDescription`; no new key strictly required for
reads, but note the background-delivery capability in the prep doc.

### 6. Tests

**File**: `Tests/AppCoreTests/MovementRemindersTests.swift` (extend or add)

- Pure `fireDate` helper: last movement 2h ago with a 3h setting → fires ~1h from
  now; last movement just now → deferred/pushed out ~3h; last movement 5h ago
  with a 3h setting → past-due clamp fires promptly.
- The seeded source's `lastMovementDate()` reflects the seeded state.
- Foreground re-arm computes from last movement rather than removing the reminder.

## Reused existing code

- `ReminderSettings` / `ReminderID` / `ReminderCopy` and the
  `MovementReminderScheduling` protocol (`Sources/AppCore/Notifications/MovementReminders.swift`)
  — extend, don't replace (glossary: `ReminderSettings`, `MovementReminderScheduler`).
- `HealthDataSource` / `SeededHealthDataSource` / `HealthKitDataSource`
  (`Sources/AppCore/Health/*.swift`) — add `lastMovementDate()` alongside the
  existing `loadToday()` glue.
- The `scenePhase` reminder wiring in `ContentView` (ContentView.swift:124–135)
  and the Settings toggle path (SettingsView.swift:589–593) — reuse the existing
  hooks rather than adding new lifecycle plumbing.
- `minutesSinceLastMovement` on `TodayState` (`Sources/AppCore/Model.swift:72`)
  as the seeded scenario signal for last-movement time.

## Scenarios to Demonstrate

- Moved 10 minutes ago, 3h setting — no nudge is imminent (clock reads from
  movement, not from opening the app).
- Last movement ~3h ago — the nudge is due, demonstrating it fires on real
  inactivity.
- Open/refresh the app after sitting still for 2h — reopening does NOT reset the
  clock (regression guard for the reported bug).
- Inactivity reminder OFF (default) — nothing scheduled, no background delivery,
  no permission prompt (scenario/preview safety).
- Guest user (no account) — the nudge still works, proving no login is required.
