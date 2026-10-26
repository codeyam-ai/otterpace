---
title: "Stay connected and keep full history across launches"
mode: ui
createdAt: "2026-10-26T20:49:35Z"
source: manual
---

## Summary

Otterpace forgets the user's data connections every time the app is cold-launched,
and it drops history it already had. Three concrete defects, all reported by the
user ("have to reconnect apple health", "a lot of my apple health and strava
history is missing from days I didn't explicitly sign into the app"):

1. **Health "logs out" on every cold launch.** The production `OtterpaceModel.init()`
   starts from `TodayState.empty` (`healthKitConnected: false`) and sets
   `healthAuth = source.authorizationState()` — but nothing then calls
   `loadToday()`. `ContentView` only shows the dashboard when
   `model.today.healthKitConnected` is true, so a user who granted Health access
   weeks ago lands on `ConnectHero` and must tap Connect again.
2. **Strava history evaporates.** Strava activities are fetched only from the
   Settings connect / Retry import actions, kept in memory only, and then
   overwritten wholesale by the next HealthKit `connect()`/`refresh()`
   (`today = await source.loadToday()`). Strava and Health workouts are never
   merged, so a relaunch or a pull-to-refresh silently drops every Strava run.
3. **Health history is shallow.** `HealthKitDataSource.recentWorkouts` reads only
   30 days / 60 workouts, and `dailySteps` is never populated outside scenarios —
   so the heatmap's steps metric is always "no step data yet" and older days look
   missing even though HealthKit has them.

After this plan: opening the app always lands on a populated dashboard when Health
access (or a Strava connection) exists; Health and Strava workouts are merged and
de-duplicated; a cached snapshot renders instantly on launch before live reads
finish; and the history/heatmap reflect real HealthKit history.

## Key Decisions

- **Restore from evidence, not a new flag.** Auto-load on launch when
  `healthAuth == .authorized` (HealthKit has been asked) OR `StravaService.isConnected`.
  No new "logged in" boolean to drift out of sync with the real permissions.
- **Merge, don't replace.** Introduce one pure merge function (Health + Strava →
  newest-first, de-duplicated by same day + same type + start within ~10 min /
  distance within ~5%, preferring the Health record) so every load path —
  connect, refresh, Strava import, background (follow-up plan) — composes the same
  way. Pure so it unit-tests on macOS like `ActivityHistory`.
- **Cache the last good snapshot on-device** (workouts, dailySteps, weekly load,
  last-refreshed time) in the app's own defaults/file, with the same scenario
  guard `applyOnDeviceState()` uses so captures are untouched. It is a render
  cache only — live reads always win — and it never leaves the device.
- **Per-day steps from one statistics-collection query** over the history window
  rather than N day queries — one HealthKit round-trip.
- **Widen the HealthKit workout window** to match what the heatmap/history can show
  (decide the exact window at Explore by reading `ActivityHeatmap`'s range options;
  likely 90–180 days) — bounded, not "all time", to keep reads cheap.
- Out of scope: background refresh and foreground auto-refresh triggers (follow-up
  plan `battery-light-background-refresh`), Sign in with Apple (already
  long-lived via `SessionStore.revalidate`), Strava token refresh (already
  server-side in `freshAccessToken`).

## Implementation

### 1. Restore connections on cold launch

**File**: `Sources/AppCore/Model.swift`

Add a `restoreOnLaunch()` (MainActor, async) that: renders the cached snapshot
immediately (step 4), then — if `healthAuth == .authorized` — runs `loadToday()`
and, if Strava is connected, imports Strava, merging both (step 2). Call it from
`ContentView`'s `.onAppear` in production only (guard `previewMode.isEmpty` and
`!HealthSource.isScenarioSeeded`).

**File**: `Sources/AppCore/ContentView.swift`

Wire the call; the existing `healthKitConnected` gate then shows the dashboard
without a tap. Avoid a flash of `ConnectHero` while the restore is in flight
(e.g. a cached snapshot sets `healthKitConnected` synchronously, or a brief
"restoring" state).

### 2. Merge Health + Strava workouts

**New file**: `Sources/AppCore/WorkoutMerge.swift`

Pure `WorkoutMerge.merge(health:strava:)` with the de-dup rule above. Refactor
`OtterpaceModel.connect()`, `refresh()` and `ingestStravaWorkouts(_:)` to keep
the last Health and Strava lists separately and recompute `workouts`,
`latestWorkout`, `weeklyLoad` and `loadHistory` from the merge (reusing the
`ActivityHistory.weeklyLoad` / `loadHistory` rollups `ingestStravaWorkouts`
already uses).

### 3. Deeper HealthKit history + per-day steps

**File**: `Sources/AppCore/Health/HealthKitDataSource.swift`

Widen `recentWorkouts(days:limit:)` and add a daily step series via
`HKStatisticsCollectionQuery` (cumulative sum, 1-day interval) over the same
window, returned in `TodayState.dailySteps`. Update the `dailySteps` doc comment
in `Model.swift` that says HealthKit gives no per-day series.

### 4. On-device snapshot cache

**New file**: `Sources/AppCore/SnapshotCache.swift`

Save/load the last merged snapshot (+ `refreshedAt`) through the model's
`defaults`, skipped for scenario-seeded stores. Written after every successful
load; read in `restoreOnLaunch()`. Cleared on `deleteAccount()` and on Strava
disconnect (Strava portion).

### 5. Strava fetch on restore

**File**: `Sources/AppCore/Strava/StravaService.swift`

No API change expected — `fetchActivities()` already returns `[]` when not
connected. Consider raising the backend `perPage` (30 in
`fetchMappedActivities`, `api/_lib/strava.ts`) to cover the same history window;
confirm the Strava rate-limit budget at Explore before changing it.

## Reused existing code

- `OtterpaceModel.connect()` / `refresh()` / `ingestStravaWorkouts(_:)` / `applyOnDeviceState()` from `Sources/AppCore/Model.swift` (glossary entry: `OtterpaceModel`)
- `HealthKitDataSource.authorizationState()` / `loadToday()` from `Sources/AppCore/Health/HealthKitDataSource.swift` (glossary entry: `HealthKitDataSource`)
- `ActivityHistory.weeklyLoad` / `loadHistory` from `Sources/AppCore/ActivityHistory.swift` (glossary entry: `ActivityHistory`)
- `StravaService.isConnected` / `fetchActivities()` from `Sources/AppCore/Strava/StravaService.swift` (glossary entry: `StravaService`)
- `HealthSource.isScenarioSeeded` scenario guard, as used in `Model.swift`
- Tests to extend: `Tests/AppCoreTests/ModelTests.swift`, `Tests/AppCoreTests/HealthKitDataSourceTests.swift`, `Tests/AppCoreTests/ActivityHistoryTests.swift`, `Tests/AppCoreTests/StravaServiceTests.swift`

## Scenarios to Demonstrate

- Returning user, Health granted, cold launch → dashboard populated, no Connect hero
- Health + Strava both connected with overlapping runs → one merged, de-duplicated history
- Strava-only user relaunches → Strava runs still on Today and in history
- Heatmap steps metric with a real multi-week per-day step series
- First-ever launch (nothing granted) → Connect hero unchanged