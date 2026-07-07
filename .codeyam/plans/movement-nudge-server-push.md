---
title: "Opt-In Server-Driven Movement Push"
mode: backend
createdAt: "2026-07-07T15:43:24Z"
source: manual
dependsOn: ["movement-nudge-fires-on-real-inactivity"]
---

## Summary

For users who want it, add an **optional, account-backed** server-driven movement
nudge on top of the on-device fix (`movement-nudge-fires-on-real-inactivity`).
When a user is signed in with Apple, has enabled health sync, and grants push
permission, the app registers an APNs device token against their persistent
backend session, keeps the backend's view of their last-movement time fresh, and
a scheduled job sends a "time to move" push after `inactivityHours` of real
inactivity — reliably, even if the device never wakes the on-device observer. It
stays strictly opt-in: guests and privacy-minded (health-off) users keep the
on-device behavior from the prerequisite plan and never register a token or upload
movement times. This leans on the persistent login that already exists (the
Sign-in-with-Apple → bearer session established at `SignInView.swift:63`); the
missing pieces are APNs registration, a movement heartbeat, and the server job.

## Key Decisions

- **Reuse the existing persistent backend session; don't build a new login.**
  `AccountSessionService.establish(identityToken:)` already exchanges Apple's
  identity token for a long-lived Keychain-stored bearer at sign-in. Push-token
  registration and the movement heartbeat ride on that same bearer — the "more
  persistent login" is really "use the session we already have to key
  server-side push."
- **Strictly opt-in and gated three ways.** A push is only ever sent when
  `session == .signedIn` AND `SyncConsentStore.healthSyncEnabled` (off by default,
  behind the one-time consent moment) AND the OS notification permission is
  granted. No token is registered and no movement time is uploaded otherwise, so
  the change is invisible to guests and health-off users.
- **Server is authoritative for the push; on-device stays the baseline.** The
  device uploads last-movement timestamps (a tiny heartbeat, piggybacked on the
  existing health-sync stream) and the backend decides when to push. The
  prerequisite plan's local nudge remains the fallback so a user with sync off,
  or offline, still gets a correct local reminder. Both are de-duplicated by id
  so a user never gets two nudges for the same idle period (server suppresses when
  it knows the local one is armed; simplest: server nudge only for health-sync
  users, who suppress the local inactivity notification while sync is active).
- **Least-sensitive payload.** The heartbeat carries only a `lastMovementAt`
  timestamp and the chosen `inactivityHours`, not raw health samples — extending
  the existing `SyncableHealthSnapshot` contract rather than opening a new data
  category.

## Implementation

### 1. Register for remote notifications at sign-in

**File**: `App/App.swift`

Extend the `@UIApplicationDelegateAdaptor` added in the prerequisite plan to
implement `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` and
`…didFailToRegisterForRemoteNotificationsWithError:`. Call
`UIApplication.shared.registerForRemoteNotifications()` only after the user is
signed in, has health sync on, and notifications are authorized.

**File**: `App/App.entitlements`

Add `aps-environment` (development/production via build config).

**File**: `App/Info.plist`

Add `UIBackgroundModes` → `remote-notification`.

### 2. Push-token registration client

**New file**: `Sources/AppCore/Account/PushRegistrationService.swift`

A small service that POSTs the APNs device token (hex) to a new backend endpoint
with the bearer session attached (same pattern as `URLSessionAccountSyncTransport`
/ `AccountSessionService`). Best-effort: any failure leaves push simply off, app
stays fully functional. Injectable URLSession + token provider for tests.
Also expose a `deregister()` used on sign-out / health-sync-off / account deletion
(wire into `SessionStore.signOut/endSession/deleteAccount` and the Settings
health-sync toggle).

### 3. Movement heartbeat

**File**: `Sources/AppCore/Account/AccountSyncService.swift`

When `healthSyncEnabled`, include `lastMovementAt` (from the prerequisite plan's
`lastMovementDate()`) and the user's `inactivityHours` in the health push so the
backend always has a fresh idle baseline. Extend `SyncableHealthSnapshot`
(`AccountSyncTransport` contract) with those fields.

