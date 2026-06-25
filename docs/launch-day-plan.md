# Launch-day plan (tomorrow)

Three goals, sequenced for one focused day:
1. **Ship to TestFlight** (and stage the App Store listing).
2. **Swift code is solid** — a quality pass before we archive the build.
3. **Great open-source CodeYam demo** — the repo reads as a model mobile-app project.

Owner legend: 👤 you · 🤖 me (terminal/CLI) · 🤝 both.

**Where we already are:** website is live (`https://otterpace.com`, HTTPS, AI coach works). Strava is deferred. So tomorrow is entirely the **app + repo**, not the backend.

**Suggested order:** Track B (clean the code) → Track A (archive & TestFlight the *clean* build) → Track C (polish the repo) — with C partly interleavable.

---

## Track B — Swift code quality (do first; ~2–3 h)
Get the code crisp *before* we archive, so the TestFlight build is the good one.

- 🤖 **Baseline:** `swift build` + `swift test` (currently 83/83 green) + backend `npm run typecheck`.
- 🤖 **Adversarial code review** of the M3/M5 modules — `Coach/RemoteCoach`, `Strava/StravaService`, `Notifications/MovementReminders`, `Analytics`, `Auth`, `SettingsView`. Look for: force-unwraps, error handling on the network paths, main-actor correctness, retain cycles in the `Task`s, and comment/idiom consistency.
- 🤖 **Resolve the Swift 6 `Sendable` warnings** (the `UserDefaults` captures in `OtterpaceModel`/tests) so the build is warning-clean.
- 🤖 **Add tests for the new logic** (keep coverage high): `ReminderSettings.load/save`, `RemoteCoach` decode + fallback mapping, Strava `WorkoutDTO → LatestWorkout` mapping, `Analytics` no-op when unconfigured, `CoachKeyStore`. Then `reconcile-registry --auto-apply` so the CodeYam editor sees them.
- 🤝 **Decision — Strava card in v1:** since Strava is deferred, either (a) **hide** the Settings → Strava card when `StravaClientID` is empty (recommended for a clean v1), or (b) leave the "Not set up" row. 🤖 I implement whichever you pick.
- 🤖 **Re-verify scenarios:** `seeded-capture-check` green; recapture any screen the code pass changed (Settings, etc.).
- 🤖 Commit + push; confirm Vercel still green (no web impact, but the auto-deploy will run).

**Exit criteria:** `swift test` green, no warnings, new modules tested, scenarios fresh.

---

## Track A — TestFlight + App Store (the main event; ~2–3 h)
Detailed steps live in **`docs/testflight-prep.md` §B** and **`docs/go-live-runbook.md` Phases 5–8**. Tomorrow's sequence:

**Decisions to make up front:**
- 🤝 **PostHog key in v1?** Recommend **leave `PostHogProjectKey` empty** for the first TestFlight build (analytics no-ops cleanly), set it before the public App Store release. Avoids a privacy-label dependency for internal testing.
- 🤝 **Scope tomorrow:** get an **internal TestFlight build live + tested**, and *create* the App Store record/listing. Full public submission (screenshots + review) can follow once you've tested the build.

**Steps:**
1. 👤 Confirm **paid Apple Developer** membership; add your Apple ID in **Xcode → Settings → Accounts**.
2. 👤 Register App ID **`com.otterpace.app`** (Identifiers) with **HealthKit** + **Sign in with Apple**.
3. 👤 **Xcode → Signing & Capabilities:** select Team, enable HealthKit + Sign in with Apple, confirm `App/App.entitlements` is the target's entitlements. (`ITSAppUsesNonExemptEncryption=NO` already set.)
4. 🤖 Pre-flight from terminal: `xcodebuild -showBuildSettings` + `security find-identity -p codesigning` to confirm signing is wired before we archive.
5. 🤝 **Build + run on a real device**, smoke-test: HealthKit (steps load), Sign in with Apple (in/out/delete), AI coach (your Anthropic key → real reply), reminders (permission + schedule). *(Strava skipped this round.)*
6. 🤖 **Archive + export:** `xcodebuild archive` → `-exportArchive` (App Store distribution), once signing is confirmed.
7. 🤖 **Upload to TestFlight** via the App Store Connect API (you generate an **ASC API key**: App Store Connect → Users and Access → Integrations → Keys) + `xcrun altool`/notarytool.
8. 👤/🤖 **App Store Connect → New App** record (Otterpace, `com.otterpace.app`); paste metadata from **`docs/app-store-listing.md`**.
9. 👤 **Test Information** + add **internal testers** → install via TestFlight → re-run the smoke test on the TestFlight build.
10. ⏭️ *(For public release, later)* App Privacy label (`docs/app-store-listing.md`), screenshots, submit for review.

**Exit criteria:** an internal TestFlight build installed on your device and smoke-tested.

---

## Track C — Open-source CodeYam demo polish (~1–2 h)
Make the repo a model "how to build a mobile app on CodeYam" project.

- 🤖 **README "Built with CodeYam" section** — the scenario-driven loop: `deviceState` seeding (`rb*`/`otterpace*` keys), the preview/capture flow, the mock seams (`CoachEngine`, `SeededHealthDataSource`) that keep previews deterministic while production hits real HealthKit/LLM, and the XCTest approach. Embed 2–3 scenario screenshots so the repo looks alive.
- 🤖 **`docs/built-with-codeyam.md`** — a short narrative of how the app was developed feature-by-feature through the editor (scenarios per feature, bleed-proofing, recapture), as a reference for other CodeYam projects.
- 🤖 **Community files audit** — confirm `LICENSE` (MIT), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md` are present and say *Otterpace* (no RunBuddy/personal leftovers).
- 🤖 **Secret/PII re-scan** of the whole repo before it gets more eyes.
- 👤 **GitHub repo polish** — description, topics (`swift ios swiftui healthkit codeyam running ai-coach`), social-preview image (the app icon), and pin `go-live-runbook.md` / this plan.
- 🤝 **Tag `v1.0`** once the TestFlight build is up.

**Exit criteria:** a newcomer can land on the repo and understand both the app *and* how to build one like it on CodeYam.

---

## Open decisions to settle tomorrow (collected)
1. Hide the Strava Settings card in v1, or keep "Not set up"? *(rec: hide)*
2. Set `PostHogProjectKey` for the first TestFlight build, or leave empty? *(rec: leave empty, add before public release)*
3. Tomorrow = internal TestFlight + create App Store record; public submission later? *(rec: yes)*

## Quick reference
`docs/go-live-runbook.md` (master sequence) · `docs/testflight-prep.md` (Xcode/ASC + DNS) · `docs/app-store-listing.md` (copy) · `docs/strava-and-analytics.md` (when Strava resumes: reuse Supabase project `xhrdoifnhqewgmpelkqr`).
