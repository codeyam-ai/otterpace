---
title: "ASC API Key — TestFlight Upload"
mode: ui
createdAt: "2026-06-25T17:57:16Z"
source: manual
---

## Summary

The App Store Connect (ASC) API Access Request is now **approved**, which unlocks
generating API keys and uploading builds to TestFlight from the terminal instead
of clicking through Xcode Organizer. This plan captures the full TestFlight
sequence — archive → export → ASC-key upload → TestFlight setup → smoke test —
splitting each step into **🤖 Claude (terminal/repo)** vs **👤 manual (Apple
portals / real device)** work. It also adds the one real repo change this requires:
ignoring `*.p8` keys so a downloaded ASC key can never be committed. This mirrors
`docs/launch-day-plan.md` steps 6–9 and makes the new **Section C** of
`docs/testflight-prep.md` actionable end-to-end.

## Key Decisions

- **CLI upload over Organizer GUI** — now that the API is approved, `xcrun altool
  --upload-app` with an API key is scriptable and repeatable (just bump the build
  number), versus manual Organizer clicks. The Organizer path stays documented as
  a fallback in `testflight-prep.md` B.4.
- **App Manager key role** — sufficient for TestFlight uploads; avoids granting
  Admin to a CI-style key. Documented in `testflight-prep.md` C.1.
- **Key stored at `~/.appstoreconnect/private_keys/`, never in repo** — Apple
  tools resolve `--apiKey <KEY_ID>` from that path automatically, so no secret ever
  touches the working tree. The `.gitignore` change is the guardrail that makes the
  "never commit it" instruction enforceable rather than aspirational.
- **Reuse existing `ExportOptions.plist`** — already set to `app-store-connect` /
  team `4D67UCFK3J` / automatic signing / upload symbols; the export step needs no
  new config.

## Implementation

### 1. Ignore App Store Connect API keys (repo change — 🤖 Claude)

**File**: `.gitignore`

Add patterns so a downloaded `.p8` key can never be staged, even if a user drops
it in the repo by mistake:

```
# App Store Connect API keys — never commit
*.p8
AuthKey_*.p8
```

This is the only source/repo change in the plan; it makes the "the `.gitignore`
ignores `*.p8`" claim already written in `docs/testflight-prep.md` Section C.2 true.

### 2. Generate the ASC API key (👤 manual — Apple portal)

**No file change.** In App Store Connect → **Users and Access → Integrations →
App Store Connect API → Keys → +**:
- Name `otterpace-ci`, **Access: App Manager**.
- **Download API Key** (`.p8`) — downloadable **only once**; if lost, revoke + regenerate.
- Capture **Key ID**, **Issuer ID**, and the `.p8` file.

Then move the key into place (🤖 Claude can run this once the file is in `~/Downloads`):
```
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
```

Reference: `docs/testflight-prep.md` Section C.1–C.2.

### 3. Confirm signing & prerequisites (👤 manual + 🤖 pre-flight)

**No file change.** Prerequisites that must already be true (from
`testflight-prep.md` B.1–B.3):
- 👤 App ID `com.otterpace.app` registered with **HealthKit** + **Sign in with Apple**.
- 👤 App Store Connect **app record** created (Otterpace, SKU `otterpace-ios`).
- 👤 Xcode Signing & Capabilities: Team selected, automatic signing, both capabilities on.
- 🤖 Pre-flight: `xcodebuild -showBuildSettings` + `security find-identity -p
  codesigning` to confirm signing is wired before archiving.

### 4. Archive the build (🤖 Claude — terminal)

**No file change.** Produce the archive consumed by the export step (build dir
already contains `build/Otterpace.xcarchive` from a prior run; re-archive for a
fresh build):
```
xcodebuild archive \
  -project App.xcodeproj -scheme App \
  -destination 'generic/platform=iOS' \
  -archivePath build/Otterpace.xcarchive
```
Bump **Build** number in the Xcode target for every subsequent upload (Version
stays `1.0`).

### 5. Export the `.ipa` (🤖 Claude — terminal)

**No file change.** Reuse `ExportOptions.plist` (already correct):
```
xcodebuild -exportArchive \
  -archivePath build/Otterpace.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export
```

### 6. Validate + upload to TestFlight (🤖 Claude — terminal)

**No file change.** Using the Key ID + Issuer ID from step 2:
```
# Optional pre-flight validation
xcrun altool --validate-app -f build/export/Otterpace.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>

# Upload
xcrun altool --upload-app -f build/export/Otterpace.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```
`--apiKey` is the **Key ID**, not a path; the tool resolves the `.p8` from
`~/.appstoreconnect/private_keys/`.

### 7. TestFlight setup (👤 manual — App Store Connect)

**No file change.** After the build finishes processing (5–30 min):
- 👤 Fill **Test Information** (beta description + feedback email). Export
  compliance is auto-answered by `ITSAppUsesNonExemptEncryption = NO`.
- 👤 Add **internal testers** (≤100 team users) to an internal group — no Beta App
  Review, available immediately.
- ⏭️ External testers later require Beta App Review + the App Privacy label
  (`docs/app-store-listing.md`).

### 8. Smoke-test the TestFlight build (👤 manual — real device)

**No file change.** Install via the TestFlight app and run the
`go-live-runbook.md` **Phase 6** checklist end-to-end: HealthKit, Sign in with
Apple, AI coach (real Anthropic key → live reply), Strava, reminders, analytics.

## Reused existing code

- `ExportOptions.plist` — existing App Store distribution export config
  (`app-store-connect`, team `4D67UCFK3J`, automatic signing, upload symbols);
  reused as-is by the export step.
- `docs/testflight-prep.md` Section C — the just-added ASC API key walkthrough this
  plan operationalizes.
- `docs/launch-day-plan.md` steps 6–9 and `docs/go-live-runbook.md` Phases 6 & 8 —
  the existing archive/upload/TestFlight/smoke-test sequence this plan threads the
  API-key path through.
- `App.xcodeproj` scheme `App` — existing build target/scheme for archive & export.

## Scenarios to Demonstrate

This is an ops/runbook + `.gitignore` change with no app UI surface, so there are
no codeyam UI scenarios. The verifiable outcomes instead are:

- `.gitignore` rejects a staged `.p8` — `git check-ignore AuthKey_TEST.p8` returns
  the path (ignored).
- `xcodebuild -exportArchive` produces `build/export/Otterpace.ipa` from the archive.
- `xcrun altool --validate-app` returns success against the exported `.ipa`.
- After upload, the build appears in App Store Connect → TestFlight as "Processing".
- Smoke test passes on the installed TestFlight build (runbook Phase 6).
