---
title: "Mobile-First Marketing Site"
mode: backend
createdAt: "2026-07-30T18:26:30Z"
source: manual
order: 1
---

## Summary

Make otterpace.com actually good on a phone. `site/index.html` is a
single-file landing page with **one** breakpoint at 880px and nothing below it,
so every iPhone width (390 / 393 / 375 / 430) renders the desktop layout merely
squeezed: an oversized hero headline, a five-phone theme gallery that wraps
awkwardly, desktop-sized section padding, nav links that vanish entirely with no
replacement, and tap targets under the 44pt minimum. `body{overflow-x:hidden}` is
currently **masking** horizontal overflow rather than preventing it. This plan
adds a real small-screen tier across `site/index.html`, `site/style.css`, and
`site/privacy.html`, fixes tap targets and reduced-motion, and removes the
overflow mask once the underlying overflow is gone. Nothing about the content or
the visual identity changes — this is the same page, laid out for the device most
people will actually open it on.

**Mode note:** this plan is `backend` because `site/` is a static web deploy, not
part of the registered codeyam app (`.codeyam/editor.json` lists one app, the iOS
target; `.codeyam/stack.json` marks `layout-web: not-applicable`). There is no
simulator-capturable surface, so verification is browser viewport checks at the
widths listed below rather than scenario captures.

## Key Decisions

- **Two breakpoints, not one.** Keep the existing 880px tablet reflow, add a real
  **≤560px phone tier** and a **≤380px** safety tier for the narrowest live
  devices (iPhone SE / Mini). One breakpoint is why the page looks squeezed
  rather than designed on a phone — 880px→375px is far too wide a span for a
  single rule set.

- **Fix overflow at the source, then drop the mask.** `body{overflow-x:hidden}`
  (line 25) hides real overflow, which is why nothing has visibly broken and also
  why nothing has been fixed. Identify the actual offenders — the fixed-width
  `.devs .halo` (132px), the `.mq` marquee track, the `h1` `clamp()` floor, the
  `.week` grid — constrain each, then **remove the `overflow-x:hidden`** so future
  regressions announce themselves instead of hiding.

- **The h1 floor is the biggest single problem.** `clamp(52px,8.5vw,104px)`
  (line 48) never goes below 52px, and at 900 weight, uppercase, `-.045em`
  tracking, "Run happy." on a 375px screen minus 56px of `.wrap` padding has
  ~319px to work with. Lower the floor to ~38px on the phone tier and let the
  `vw` term drive it. Same treatment for `.h2` (line 69) and `.final h2` (129).

- **Give mobile nav something, not nothing.** Line 138 does `.nl{display:none}`,
  which deletes /themes, /weekly-recap, and /open-source from every phone with no
  replacement. A hamburger menu is overkill for three anchors on a one-page site:
  instead render them as a compact scrollable chip row under the sticky nav
  (or fold them into the footer, which is already link-shaped). Either way the
  page's sections stay reachable on the device most visitors use.

- **44pt tap targets everywhere.** `nav .btn` (line 36) is 10px padding + 14px
  text ≈ 38px tall; the footer links are 13px monospace text with no padding.
  Both are below Apple's 44pt minimum on the site advertising an iOS app. Set a
  `min-height:44px` and generous hit padding on every interactive element in the
  phone tier.

- **Respect `prefers-reduced-motion`.** The `.mq` marquee (lines 38–41) runs an
  infinite 34s translate with no guard, and `.lnk:hover{transform}` /
  `html{scroll-behavior:smooth}` are likewise unguarded. One
  `@media (prefers-reduced-motion: reduce)` block pausing the marquee and
  neutralizing the transitions. This is the single highest-value accessibility fix
  on the page and costs about six lines.

- **The theme gallery becomes a scroll-snap rail on phones.** Five 150px phone
  shots in a wrapping flexbox (lines 75–85) becomes a ragged 2-2-1 stack on
  mobile, and the absolutely-positioned 132×200 `.halo` doesn't reflow with it. A
  horizontal scroll-snap rail inside its own `overflow-x:auto` container shows
  the themes the way an app-store carousel does, keeps the halo aligned to its
  figure, and contains the overflow instead of leaking it to the page.

