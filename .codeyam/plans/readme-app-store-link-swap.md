---
title: "Post-Launch Link Swap — App Store URL Everywhere"
mode: ui
createdAt: "2026-07-16T01:33:00Z"
source: manual
dependsOn: ["readme-quality-pass"]
---

## Summary

Once Otterpace is live on the App Store, replace every "coming soon / TestFlight /
in review" placeholder with the real App Store listing URL, and add proper
install affordances (App Store badge/link) across the repo and the marketing
site. This is the deferred follow-up to `readme-quality-pass`, which intentionally
leaves clearly-marked TODO placeholders rather than shipping a dead store link.
This plan should be run **after** the app is approved and its App Store URL is
known.

## Key Decisions

- **Gated on launch** — `dependsOn: ["readme-quality-pass"]`; do not run until the
  app is actually approved and the App Store URL exists. The whole point is to
  swap placeholders for a real, working link.
- **Single source of truth for the URL** — collect the App Store URL once and
  apply it everywhere (README, site, docs) so there's no drift.
- **Add a real install affordance** — match the sibling showcase repos
  (Counter/TabCommand link straight to their store listing); add an official
  "Download on the App Store" badge/link, not just a bare URL.

## Implementation

### 1. Replace the README availability placeholder

**File**: `README.md`

Swap the `<!-- TODO: replace with App Store URL on launch -->` placeholder added
by `readme-quality-pass` for the live listing. Change the Availability section
from "in TestFlight / App Store review" to an available-now framing with an
"Download on the App Store" link/badge pointing at the real URL. Keep the
[otterpace.com](https://otterpace.com) reference.

### 2. Sweep the repo for remaining launch-state placeholders

**Files**: `README.md`, `docs/*.md` (esp. `docs/go-live-runbook.md`,
`docs/testflight-prep.md`), and any `appstore/` listing metadata

Grep for `TestFlight`, `App Store review`, `coming soon`, and the TODO marker
across tracked files and update each to the post-launch wording. Confirm the
go-live runbook is marked complete or archived as appropriate.

### 3. Update the marketing site (otterpace.com)

**Files**: `site/` (landing page + any CTA)

Point the site's primary CTA at the live App Store listing (App Store badge),
replacing any waitlist/TestFlight/coming-soon copy. Redeploy via Vercel per the
existing deploy flow.

### 4. Verify no dead or placeholder links remain

**Files**: repo-wide

Final grep to confirm no `TODO: replace with App Store URL`, no "coming soon",
and no dead store links remain anywhere in the repo or site.

## Reused existing code

- `README.md` Availability section + TODO placeholder introduced by
  [readme-quality-pass](.codeyam/plans/readme-quality-pass.md)
- `docs/go-live-runbook.md`, `docs/testflight-prep.md` — launch-state prose to update
- `site/` — marketing landing page CTA
- `appstore/` — listing metadata (if store URL is referenced there)
- [otterpace.com](https://otterpace.com) — canonical product site, kept as a reference throughout

## Scenarios to Demonstrate

Documentation/marketing-copy change with no app runtime surface — verification is
by review, not captured scenarios:

- README Availability shows an available-now App Store badge/link (real URL, resolves)
- No `TODO: replace with App Store URL`, "coming soon", "in review", or TestFlight-only
  copy remains in the repo or `site/`
- otterpace.com CTA links to the live App Store listing after redeploy
