---
title: "App Store Submission (Public v1 Release)"
mode: ui
createdAt: "2026-07-08T20:20:38Z"
source: manual
dependsOn: ["movement-nudge-server-push"]
---

## Summary

TestFlight is done — the build uploads via `Scripts/testflight-upload.sh`, internal
testing is smoke-tested, and the listing copy/screenshots are staged. What's left is
the **public App Store submission**: the one path we've only ever referenced as
"…later" (`launch-day-plan.md` step 10, `go-live-runbook.md` Phase 7's forward
pointer). This plan operationalizes that last mile as a single runbook —
`docs/app-store-submission.md` — covering the App Privacy label, screenshots +
metadata, App Review Information (including the two review-risk mitigations unique to
this app), and **Submit for Review**. Per the decisions made while planning: **v1
ships with analytics OFF** (so the privacy label is the simplest "Data Not Collected"
case) and the approved build **auto-releases on approval**. This is an
ops/runbook doc + a small `go-live-runbook.md` update; there are **no Swift or API
source changes**, mirroring the `asc-api-key-testflight-upload` plan's shape.

## Key Decisions

- **Analytics OFF for v1 → "Data Not Collected" privacy label.** Leave
  `PostHogProjectKey` empty in `App/Info.plist` (Analytics is already a clean no-op
  when unset — confirmed in `post-review-followups.md` CUT-3). With PostHog off,
  Strava hidden (`StravaClientID` empty), and HealthKit read on-device only (never
  "collected" in App Store terms), the App Privacy answer is a clean **Data Not
  Collected** — far simpler and lower-risk than the Usage-Data label drafted in
  `app-store-listing.md`. That draft's "analytics is on" wording is superseded for
  this release; the new runbook records the v1 answer explicitly so the two don't
  drift.
- **Auto-release on approval.** In the version's *Release* section choose
  **Automatically release this version** — least friction for a first ship.
  (Manual release stays documented as the one-line alternative.)
- **Reuse the existing upload path, not a new one.** The build submitted for review
  is the same App-Store-distribution `.ipa` produced by `Scripts/testflight-upload.sh`
  (bump build number, archive, export, upload). Submission itself is an App Store
  Connect portal action — `altool` uploads builds but does not submit for review — so
  the "Submit" steps are 👤 manual in ASC. No new script.
- **Two review-risk mitigations are first-class, not footnotes.** (1) HealthKit
  shows an *empty* dashboard on a reviewer's fresh device, and (2) the AI coach is
  **bring-your-own-key**. Both are legitimate rejection triggers if a reviewer can't
  see the app work, so the runbook's **App Review Information → Notes** spells out
  that the built-in offline coach answers with no key, Sign in with Apple is optional
  (no demo account needed), and Health data may be sparse on a fresh device.
- **Doc-only, no source changes.** Constrained-file pre-check returned none;
  `*.p8` is already git-ignored; `ITSAppUsesNonExemptEncryption = NO` is already set
  (skips export compliance). Setting `PostHogProjectKey` is intentionally *not* done
  (v1 = off), so even `Info.plist` is untouched this release.

## Implementation

### 1. Write the public-submission runbook

**New file**: `docs/app-store-submission.md`

The end-to-end "TestFlight → live on the App Store" sequence, in the same
👤 manual / 🤖 terminal style as `testflight-prep.md`, with a **Verify** per phase.
Sections:

1. **Preconditions** — internal TestFlight build installed + smoke-tested
   (`go-live-runbook.md` Phase 6); app record exists (`com.otterpace.app`, SKU
   `otterpace-ios`); `movement-nudge-server-push` and all queued plans landed
   (this plan `dependsOn` it). Confirm `PostHogProjectKey` is **empty** and
   `StravaClientID` is **empty** — the v1 shipping state.
2. **Build for submission** (🤖) — `Scripts/testflight-upload.sh` to produce/upload
   the build that will be attached to the review submission (auto-bumps
   `CURRENT_PROJECT_VERSION`; Version stays `1.0`). Commit the build-number bump.
3. **App Privacy label = Data Not Collected** (👤) — App Store Connect → **App
   Privacy** → answer **We do not collect data from this app** for v1, with the
   one-paragraph rationale (analytics off, Strava hidden, Health on-device). Note
   inline: if analytics is ever turned on later, switch to the Usage-Data mapping in
   `app-store-listing.md` and update `site/privacy.html` in lockstep.
