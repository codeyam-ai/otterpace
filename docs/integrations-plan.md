# Otterpace — Real Integrations (HealthKit + Sign in with Apple)

How we move from **mock/seeded data** to **real** step tracking, plus optional
Sign in with Apple.

> **Status — code built (Aug pass):** the data-source seam, `HealthKitDataSource`,
> `SessionStore` + `SignInView` (with "Continue without an account"), the denied
> state, and the entitlements file + `NSHealthShareUsageDescription` are all in the
> repo, unit-tested (80 tests), with previews intact. **Not yet verified live** —
> that needs the two capabilities enabled in Xcode + a signed device build (you):
>
> 1. In Xcode → App target → **Signing & Capabilities**, add **HealthKit** and
>    **Sign in with Apple** (this wires `App/App.entitlements` and registers the
>    App ID capabilities under your team).
> 2. Run on a device (or add Health samples in the simulator) and confirm: the
>    permission sheet appears, real steps load, denial shows the "Health access is
>    off" screen, and Sign in with Apple completes (or you continue as guest).

## The key distinction (read first)

**HealthKit and Sign in with Apple are unrelated.**

- **HealthKit** = the app asks *iOS* for permission to read your on-device health
  data (steps, distance, active energy). It is **not** an account and needs **no
  login**. Data stays on the device. This is the actual "step tracking."
- **Sign in with Apple** = identity/login. It returns a user identifier (and an
  email, once). It provides **no fitness data**. It's only useful for a persistent
  account, cross-device sync, or a backend.

→ The real step-tracking experience is **HealthKit alone, no sign-in**. Sign in
with Apple is an optional layer, recommended to defer for the MVP (your spec says
"no account required").

## Verification boundary (important)

Neither integration can be fully verified in the CodeYam simulator/preview loop —
both need **entitlements + a signed build**:

- What I can do here: write the code, add entitlements + Info.plist usage strings,
  unit-test the pure logic, and keep every CodeYam scenario rendering via the
  existing seeded mock data.
- What needs your Xcode + Apple Developer account: enable the two capabilities,
  sign with your team, and run on a device (or a simulator with Health samples /
  an Apple ID) to confirm the real permission + sign-in flows.

So "done in repo" ≠ "verified live" — you'll do the final on-device verification.

## Architecture: mock and real coexisting

Today `OtterpaceModel.readState()` reads flat `rb*` UserDefaults keys that each
scenario seeds. We keep that for previews and add a real source behind a protocol:

```
protocol HealthDataSource {
    func currentAuthorization() -> HealthAuthState     // notDetermined | denied | authorized
    func requestAuthorization() async -> HealthAuthState
    func todaySnapshot() async -> TodayActivity         // steps, distance, activeEnergy, workouts
}
```

- `SeededHealthDataSource` — current behavior; reads `rb*` UserDefaults. Used when
  a scenario seed is present (previews, tests).
- `HealthKitDataSource` — real `HKHealthStore` reads. Used in production.
- `OtterpaceModel` picks the source at launch: seeded if a scenario is active,
  else HealthKit. The views don't change; they still render `TodayState`.

This keeps the 25+ CodeYam scenarios working unchanged while production reads live
data.

## Part A — HealthKit step tracking (the must-have)

1. **Entitlement + capability**: add HealthKit to the App target (Signing &
   Capabilities). Adds `com.apple.developer.healthkit` to the entitlements file.
2. **Info.plist**: add `NSHealthShareUsageDescription` (why we read steps) — App
   Review rejects HealthKit apps without it. (Add `NSHealthUpdateUsageDescription`
   only if we later *write* workouts.)
3. **`HealthKitDataSource`** (`Sources/AppCore/Health/`): request read access for
   step count, walking/running distance, active energy, and workouts; query
   today's totals and recent workouts; map into the existing `TodayState` /
   `LatestWorkout` / `WeeklyLoad` types.
4. **Permission states**: not-determined → show the "Connect Apple Health" hero
   (existing). authorized → load + show the dashboard. denied → a gentle
   "Health access is off — enable it in Settings" state (new, small).
5. **Wire `connect()`** to actually call `requestAuthorization()` (today it just
   flips a bool), then load the snapshot async.
6. **Tests** (verifiable here): the data-source selection logic, the
   denied/authorized state mapping, and the HealthKit→TodayState mapping with a
   fake `HKHealthStore` seam. The real HK reads themselves are platform-glue
   (verified on device).
7. **Device/simulator testing** (you): grant permission, confirm real steps
   appear; deny, confirm the fallback; add Health samples in the simulator to test
   without a device.

## Part B — Sign in with Apple (optional layer)

Only if you want accounts/sync later. Local-only (no backend) for MVP:

1. **Capability**: add "Sign in with Apple" to the App target (entitlement
   `com.apple.developer.applesignin`). **Requires the paid Apple Developer
   account + provisioning** — can't run without it.
2. **UI**: an optional sign-in screen with `ASAuthorizationAppleIDButton` and a
   prominent **"Continue without an account"** (per the no-account MVP). Never
   gates HealthKit.
3. **`SessionStore`** (`Sources/AppCore/Auth/`): run `ASAuthorizationController`,
   store the stable `user` identifier in the **Keychain** (not UserDefaults).
   Handle the gotcha that email/name are returned **only on first authorization**.
4. **State**: signed-in vs. guest; a "Sign out" in Settings (forgets the local
   identifier). No server calls.
5. **Tests** (verifiable here): the `SessionStore` state transitions and Keychain
   read/write behind a seam. The actual Apple dialog is platform-glue (verified on
   device with an Apple ID).

## Recommended sequencing

1. **HealthKit first** — it delivers the real feature with no login and matches
   the spec. Highest value.
2. **Sign in with Apple second** — optional; do it when a cross-device/account
   story is actually needed. Easy to add later behind the same `SessionStore`.

## Out of scope (for now)

Strava OAuth, a coach/AI backend, cloud sync, and HealthKit *writes* — all later
milestones; none required for real on-device step tracking.
