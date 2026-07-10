# Otterpace — App Store Submission Runbook (Public v1 Release)

The last mile: **TestFlight build → live on the App Store**. This is the ordered,
checkbox-per-phase sequence for the public 1.0 submission in App Store Connect
(ASC). It is **account/portal + one build command** — there are **no Swift or API
source changes** in this release.

This runbook is the execution companion to two other docs:
- **`docs/app-store-listing.md`** — the copy source of truth (Name, Subtitle,
  Description, Keywords, review notes, screenshot order). Paste from there; this
  runbook tells you *which field* each value goes in and *when*.
- **`docs/go-live-runbook.md`** — the master go-live sequence. This runbook is its
  Phase 10 (the public submission that Phase 8 TestFlight hands off to).

Legend: 👤 = you, in the ASC portal (or on a device) · 🤖 = a terminal command ·
**Verify** = the concrete check that closes each phase.

> **v1 decisions baked into this runbook** (see `docs/app-store-listing.md` and the
> `app-store-submission` plan for the rationale):
> - **Analytics OFF** (`PostHogProjectKey` empty) + **Strava hidden**
>   (`StravaClientID` empty) + **HealthKit read on-device only** → the App Privacy
>   answer is a clean **Data Not Collected**.
> - **Auto-release on approval** (Manual release documented as the one-line
>   alternative).
> - The build attached to the review submission is the **same
>   App-Store-distribution `.ipa`** produced by `Scripts/testflight-upload.sh`.

---

## Phase 0 — Preconditions

- 👤 App record exists in ASC — bundle id `com.otterpace.app`, SKU `otterpace-ios`.
- 👤 An internal **TestFlight build** is installed and smoke-tested
  (`docs/go-live-runbook.md` Phase 6).
- 👤 The public URLs resolve over HTTPS (a reviewer *will* click them):
  `https://otterpace.com`, `https://otterpace.com/privacy`.
- 🤖 Confirm the v1 shipping state in `App/Info.plist`:
  ```bash
  grep -A1 -E 'PostHogProjectKey|StravaClientID|ITSAppUsesNonExemptEncryption' App/Info.plist
  ```
  Expect: `PostHogProjectKey` **empty**, `StravaClientID` **empty**,
  `ITSAppUsesNonExemptEncryption` = **false** (skips the export-compliance prompt).

**Verify:** the app record is visible in ASC, a TestFlight build ran on a real
device, and both otterpace.com URLs load over HTTPS.

> **Already uploaded your screenshots and nothing else?** That is the expected
> starting point. Screenshots (Phase 4b) are the one asset you stage in ASC ahead
> of time; everything below — privacy label, metadata, age rating, pricing, review
> notes, build attachment — is still empty and this runbook walks each one.

---

## Phase 1 — Build the submission binary  🤖

The submitted build is the same App-Store-distribution `.ipa` the TestFlight path
produces — `altool` uploads it; **it does not submit for review** (that is a portal
action in Phase 6). Reuse the existing one-command path; do not invent a new one.

```bash
export ASC_KEY_ID=<your key id>        # e.g. LHDZUB2V8A
export ASC_ISSUER_ID=<your issuer id>  # the UUID atop the ASC Keys page
Scripts/testflight-upload.sh           # auto-bumps build number → archive → export → upload
```

- The build number (`CURRENT_PROJECT_VERSION`) auto-increments — ASC rejects a
  duplicate build number for the same marketing version. Marketing **Version stays
  `1.0`**.
- 🤖 Commit the build-number bump the script leaves in the working tree.

**Verify:** the build appears in ASC → **TestFlight** as *Processing* (5–30 min),
then flips to a green/valid state. You cannot attach it in Phase 5 until processing
finishes.

> **Skip this phase** only if the exact build you intend to ship is already
> uploaded and out of *Processing*.

---

## Phase 2 — App Privacy label = **Data Not Collected**  👤

ASC → your app → **App Privacy** → **Get Started / Edit** → answer **"We do not
collect data from this app."**

Rationale for v1: analytics is off (`PostHogProjectKey` empty), Strava import is
hidden (`StravaClientID` empty), and HealthKit data is **read on-device only** — it
never leaves the device, so it is **not "collected"** in App Store terms.

> ⚠️ **If you ever turn analytics on** (or enable Strava with server-stored tokens)
> in a later release, this answer changes to a **Usage Data** declaration — see the
> mapping in `docs/app-store-listing.md` and `docs/go-live-runbook.md` Phase 7, and
> update `site/privacy.html` in lockstep so the label and the policy never drift.

**Verify:** the App Privacy section shows **Data Not Collected** and is consistent
with `site/privacy.html`.

---

## Phase 3 — Version 1.0 metadata  👤

In the **1.0** version, paste each field **verbatim** from
`docs/app-store-listing.md` → *Ready-to-paste ASC fields*:

