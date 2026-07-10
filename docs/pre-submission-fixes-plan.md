# Pre-Submission Website & Contact Fixes (v1)

Three fixes surfaced while verifying the App Store Support/Marketing/Privacy URLs
against the v1 submission (analytics-off, Strava-hidden, "Data Not Collected").
These must be resolved **before** submitting for review — the App Privacy label,
the Support URL, and the linked Privacy Policy all have to agree.

Companion docs: `docs/app-store-submission.md` (runbook), `docs/app-store-listing.md`
(copy source of truth), `docs/site-and-dns.md` (deploy + DNS mechanics).

Legend: 👤 = you (portal/DNS) · 🤖 = code/terminal · Status: ☐ todo · ☑ done.

---

## Fix 1 — Privacy policy ↔ submission alignment  🤖  ☑ DONE & LIVE (deployed 2026-07-10)

**Problem.** The live `site/privacy.html` was written in the "analytics ON" era
(2026-06-24 rewrite). It describes PostHog app analytics, Strava backend token
storage, and an optional Apple Health *upload* — none of which is true of the v1
build. That directly contradicts the App Privacy label ("Data Not Collected") and
the App Store description ("your Apple Health data ... is never uploaded"). An
inaccurate privacy label is a hard rejection trigger (App Review 5.1.1).

**Change (made in this session, local — not yet deployed):**
- Removed the **PostHog app-analytics** section (analytics off in v1;
  `PostHogProjectKey` empty).
- Removed the **Strava** section (hidden in v1; `StravaClientID` empty).
- Removed the **optional Apple Health upload / health-&-activity sync** paragraph
  (v1 reads Health on-device only and never uploads it — matches the App Store
  description).
- **Kept** (accurate for v1, disclosed as optional / off-by-default / deletable):
  Sign in with Apple + **settings sync** (step goal & preferences), and the
  **BYO-key AI coach** (stateless backend, key never stored server-side).
- **Kept** the **website** Vercel Web Analytics disclosure (the site still loads
  `/_vercel/insights/script.js`; it is website-scoped and does not affect the
  app's privacy label).
- Bumped the "Last updated" date.

**Verify:** the policy no longer claims any app analytics, Strava, or health
upload; every remaining data flow is optional + user-initiated; it is consistent
with the "Data Not Collected" label and the App Store description.

> **Judgment call for you to confirm with Apple's rules:** "Data Not Collected"
> relies on **settings sync** (goal/prefs) qualifying for Apple's *optional-data
> exemption* — it is off by default, user-initiated, not used for tracking/ads,
> and not primary functionality, which is the standard basis for that exemption.
> If you'd rather not rely on the exemption, the alternative is to declare
> "Other Data / not linked to you" on the label instead of "Data Not Collected."

---

## Fix 2 — Wire up hello@otterpace.com via free forwarding  👤  ☑ DONE (2026-07-10)

**Resolved via Namecheap Email Forwarding** — added a single forwarder
`hello@ → nseldeib@gmail.com` (no catch-all, to keep spam down) and accepted
Namecheap's MX records. A test email to `hello@otterpace.com` was received in
Gmail — confirmed working.

<details><summary>Original plan (for reference)</summary>

**Problem.** The Privacy Policy's Contact line and (after Fix 3) the homepage point
at `hello@otterpace.com`, which has **no mailbox** — mail bounces. The App Store
*review* contact deliberately uses `nseldeib@gmail.com` instead (see runbook
Phase 6), but the **public-facing** address needs to actually deliver.

**Approach — free email forwarding (no mailbox cost).** DNS for otterpace.com is on
**Namecheap** (A records `@` + `www` → `76.76.21.21`, per `docs/site-and-dns.md`).
Namecheap includes **free Email Forwarding** — the simplest option since DNS is
already there:

1. 👤 Namecheap → Domain List → otterpace.com → **Manage** → **Email Forwarding**
   (or Advanced DNS).
2. 👤 Add a forwarding rule: **hello@** → `nseldeib@gmail.com`. Add a catch-all
   (`*@` → same) if you want to future-proof `support@`, etc.
3. 👤 Namecheap will prompt to add its **MX records** (e.g. `mx1.privateemail.com`
   / `mx2.privateemail.com`) — accept them. ⚠️ This adds MX records to a domain
   whose web/A records point at Vercel; MX and A are independent, so mail routing
   does **not** affect the website.
4. 👤 Wait for DNS propagation (minutes–1 hr), then send a test to
   `hello@otterpace.com` and confirm it lands in the Gmail inbox.

*Alternatives if you prefer them over Namecheap forwarding:* **Cloudflare Email
Routing** (free, but requires moving DNS to Cloudflare) or **ImprovMX** (free tier,
add their MX + a TXT). Namecheap-native is the least-moving-parts choice here.

**Verify:** a test email to `hello@otterpace.com` is received at
`nseldeib@gmail.com`.
</details>

---

## Fix 3 — Add a contact/support path to the homepage  🤖  ☑ DONE & LIVE (deployed 2026-07-10)

**Problem.** Apple's **Support URL** (`https://otterpace.com`) must give users a way
to get help. The homepage had only "View on GitHub" and "Privacy" links — no
contact route (App Review 1.5 soft-rejection risk). It also still reads "Coming
soon to the App Store."

**Change (made in this session, local — not yet deployed):**
- Added a **Contact** link (`mailto:hello@otterpace.com`) to the homepage CTA row
  and footer.

**Verify:** the homepage shows a working Contact link; once Fix 2 is live, clicking
it opens a mail composer to a deliverable address.

> **Also worth doing at launch (not blocking):** flip "🐾 Coming soon to the App
> Store" to a real **Download on the App Store** badge/link once the app is live.

---

## Deploy  👤/🤖  ☑ DONE & LIVE (2026-07-10)

Deployed to Vercel production and verified live over HTTPS: `privacy.html` shows
"Last updated: July 10, 2026" with no PostHog/Strava/health-sync terms, and the
homepage Contact `mailto:` link is present.

> **Gotcha discovered during deploy:** Git-push auto-deploy was **silently
> broken** — the every-20-min movement-nudge cron (`fa50187`, 2026-07-09) exceeds
> the Vercel **Hobby** plan's daily-cron limit, so every deploy since it landed
> was rejected. Fix: removed the `crons` block from `vercel.json` (commit on
> 2026-07-10) and deployed via `vercel --prod --yes`. `api/cron/movement-nudge.ts`
> stays in the repo; re-add the schedule after a **Pro** upgrade. See the
> follow-up note below.

---

## Follow-ups (not blocking submission)

- **Server-driven movement push is inert** until Vercel Pro + the cron is
  re-added. Client code (`fa50187`) ships in the app build but no server push
  fires; **local** movement reminders are unaffected. Decide later: upgrade to
  Pro, or move the nudge to an external scheduler.
- **App Store Connect build is stale.** ASC has build 3 (1.0/3, TestFlight-
  Approved, 2026-07-06), but **7 app-source feature commits** landed after it
  (intent-aware coaching, weekly-review live data, race persistence/import, race
  dead-state fix, movement nudges). The listing + screenshots advertise these, so
  submit a **fresh build (1.0/4)** from current HEAD via
  `Scripts/testflight-upload.sh` (runbook Phase 1) before attaching in ASC.
- **Homepage still says "Coming soon to the App Store."** Flip to a real App Store
  link once live.