**File**: `Sources/AppCore/Notifications/MovementActivityMonitor.swift`

On each background HealthKit wake (already added in the prerequisite plan), also
fire the heartbeat when health sync is on — so the server's last-movement view
updates without requiring a foreground.

### 4. Backend: token store, endpoint, and scheduler

**New file**: `api/account/push.ts`

`POST` registers `{ deviceToken, platform }` for the bearer's user;
`DELETE` removes it. Authenticated via the existing `api/_lib/session.ts` bearer
verification.

**File**: `api/_lib/account.ts`

Extend the per-user account record with `pushTokens[]`, `lastMovementAt`,
`inactivityHours`, and `lastNudgeSentAt` (for de-dup). The health `PUT`
(`api/account/health.ts`) writes `lastMovementAt` / `inactivityHours` from the
heartbeat.

**New file**: `api/_lib/apns.ts`

Minimal APNs HTTP/2 sender (token-based auth: key id, team id, `.p8`) reading
credentials from environment variables. Sends the "Stretch your legs?" payload
mirroring `ReminderCopy.inactivity*`.

**New file**: `api/cron/movement-nudge.ts` + **File**: `vercel.json`

A scheduled function (Vercel cron, e.g. every 15–30 min) that scans users with a
push token + health sync on, computes `now - lastMovementAt >= inactivityHours`,
skips anyone nudged within the current idle window (`lastNudgeSentAt`), sends the
APNs push, and stamps `lastNudgeSentAt`. Respects a quiet-hours guard so no nudge
fires overnight.

### 5. Suppress the double nudge

**File**: `Sources/AppCore/Notifications/MovementReminders.swift` /
`MovementActivityMonitor.swift`

When server push is active for this user (signed in + health sync on + token
registered), skip arming the *local* inactivity notification so the user gets one
nudge, not two. If sync later turns off, fall back to the local nudge from the
prerequisite plan.

### 6. Tests

**File**: `Tests/AppCoreTests/PushRegistrationServiceTests.swift` (new)

Token register/deregister hits the right path with the bearer; failures are
swallowed; deregister is triggered on sign-out / health-off.

**File**: `api/_lib/*.test.ts` (vitest, per the backend harness)

Idle detection + de-dup: a user idle past threshold gets exactly one push per idle
window; a user who moved recently gets none; quiet-hours suppresses; health-off /
tokenless users are skipped.

## Reused existing code

- `AccountSessionService` + `AccountSessionStore` (`Sources/AppCore/Account/AccountSession.swift`)
  — the persistent bearer session the push registration authenticates against.
- `URLSessionAccountSyncTransport` auth pattern (`Sources/AppCore/Account/AccountSyncTransport.swift`)
  — mirror its `authorize(_:)` bearer attachment for the push endpoint.
- `SyncConsentStore.healthSyncEnabled` + consent gating (`Sources/AppCore/Account/SyncConsent.swift`)
  — the opt-in gate; no push without it.
- `AccountSyncService` health push (`Sources/AppCore/Account/AccountSyncService.swift:135`)
  — extend for the movement heartbeat rather than adding a new stream.
- `ReminderCopy.inactivityTitle/Body` (`Sources/AppCore/Notifications/MovementReminders.swift`)
  — reuse verbatim for the server payload so local + server nudges read identically.
- `api/_lib/session.ts` bearer verification + `api/account/health.ts` shape — the
  server-side handshake and per-user record to extend.
- `lastMovementDate()` from the prerequisite plan — the single source of the idle
  baseline on both device and server.

## Scenarios to Demonstrate

- Signed-in + health sync on + push granted, idle past threshold — a server push
  is sent, and the local nudge is suppressed (exactly one nudge).
- Same user, moved 5 minutes ago — no push (server sees a fresh `lastMovementAt`).
- Guest / health-sync off — no token registered, no upload, local on-device nudge
  from the prerequisite plan still works.
- Quiet hours — idle user gets no overnight push.
- Health sync turned off in Settings — token deregisters and behavior reverts to
  the on-device nudge.
- Sign out / delete account — push token is removed server-side and locally.
