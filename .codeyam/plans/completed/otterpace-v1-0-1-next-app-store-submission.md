---
title: "Otterpace v1.0.1 — Next App Store Submission"
mode: ui
createdAt: "2026-07-13T20:00:04Z"
source: manual
---

## Summary

Prepare the second App Store submission round for Otterpace, cleaning up the
three gaps left by the v1.0 submission and shipping the one website change that
becomes possible once the app is live. This covers: (1) attaching **build 4**
(already in TestFlight, carries the 7 post-build-3 feature commits including the
loading-scenario race fix) instead of build 3; (2) filling in the **Subtitle**
field that was accidentally omitted last time; (3) refreshing the **screenshots**
to the current UI; and (4) the one **code change** — flipping the homepage
"Coming soon" badge into a real "Download on the App Store" link once the app has
a live numeric App Store ID. Everything but item 4 is App Store Connect portal /
build work paired to `docs/app-store-submission.md`; item 4 is a small edit to
`site/index.html` + `site/style.css`.

## Key Decisions

- **Build 4, not a fresh archive** — build 4 is already uploaded and processed in
  TestFlight and carries every commit since build 3, so the next submission just
  attaches it in ASC. Only re-run `Scripts/testflight-upload.sh` (auto-bump →
  build 5) if additional feature work lands before this round submits.
- **Subtitle is metadata-only, no review risk** — `Your friendly running coach`
  (27 chars) is already the source-of-truth value in `docs/app-store-listing.md`;
  this round just enters it in the field that was left blank.
- **Screenshots: reuse the capture path, don't hand-shoot** — the raw 6.5" set is
  the current on-disk asset; regeneration should go through a seeded-scenario
  capture. The `scratchpad/appstore-capture.mjs` script referenced in the docs is
  **not present in the working tree** and must be reconstructed (or screenshots
  captured manually via `simctl`, accounting for the known LaunchScreen capture
  race) before this item can complete. Flagged so it isn't discovered at submit
  time.
- **Homepage badge flip is gated on a live App Store ID** — the numeric app ID in
  `https://apps.apple.com/app/id<APP_ID>` does not exist until the app is
  approved and live. The code change is written now but must not ship until that
  ID is known; until then the badge stays "Coming soon."
- **Do NOT bump the marketing version blindly** — decide 1.0.1 vs a fresh 1.0
  metadata update in ASC based on whether build 3 was approved. If 1.0 is live,
  the subtitle/screenshot/build-4 changes go into a new **1.0.1** version;
  if 1.0 is still in review, these can be edited in place. Resolve at execution
  time against the actual ASC state.

## Implementation

### 1. Flip the homepage "Coming soon" badge to a real App Store link

**File**: `site/index.html` (line 19)

Currently:
```html
<div class="badge">🐾 Coming soon to the App Store</div>
```

Change to an anchor pointing at the live App Store product page once the numeric
App Store ID is known:
```html
<a class="badge badge-cta" href="https://apps.apple.com/app/id<APP_ID>">Download on the App Store</a>
```

Keep the paw emoji decision consistent with the rest of the site (emoji are fine
in website HTML — the no-emoji rule is App Store Connect's Description field
only). The `<APP_ID>` placeholder must be replaced with the real numeric ID from
the live App Store listing before this ships.

**File**: `site/style.css` (`.badge` at line 35)

The existing `.badge` rule already renders a pill. Add an anchor-friendly
variant (`.badge-cta`) so the badge-as-link keeps the pill look, gets
`text-decoration: none`, an obvious hover/active state, and remains keyboard
focusable. Reuse the existing brand color variables (`--brand-deep`,
`--brand`) already used by `.badge` and `.cta` so it matches the design system.

### 2. Enter the Subtitle in App Store Connect

**Portal step** (App Store Connect → 1.0.1 / 1.0 version → Subtitle):

Paste `Your friendly running coach` verbatim from
`docs/app-store-listing.md` → *Ready-to-paste ASC fields → Subtitle*. This is the
field omitted in the v1.0 submission. No code change.

### 3. Refresh screenshots

**Asset dir**: `appstore/screenshots/6.5-inch/` (six 1284×2778 PNGs)

Regenerate the six-shot set from the current UI so screenshots reflect the
build-4 app. Preferred path: reconstruct the missing
`scratchpad/appstore-capture.mjs` seeded-scenario capture flow (the docs still
reference it). Fallback: capture manually on an iPhone 13 Pro Max simulator with
a clean 9:41 status bar, working around the known LaunchScreen capture race
(manual `simctl` relaunch + screenshot). Verify ASC still accepts the 6.5" set
alone; if it now requires 6.9", recapture at 1320×2868 on an iPhone 16 Pro Max
sim. Re-upload in the documented order (first three show on the install sheet).

### 4. Attach build 4 and submit

**Portal step** (App Store Connect → version → Build → +):

Select the processed **build 4** from TestFlight (confirm it is out of
*Processing*). Then walk `docs/app-store-submission.md` Phase 5c–6 to finish:
age rating stays 9+, Free, App Privacy = Data Not Collected, review notes from
`docs/app-store-listing.md`, contact `nseldeib@gmail.com`, and Submit for Review.

### 5. (Optional / deferred) Re-enable the movement-nudge cron

**Files**: `vercel.json`, `api/cron/movement-nudge.ts`

The `*/20 * * * *` cron was removed to unblock free-plan Vercel deploys (Hobby
allows only daily crons). If the movement-nudge push feature is wanted for this
round, either move the schedule to a daily cadence that fits Hobby limits, or
upgrade to Vercel Pro and re-add the sub-daily `crons` block. Leave inert
otherwise — it does not block the App Store submission.

## Reused existing code

- `Scripts/testflight-upload.sh` — the one-command archive → export → upload path;
  only needed if a build 5 becomes necessary (build 4 already uploaded).
- `docs/app-store-listing.md` — copy source of truth for Subtitle, Description,
  keywords, review notes, and screenshot order.
- `docs/app-store-submission.md` — the ordered ASC portal runbook (Phase 3
  metadata, Phase 4 screenshots, Phase 5 build/age/pricing, Phase 6 submit).
- `.badge` / `.cta` rules in `site/style.css` and the brand CSS variables — reused
  for the new `.badge-cta` link styling.
- `appstore/screenshots/6.5-inch/` — existing raw set and documented upload order.
- `api/cron/movement-nudge.ts` — existing APNs push handler (`listNudgeCandidates`,
  `shouldNudge`, `CRON_SECRET` auth), inert until a cron is re-scheduled.

## Scenarios to Demonstrate

- **Homepage badge — live-ID state**: badge renders as a "Download on the App
  Store" link with a valid `apps.apple.com/app/id…` href, styled as a pill, and
  is keyboard-focusable.
- **Homepage badge — pre-launch state**: with no live ID, the badge still shows
  "Coming soon to the App Store" and does not link out (guard against shipping a
  dead `id<APP_ID>` placeholder link).
- **Badge hover/focus**: hover and keyboard-focus states are visibly distinct and
  match the site's brand palette.
- **Responsive**: badge-as-link wraps cleanly and stays centered on a narrow
  (mobile) viewport, same as the current static badge.