- **Don't touch content, copy, or the OG/meta block.** Layout, spacing,
  typography scale, and accessibility only. Everything from `<title>` through the
  Twitter card tags is deliberately unchanged so social previews and SEO stay
  exactly as they are.

## Implementation

### 1. Landing page — responsive tiers

**File**: `site/index.html` (inline `<style>`, lines 21–139)

Replace the single line-138 media query with a layered set:

- **≤880px** (existing, kept): single-column `.hero-grid`, `.feat`, `.review`,
  `.steps`; `.week` at `1fr 1fr`.
- **≤560px** (new): `.wrap` padding `0 20px`; `section` padding `40px 0`;
  `h1` floor ~38px; `.h2` floor ~26px; `.lead` 17px; `.sub` 16px;
  `.made` padding `28px 20px`; `.gallery` padding `24px 16px 12px`;
  `.week` to a single column with its `.title` full-width and the four `.stat`s
  in a 2×2; `.rc`/`.fc`/`.step` padding to 16–18px; `.final` padding `40px 20px`;
  footer stacked and left-aligned with its `.disc` inheriting that alignment.
- **≤380px** (new): `h1` floor ~32px, `.cta-row` badges to `height:44px`, and the
  hero device to `width:min(240px,78vw)`.

Also, viewport-independent:

- `.cta-row` — the App Store badge and the ghosted Play badge (lines 159–162,
  242–245) get `flex-wrap` behavior that stacks them cleanly rather than leaving
  an orphan; the `.soon-tag` (`top:-9px;right:-9px`) needs container padding so it
  can't be clipped once the badges stack.
- `nav .wrap` — `gap` reduced and the brand allowed to shrink so the "Get the
  app" button never wraps.
- `body` — remove `overflow-x:hidden` **after** the offenders above are fixed, and
  verify at each width that no horizontal scrollbar appears.

### 2. Mobile nav links

**File**: `site/index.html` (nav block, lines 142–147, and `.nl` styles line 35)

Replace `.nl{display:none}` with a phone-tier treatment: a horizontally
scrollable chip row beneath the sticky nav bar (`overflow-x:auto`,
`scroll-snap-type:x proximity`, `-webkit-overflow-scrolling:touch`,
`scrollbar-width:none`), each chip ≥44px tall. Sticky-nav height grows
accordingly; confirm the `#themes` / `#recap` / `#made` anchor targets still land
correctly under the taller sticky header (add `scroll-margin-top` to those
sections).

### 3. Theme gallery rail

**File**: `site/index.html` (`.gallery` / `.devs`, lines 73–85 and 177–186)

On the phone tier, `.devs` becomes `display:flex; overflow-x:auto;
scroll-snap-type:x mandatory; flex-wrap:nowrap` with each `figure` at
`scroll-snap-align:center` and a fixed shrink-proof width; `.devs .halo` sized
relative to its figure rather than a fixed 132px so it tracks the image. Add a
short "swipe →" affordance line and keep `.devs figure.mid` from being the only
enlarged one on mobile (the size difference reads as a bug in a rail).

### 4. Accessibility pass

**File**: `site/index.html`

