---
title: "Battery-light background refresh"
mode: backend
createdAt: "2026-10-26T20:49:40Z"
source: manual
dependsOn: ["stay-connected-and-keep-full-history-across-launches"]
---

## Summary

Keep Otterpace's data fresh without the user opening the app, as lightly on the
battery as iOS allows. Today nothing refreshes on foreground (only pull-to-refresh
calls `OtterpaceModel.refresh()`), nothing refreshes Strava after the first
import, and the server-driven nudge's movement heartbeat is uploaded **only** when
the user flips Health sync on in Settings (`SettingsView.enableHealthSync`). A
stale heartbeat and a stale on-device picture are exactly what produce "get
moving" nudges on very active days. This plan adds foreground refresh, piggybacks
a refresh on the HealthKit background wakes the app already receives, and adds one
infrequent `BGAppRefreshTask` — then re-sends the heartbeat from fresh data.

User constraint, verbatim: *"be cautious about it - don't overdo it and tax phone
battery."*

## Key Decisions

- **Reuse the wake we already pay for.** `AppDelegate` already re-registers
  `MovementActivityMonitor`'s `HKObserverQuery` with `.hourly` background delivery
  at launch. Extend that wake to also refresh the cached snapshot and heartbeat,
  rather than adding a second HealthKit observer.
- **One `BGAppRefreshTask`, long interval.** Request `earliestBeginDate` ≥ 4h and
  let iOS's own budgeting decide; reschedule only after a run. No
  `BGProcessingTask`, no `fetch`-mode polling loops, no location, no audio.
- **Throttle everything.** A single `RefreshPolicy` (pure, unit-tested) answers
  "should we refresh now?" from the last refresh time: foreground ≥ 15 min,
  background ≥ 1h, Strava ≥ 3h (remote, rate-limited). Pull-to-refresh bypasses it.
- **Never run the AI coach in the background.** No coach-card regeneration, no
  spend on the user's API key while the app is closed.
- **Respect protected data.** HealthKit is unreadable while the phone is locked;
  a background read that fails or returns nothing must be treated as *unknown*
  (keep the cache, don't overwrite with zeros, don't push a heartbeat) —
  consistent with `ActivityFreshness`'s "when freshness is unknown, stay quiet".
- **Heartbeat only when opted in.** Push `SyncableHealthSnapshot` from a refresh
  only when the existing gates hold (signed in + Health sync consent), exactly as
  `AppDelegate.registerForPushIfEligible()` gates push.

## Implementation

### 1. Refresh policy

**New file**: `Sources/AppCore/RefreshPolicy.swift`

Pure throttle: `shouldRefresh(kind:lastRefreshed:now:)` for `.foreground`,
`.background`, `.strava`. Unit-tested like `ActivityFreshness`.

### 2. One refresh entry point

**File**: `Sources/AppCore/Model.swift`

`refreshIfDue(_ kind:)` that consults the policy, runs the Health load + (if due)
Strava import through the merge/cache from the prerequisite plan, and returns
whether fresh data was obtained. Unknown/empty background reads leave the cache
untouched.

### 3. Foreground refresh

**File**: `Sources/AppCore/ContentView.swift`

Call `model.refreshIfDue(.foreground)` in the existing `scenePhase == .active`
branch, before the nudge re-arm calls so they decide from fresh data.

### 4. Background refresh on existing wakes + BGAppRefreshTask

**File**: `App/App.swift`

Register a `BGAppRefreshTask` handler in `didFinishLaunchingWithOptions`
(production only, same scenario guard), schedule it on entering background, and
complete it with an expiration handler. Route the `MovementActivityMonitor`
observer wake through the same background refresh.

**File**: `App/Info.plist`

Add `fetch` to `UIBackgroundModes` and a `BGTaskSchedulerPermittedIdentifiers`
entry (e.g. `com.otterpace.app.refresh`).

### 5. Heartbeat from fresh data

**File**: `Sources/AppCore/Account/AccountSyncService.swift`

After a successful refresh, when opted in, push the same `SyncableHealthSnapshot`
shape `SettingsView.enableHealthSync` builds today. Extract that builder out of
`SettingsView.swift` so both paths share it.

## Reused existing code

- `MovementActivityMonitor` + `AppDelegate` background-launch path from `Sources/AppCore/Notifications/MovementActivityMonitor.swift` and `App/App.swift` (glossary entry: `MovementActivityMonitor`)
- `ActivityFreshness` from `Sources/AppCore/Notifications/ActivityFreshness.swift` (glossary entry: `ActivityFreshness`)
- `AccountSyncService.pushHealth` from `Sources/AppCore/Account/AccountSyncService.swift` (glossary entry: `AccountSyncService`)
- `OtterpaceModel.refresh()` / `lastMovementISO()` / `armedInactivityISO()` from `Sources/AppCore/Model.swift` (glossary entry: `OtterpaceModel`)
- Tests to extend: `Tests/AppCoreTests/ModelTests.swift`, `Tests/AppCoreTests/AccountSyncTests.swift`, `Tests/AppCoreTests/MovementRemindersTests.swift`

## Scenarios to Demonstrate

- Return to foreground after 2h → Today shows the new steps/workout without pulling
- Return to foreground after 2 min → no refresh (throttled)
- Background wake while locked → cache kept, no heartbeat pushed
- Very active day with stale heartbeat → refreshed heartbeat, no inactivity nudge