- **Name**: `Otterpace` · **Subtitle**: `Your friendly running coach`
- **Promotional Text** (editable anytime without review)
- **Description**
- **Keywords** (comma-separated, no spaces)
- **What's New** (v1.0)
- **Support URL** / **Marketing URL** / **Privacy Policy URL** →
  `https://otterpace.com`, `https://otterpace.com`, `https://otterpace.com/privacy`
- **Primary category**: Health & Fitness · **Secondary**: Lifestyle
- **Copyright**: `2026 Otterpace`

**Verify:** every required text field is filled and none exceeds its character
limit (ASC flags overflow inline).

---

## Phase 4 — Screenshots  👤

**4a. Which set.** A six-shot 6.5" set (1284×2778) is committed at
`appstore/screenshots/6.5-inch/`. ASC reuses one 6.5" set across display sizes.

**4b. Upload order** (first three show on the install sheet):
1. `01-today-goal-crushed.png` — Today dashboard, goal crushed
2. `02-ask-coach-knee-pain.png` — injury-aware "Safety First" coaching
3. `03-weekly-review-solid-week.png` — Weekly Review
4. `04-welcome-meet-buddy.png` — Meet Buddy onboarding
5. `05-today-fresh-start.png` — day-one dashboard
6. `06-settings.png` — Settings (privacy / BYO key)

> ⚠️ **Verify the size requirement before submitting.** If ASC no longer accepts
> the 6.5" set alone and now requires **6.9"**, recapture at **1320×2868** on an
> iPhone 16 Pro Max simulator (regenerate with `scratchpad/appstore-capture.mjs`),
> then re-upload.

**Verify:** all six screenshots render in the version in the order above, and ASC
raises no missing-display-size error.

---

## Phase 5 — Age rating, pricing, build, release option  👤

**5a. Age rating questionnaire** — every answer **None** → resulting rating **4+**
(matches `docs/app-store-listing.md`).

**5b. Pricing & Availability** — **Free**; all territories (or your chosen set).

**5c. Attach the build** — in the 1.0 version, **Build → +**, select the processed
build from Phase 1.

**5d. Release option** — in the version's **Release** section choose
**Automatically release this version** (auto-release on approval). *Alternative:*
**Manually release this version** to hold it after approval.

**Verify:** the version shows the attached build, **4+**, **Free**, and the chosen
release option — with no red "missing information" banners left except App Review
Information (Phase 6).

---

## Phase 6 — App Review Information + Submit  👤

**6a. Contact.** Name / phone / email — this must be a **working inbox** Apple can
reach you at, so use `nseldeib@gmail.com` (the address in
`docs/app-store-listing.md`'s review notes). Do **not** use `hello@otterpace.com` —
that alias is a post-launch nice-to-have (`docs/go-live-runbook.md` Phase 9) and is
not set up yet, so review correspondence would bounce.

**6b. Notes.** Paste the **App Review Information → Notes** block from
`docs/app-store-listing.md`. It pre-empts the three Otterpace-specific rejection
triggers so a reviewer can actually see the app work:
- **The AI coach works with no key** — "Ask Buddy" answers with a built-in,
  on-device coach; the "connect your own AI key" field in Settings is optional and
  only enhances replies. Leave it empty to review.
- **Sign in with Apple is optional** — the app is fully usable signed out, so **no
  demo account is needed**; a reviewer exercises every feature with their own Apple
  ID.
- **HealthKit may be empty on a fresh device** — grant the Health permission when
  prompted; steps/distance/active minutes populate from the device's own Health
  data. (The screenshots show the populated states.)

**6c. Sign-In Information.** Leave **"Sign-in required" unchecked** — no
username/password to provide.

**6d. Export compliance.** Already handled — `ITSAppUsesNonExemptEncryption = NO` in
`App/Info.plist` means ASC does not prompt.

**6e. Submit.** **Add for Review → Submit for Review.**

**Verify:** ASC accepts the submission and the version state changes to **Waiting
for Review** with no blocking validation errors.

---

## Phase 7 — After submission  👤

Expected states: **Waiting for Review → In Review → Ready for Sale** (or
**Rejected**).

- On approval with **Automatically release** selected, it goes live automatically.
  With **Manual release**, click **Release this version** when ready.
- If **Rejected**, respond in **Resolution Center**. The common Otterpace triggers
  (no-key coach, optional sign-in / no demo account, sparse HealthKit on a fresh
  device) are already pre-empted by the Phase 6 notes — point the reviewer back to
  them.

**Verify:** the app reaches **Ready for Sale** and its App Store product page loads.

---

## Cross-references

- `docs/app-store-listing.md` — the copy/keywords/screenshots source of truth this
  runbook pastes from.
- `docs/go-live-runbook.md` — master go-live sequence; this runbook is its Phase 10.
- `docs/testflight-prep.md` — the archive/export/upload mechanics behind Phase 1.
- `Scripts/testflight-upload.sh` / `ExportOptions.plist` — the reused build path.