4. **Version metadata + screenshots** (👤) — in the **1.0** version: paste
   Name/Subtitle/Promotional text/Keywords/Description/"What's New"/URLs/category/
   age-rating/copyright straight from `docs/app-store-listing.md`; upload the six
   `appstore/screenshots/6.5-inch/*.png` in the documented order. **Verify screenshot
   sizing** against the current App Store Connect required display sizes before
   submitting — if ASC no longer accepts the 6.5" set alone, recapture at 6.9"
   (1320×2868, iPhone 16 Pro Max sim) per the note in `app-store-listing.md`.
5. **Age rating questionnaire** (👤) — all "None" → **4+** (matches
   `app-store-listing.md`).
6. **Pricing & Availability** (👤) — **Free**, all territories (or your chosen set).
7. **App Review Information** (👤) — contact name/phone/email (`hello@otterpace.com`);
   **Notes** covering the three reviewer-experience facts so the build isn't rejected
   as "unable to review":
   - Built-in coach answers with **no key required**; the "connect your own AI key"
     field in Settings is optional and enhances replies only.
   - **Sign in with Apple is optional** — the app is fully usable signed-out, so **no
     demo account is needed** (reviewers can use their own Apple ID to exercise it).
   - **HealthKit** data may be **empty on a fresh device**; grant the Health
     permission and note that steps/distance populate from the device's own Health
     data. (The seeded scenarios in the screenshots show the populated states.)
8. **Attach build + choose release option** (👤) — select the processed build in the
   version, set **Release → Automatically release this version** (auto-release on
   approval, per decision), then **Add for Review → Submit**. Document **Manual
   release** as the one-line alternative.
9. **After submission** (👤) — states to expect (Waiting for Review → In Review →
   Ready for Sale / Rejected); if rejected, respond in **Resolution Center**; common
   Otterpace triggers pre-empted by the review notes above. On approval it goes live
   automatically.

Cross-link `go-live-runbook.md`, `testflight-prep.md` (build/upload mechanics),
and `app-store-listing.md` (the copy source of truth).

### 2. Wire the runbook into the master sequence

**File**: `docs/go-live-runbook.md`

- Update **Phase 7 (App Store privacy label)** to record the v1 answer: with
  analytics off + Strava hidden, the label is **Data Not Collected**; point to
  `docs/app-store-submission.md` for the full submission flow. Keep the
  Usage-Data mapping as the "if you enable analytics later" branch so nothing is lost.
- Add a **Phase 10 — App Store submission** entry: one short paragraph that hands
  off to `docs/app-store-submission.md` (privacy label → metadata/screenshots →
  review notes → submit, auto-release on approval), so the master sequence ends at
  "live on the App Store" instead of "TestFlight."

## Reused existing code

- `Scripts/testflight-upload.sh` — the one-command archive/export/validate/upload
  path; reused verbatim to produce the build attached to the review submission.
- `ExportOptions.plist` — App-Store-Connect distribution export config
  (team `4D67UCFK3J`, automatic signing, upload symbols); reused as-is.
- `docs/app-store-listing.md` — the metadata/screenshots/keywords source of truth
  that the submission runbook pastes from (its "analytics on" privacy note is
  explicitly superseded for the analytics-off v1).
- `appstore/screenshots/6.5-inch/*.png` — the committed six-shot 1284×2778 set,
  uploaded in the documented order.
- `docs/go-live-runbook.md` Phases 6–8 and `docs/testflight-prep.md` §B–C — the
  existing archive/upload/TestFlight sequence this plan continues into public release.
- `App/Info.plist` — read-only here to confirm the v1 shipping state
  (`PostHogProjectKey` empty, `StravaClientID` empty,
  `ITSAppUsesNonExemptEncryption = NO`); not modified.
- `post-review-followups.md` CUT-3 — the confirmation that Analytics no-ops cleanly
  when `PostHogProjectKey` is empty, which underwrites the Data-Not-Collected label.

## Scenarios to Demonstrate

This is an ops/runbook doc with no app UI surface (like `asc-api-key-testflight-upload`),
so there are no codeyam UI scenarios. The verifiable outcomes instead are:

- `docs/app-store-submission.md` exists and renders as an ordered, checkbox runbook
  with a Verify per phase.
- `docs/go-live-runbook.md` Phase 7 reads "Data Not Collected" for v1 and a new
  Phase 10 hands off to the submission runbook.
- `Scripts/testflight-upload.sh` produces an uploadable build (the same mechanics as
  the last TestFlight upload).
- The App Privacy section in App Store Connect can be answered **Data Not Collected**
  consistently with `site/privacy.html` for the analytics-off v1.
- Version 1.0 shows attached build + all metadata + 6 screenshots, and can be
  **Submitted for Review** with auto-release selected.