- `@media (prefers-reduced-motion: reduce)` — `.mq .track{animation:none}` (and
  center the single copy of the strip so it doesn't sit half-scrolled),
  `.lnk:hover{transform:none}`, `html{scroll-behavior:auto}`, and neutralize the
  `.lnk` transition.
- Interactive minimums: `min-height:44px` + hit padding on `nav .btn`, `.lnk`,
  `.nl` chips, footer links, and the badge anchors.
- Contrast: verify `--muted` (#7a7480) and `.step p` (#9a9caa on #1b1b23) against
  their backgrounds at the smaller mobile font sizes; darken/lighten the token if
  a pair lands under WCAG AA at the reduced size. The iOS app already holds AA —
  the site should match its own claim.
- `:focus-visible` rings on every anchor (currently none), so keyboard and switch
  users can see where they are.
- The marquee is decorative text repeated twice; mark the duplicate
  `aria-hidden="true"` so screen readers don't read the strip twice.

### 5. Privacy page + shared stylesheet

**File**: `site/style.css`

The `@media (max-width: 600px)` block (lines 80–85) covers `.doc` only. Extend
it to the landing-hero classes it also serves (`.hero` padding, `.hero h1` size,
`.hero img.icon` from 132px to ~104px, `.features li` padding, `.cta a` to a
44px min height and full-width-ish stacking) and add a ≤380px tier. Also give
`.doc` a `max-width` in ch for comfortable line length on large phones.

**File**: `site/privacy.html`

Verify the reflow after the CSS change; add `scroll-margin-top` if any in-page
anchors are added, and confirm the `← Otterpace` back link meets the 44pt target.
This page will also gain a "Friends (optional)" section from the social plan —
the two plans touch different parts of the file and shouldn't conflict, but land
whichever ships second on top of the first.

### 6. Verification

No scenario captures (see the mode note) — but "check it in a browser" is not a
gate unless someone is named to do it, so this specifies the method.

**Driven verification.** Serve `site/` locally and drive Chrome through the width
sweep, capturing a screenshot at each: **320, 375, 390, 393, 430, 560, 768, 880,
1140**. At every width assert programmatically rather than by eye:

- `document.documentElement.scrollWidth <= window.innerWidth` — the horizontal-overflow
  check, which is the whole reason `overflow-x:hidden` is being removed. This one
  assertion is what keeps the fix from silently regressing.
- every `a`, `button`, and `.btn` has a bounding rect ≥44px on its smaller axis.
- no element's `scrollWidth` exceeds its `clientWidth` outside the two containers
  that are *meant* to scroll (the theme rail and the nav chip row).

Then screenshot-review the sweep for clipped or awkward text, which is the part
that genuinely needs eyes.

**Reduced motion.** Re-run at 390px with reduced motion emulated and confirm the
marquee is static and its text legible in place.

**Desktop regression.** The 880px and 1140px captures must be visually identical
to the current site — diff them against captures taken before any edit. Take those
"before" captures first, as the very first step of implementation.

## Reused existing code

- The existing 880px breakpoint (`site/index.html:138`) — extended into a tiered
  set rather than replaced.
- The `@media (max-width: 600px)` block in `site/style.css:80` — the established
  small-screen pattern for the document pages, widened to cover the landing hero.
- The `:root` CSS custom-property palettes in both files — reused as-is; no new
  colors, only contrast verification of existing tokens.
- `site/style.css`'s longhand-padding comment (lines ~72–74) — a documented
  gotcha in this stylesheet worth honoring when touching `.doc` padding again.

## Scenarios to Demonstrate

*(Browser viewport checks, not simulator captures — see the mode note.)*

- Landing page at **375px** — hero headline fits on one line per phrase, badges
  stack cleanly, no horizontal scroll.
- Landing page at **320px** — the narrowest supported width, everything legible.
- Theme gallery at **390px** — the scroll-snap rail with a partial next card
  visible, halos aligned.
- Sticky nav at **390px** — the anchor chip row present and scrollable; tapping
  `/recap` lands the section below the sticky header.
- Weekly-recap block at **390px** — the four stats in a readable 2×2, not a
  cramped single row.
- "How it's made" block at **375px** — three steps stacked with mobile padding,
  both CTAs full-width-ish and ≥44px.
- Footer at **375px** — links stacked, disclaimer readable, all targets ≥44px.
- **Reduced-motion** at 390px — the marquee static and legible.
- **privacy.html** at 375px — comfortable measure, back link tappable.
- **880px and 1140px** — regression checks that the desktop and tablet layouts are
  visually unchanged.
