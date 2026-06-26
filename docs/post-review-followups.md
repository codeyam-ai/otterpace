# Post-review follow-ups

Tracking the work left after the OSS / TestFlight code-quality pass (the pass
itself fixed all blockers + highs and most mediums). Two buckets: **deploy/config
actions** (require credentials or infra only you can provision) and **deferred
findings** (low-severity product decisions intentionally left open).

To turn any deferred item into a formal build, run `/codeyam-plan` and reference
the finding id below.

---

## A. Deploy / config actions (required to go fully live)

### A1. Account-sync backend (the BE-1 auth subsystem)
The new session-token auth is code-complete and tested, but the backend needs
provisioning before signed-in sync works against the deployed API:

- [ ] Create the `account_sessions` table in Supabase (SQL in `docs/account-sync.md`).
- [ ] Set the `APPLE_BUNDLE_ID` env var in Vercel (defaults to `com.otterpace.app`;
      set explicitly if the bundle id differs).
- [ ] Deploy the updated `api/`. Until then, signed-in sync degrades **gracefully**
      (the server 401s, the client silently keeps data local) — no crash, no data loss.

### A2. Strava (code-complete + hardened; gated off by config)
Strava is fully wired and now BE-2-hardened; the v1 "hidden" state is just the
empty `StravaClientID`. To enable it:

- [ ] Register a Strava API application to get a client id + secret.
- [ ] Set `StravaClientID` in `App/Info.plist` (public, safe to ship).
- [ ] Set `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET` in Vercel.
- [ ] Confirm the Strava app's Authorization Callback Domain is `otterpace.com`.

Leaving these blank keeps the Strava card hidden — a valid v1 shipping state.

### A3. New TestFlight build
The build config is archive-ready (Release config, wired entitlements, automatic
signing, iPhone-only). To ship a build:

- [ ] Bump `CURRENT_PROJECT_VERSION` (build number) in the App target before each
      upload — now driven from build settings, not hardcoded in `Info.plist`.
- [ ] Archive (Release) and upload via the existing `docs/testflight-prep.md` runbook.

---

## B. Deferred findings (low-severity — your call)

### ✅ CUT-3 — PostHog analytics ships disabled — RESOLVED
Confirmed `Analytics` is already a clean no-op when `PostHogProjectKey` is empty
(`enabled = !projectKey.isEmpty`, guarded in `capture`). Decision: **keep the no-op
stub** — it's disclosed in the privacy policy and makes zero network calls until a
key is configured. No code change needed.

### ✅ SW-4 — Strava connect could land on a silent empty dashboard — RESOLVED
`StravaService.fetchActivities()` now **throws** on a real failure (network/non-200/
decode) instead of returning `[]`, so a failed import after a successful connect is
surfaced in `SettingsView` with the error message and a **Retry import** action,
rather than silently showing an empty dashboard. A legitimate zero-activities import
still returns `[]` (no error).

### ✅ BE-6 — prefs health-field denylist was top-level only — RESOLVED
`prefsContainHealthFields` now recurses through nested objects and arrays (bounded
depth) so a health field hidden one level down can't slip past the defense-in-depth
guard. Covered by a new nested-payload test in `test/api/account.test.ts`.

### ✅ BE-7 — coach content-type / context-shape strictness — RESOLVED
`coach.ts` now requires `Content-Type: application/json` (415 otherwise — the iOS
client always sends it) and rejects a non-object `context` (400 `invalid_context`)
so only structured context reaches the prompt. CORS stays intentionally unset (the
endpoint is called from the app, not a browser, so the restrictive default is
correct). Covered by new tests in `test/api/coach.test.ts`.

### B3. TF-5 — unused `NSHealthUpdateUsageDescription` (intentionally kept)
The app never writes to HealthKit, so this usage string is technically unused. It
was **kept on purpose**: removing it would reverse a prior TestFlight fix and an
extra usage string is harmless on upload. Revisit only if Apple ever flags it.
