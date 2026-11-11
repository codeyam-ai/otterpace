// codeyam-generated — DO NOT EDIT.
// codeyam-editor: 0.1.7  build: 283adba28f3fc30f058c87b4f92900dccc81f9e5  source-sha256: 1e8c260517a4c76f3fd8972c25ada9bcd623b43d1042bb0cc317fb2f5e1d0787
// Interaction targeting for the capture harness: turn a step's visible-text or
// CSS-selector target into the one element to act on, explain a miss in terms
// the author can act on, and measure where a pointer step lands inside its
// target. Split out of scenario-playwright.js, which drives the interactions
// themselves; everything here reads the page and never acts on it.

// The CSS selector for "clickable / interactive" elements — buttons, links,
// role=button, form controls, <summary>, and anything with an onclick. Shared
// by the candidate-label collector (below) and the text-target resolver
// (`resolveTextTarget`), which prefers an interactive element over a plain
// text node when a click/press label matches both.
const INTERACTIVE_SELECTOR =
  "button, a[href], [role=button], input, select, textarea, summary, [onclick]";

// Collect up to 20 distinct visible labels of interactive elements on the
// page — buttons, links, role=button, form controls, <summary>, and anything
// with an onclick. Used to build an ACTIONABLE error when an interaction's
// target matches nothing: the agent reliably knows a label it rendered, so
// listing the real candidates turns a silent blank capture into a "did you
// mean one of these?" hint. Pure read (no clicks); falls back to value /
// aria-label / placeholder when an element has no text.
async function collectInteractiveLabels(frame) {
  return frame.evaluate((selector) => {
    const nodes = Array.from(document.querySelectorAll(selector));
    const labels = nodes
      .map((node) => {
        const text =
          (node.innerText || node.textContent || "").trim() ||
          (typeof node.value === "string" ? node.value.trim() : "") ||
          (node.getAttribute && node.getAttribute("aria-label")) ||
          (node.getAttribute && node.getAttribute("placeholder")) ||
          "";
        return String(text).trim();
      })
      .filter((label) => label.length > 0);
    return Array.from(new Set(labels)).slice(0, 20);
  }, INTERACTIVE_SELECTOR);
}

// How many candidate labels an error message may echo. Deliberately tighter
// than `collectInteractiveLabels`' own 20-label read cap: the labels are the
// USER'S page content, so every one printed is a line of their app leaked into
// the terminal. Enough to answer "did you mean one of these?", not enough to
// transcribe the page.
const CANDIDATE_LABEL_CAP = 8;

// Render the candidate labels for an error message, capped and counted. Shared
// by the no-match and action-failed paths so the echo policy lives in one place.
async function candidateLabelSummary(frame) {
  const candidates = await collectInteractiveLabels(frame);
  if (candidates.length === 0) return "(none found on page)";
  const shown = candidates.slice(0, CANDIDATE_LABEL_CAP);
  const rest = candidates.length - shown.length;
  return rest > 0 ? `${shown.join(", ")} (+${rest} more)` : shown.join(", ");
}

// Compose the "no element matched" error, branched on the form the caller
// ACTUALLY passed. Pure and string-returning so both branches are asserted
// without a browser.
//
// The substring advice ("prefer an exact CSS selector") only applies to a text
// label. Printing it at a caller who already passed `#id` contradicts its own
// input and reads as misdirection — the failure mode that sent two sessions
// hunting a selector bug when the page had simply not hydrated. The candidate
// labels ride with the text branch for the same reason: they answer "did you
// mean one of these?", a question only a text match can have asked, and every
// label printed is a line of the user's own page echoed into the terminal.
//
// A text miss on a canvas-dominated page is not a spelling problem: the label
// is painted into the canvas and is not page text at all, so an empty
// candidate list would only send the author hunting a typo. That branch names
// the canvas and the position form instead.
function noMatchGuidance({ targetDesc, matchedByText, candidateLabels, canvasDominated = false }) {
  const queryParamHint =
    `Many filter/status/sort states are also reachable directly via a ` +
    `URL query param (e.g. add "?status=active" to the path) with no ` +
    `interaction at all.`;
  if (matchedByText && canvasDominated) {
    return (
      `preview-interact: no element matched ${targetDesc}, and this page is ` +
      `canvas-dominated (it paints into a canvas with no visible page text), ` +
      `so the label is painted on the canvas and cannot be matched as text. ` +
      `Target the canvas by position instead: ` +
      `{"selector":"canvas","position":{"x":120,"y":40}} — a point in CSS ` +
      `pixels from the canvas's top-left corner, read off the frame captured ` +
      `just before this step.`
    );
  }
  if (matchedByText) {
    return (
      `preview-interact: no element matched ${targetDesc}. ` +
      `Text is matched as a case-insensitive SUBSTRING, so a misspelled or ` +
      `over-specific label matches nothing — prefer an exact/role/testid CSS ` +
      `selector (e.g. {"selector":"[data-testid=\\"save\\"]"}) for a precise ` +
      `target. ${queryParamHint} ` +
      `Candidate interactive labels: ${candidateLabels}`
    );
  }
  return (
    `preview-interact: no element matched ${targetDesc}. ` +
    `That is already an exact CSS selector, so nothing on the page matches ` +
    `it as written — confirm the element is present in THIS state (it may be ` +
    `behind a tab, dialog, or conditional render), that the id/attribute is ` +
    `spelled as the markup emits it, and that the page rendered and hydrated ` +
    `at all. ${queryParamHint}`
  );
}

// Describe the elements a substring text match resolved, so an ambiguity
// warning can name the competing controls (e.g. the preset button "Bet" vs the
// disclosure button "…or bet on"). Reads each matched element's inner text via
// Playwright's `allInnerTexts`, caps the list at 5, and trims each to a single
// short line. Pure read; degrades to a count-only description if the locator
// API or the page can't produce texts.
async function describeMatchCandidates(baseLocator, matchCount) {
  const CAP = 5;
  const MAX_LEN = 60;
  let texts = [];
  try {
    if (typeof baseLocator.allInnerTexts === "function") {
      texts = await baseLocator.allInnerTexts();
    }
  } catch (_) {
    texts = [];
  }
  const described = texts
    .map((t) => String(t).replace(/\s+/g, " ").trim())
    .filter((t) => t.length > 0)
    .slice(0, CAP)
    .map((t) => (t.length > MAX_LEN ? `${t.slice(0, MAX_LEN)}…` : t))
    .map((t) => `"${t}"`);
  if (described.length === 0) {
    return [`${matchCount} elements (text unavailable)`];
  }
  if (matchCount > described.length) {
    described.push(`…and ${matchCount - described.length} more`);
  }
  return described;
}

// Drive a single user-style interaction against the settled frame before the
// screenshot, so an interactive state (expanded accordion, open modal, filled
// field) can be captured without editing app source.
//
// The target is matched by visible `text` (preferred — the agent reliably
// knows the label it rendered) or a CSS `selector`. `action` is click / fill /
// press; `value` carries the text for `fill` or the key for `press` (e.g.
// `Enter`). On a no-match target this THROWS with the list of candidate
// interactive labels — the capture script's outer catch turns that into a
// failed capture with an actionable message, never a silent blank screenshot.
//
// Resolve a visible-text target to the element most likely intended, instead
// of blindly taking the first substring hit. A bare
// `getByText(text, { exact: false })` is a case-insensitive SUBSTRING match, so
// a label can land on a plain text node or a placeholder rather than the chip /
// button the agent meant (observed: a `"Japan"` click hit placeholder text, not
// the chip; a `"Bet"` click hit a disclosure button described "or bet on"). We
// try increasingly-loose locators in priority order and take the first that
// matches anything:
//   1. exact + interactive   (for click/press)
//   2. exact
//   3. substring + interactive   (for click/press)
//   4. substring
// so an exact, clickable element wins over a substring plain-text node. Returns
// the winning tier's locator plus its match count; when nothing matches at all,
// returns the substring locator (count 0) so the caller's zero-match error path
// still fires with its candidate-label hint.
async function resolveTextTarget(frame, text, action) {
  const preferInteractive = action === "click" || action === "press";
  const exactBase = frame.getByText(text, { exact: true });
  const substrBase = frame.getByText(text, { exact: false });

  const tiers = [];
  // `.and()` (Playwright ≥1.34) intersects two locators to the elements
  // matching both — here, the text element that is ALSO interactive. Guard on
  // its presence so a locator without `.and` degrades to text-only tiers.
  if (preferInteractive && typeof exactBase.and === "function") {
    const interactive = frame.locator(INTERACTIVE_SELECTOR);
    tiers.push(exactBase.and(interactive));
    tiers.push(exactBase);
    tiers.push(substrBase.and(interactive));
    tiers.push(substrBase);
  } else {
    tiers.push(exactBase);
    tiers.push(substrBase);
  }

  for (const loc of tiers) {
    const count = await loc.count();
    if (count > 0) {
      return { baseLocator: loc, matchCount: count };
    }
  }
  return { baseLocator: substrBase, matchCount: 0 };
}

// Pick the single element to act on from a resolved locator. When more than one
// candidate remains within the winning tier, prefer a VISIBLE element over a
// hidden one rather than acting on raw `.first()` (a hidden duplicate — an
// off-screen menu clone, an aria-hidden mirror — is almost never the intended
// target). Degrades to `.first()` when the locator API lacks a visible filter
// or no candidate is visible.
async function pickBestCandidate(baseLocator, matchCount) {
  if (matchCount <= 1) {
    return baseLocator.first();
  }
  try {
    if (typeof baseLocator.filter === "function") {
      const visible = baseLocator.filter({ visible: true });
      if ((await visible.count()) > 0) {
        return visible.first();
      }
    }
  } catch (_) {
    // Locator API without a `{ visible: true }` filter — fall through.
  }
  return baseLocator.first();
}

// The page that owns `frame` — its `mouse` and `keyboard` are page-level, and a
// locator's `boundingBox()` is already in that page's viewport coordinates, so
// a point measured from the box can be handed to `page.mouse` unchanged.
function pageOf(frame) {
  return typeof frame.page === "function" ? frame.page() : frame;
}

// `drag` / `wheel` need the target's box to turn a target-relative point into a
// viewport point. A target that is not rendered has no box, and acting at
// (0,0) instead would silently drive whatever is in the corner.
async function targetBox(locator, targetDesc) {
  if (typeof locator.scrollIntoViewIfNeeded === "function") {
    await locator.scrollIntoViewIfNeeded().catch(() => {});
  }
  const box = await locator.boundingBox();
  if (!box) {
    throw new Error(`${targetDesc} has no bounding box (not rendered or not visible)`);
  }
  return box;
}

// A target-relative point resolved to viewport coordinates, plus whether it
// lies inside the box. Positions are CSS pixels from the target's top-left, so
// a point measured off a device-pixel screenshot overshoots the box and would
// drive whatever sits beside the target; `inside` lets the caller refuse it.
// No point means the centre, which is always inside.
function pointIn(box, point) {
  if (point && typeof point.x === "number" && typeof point.y === "number") {
    const inside =
      point.x >= 0 && point.y >= 0 && point.x < box.width && point.y < box.height;
    return { x: box.x + point.x, y: box.y + point.y, inside };
  }
  return { x: box.x + box.width / 2, y: box.y + box.height / 2, inside: true };
}

// The page's device pixel ratio — how many screenshot pixels make one CSS
// pixel. `null` when the frame cannot answer, so a report never guesses.
async function devicePixelRatioOf(frame) {
  try {
    const ratio = await frame.evaluate(() => window.devicePixelRatio);
    return typeof ratio === "number" && ratio > 0 ? ratio : null;
  } catch (_) {
    return null;
  }
}

// Why a point is not where its author thought: name the target's real CSS size
// and, when screenshots are scaled, the divisor that converts a coordinate
// measured off one into the CSS pixels a position is written in.
function outsideTargetMessage(label, point, targetDesc, box, devicePixelRatio) {
  const scale =
    devicePixelRatio && devicePixelRatio !== 1
      ? `screenshots are ${devicePixelRatio}× device pixels — divide screenshot coordinates by ${devicePixelRatio}`
      : "positions are CSS pixels from the target's top-left";
  const size = `${Math.round(box.width)}×${Math.round(box.height)} CSS px`;
  return `${label} (${point.x},${point.y}) is outside ${targetDesc} (${size}; ${scale})`;
}

// A start point outside the target can never act on it, so it is refused —
// loudly, like a target that matches nothing. Flagged so `performInteraction`
// rethrows it without the candidate-labels hint, which is about a missing
// target, not a misplaced point.
async function outsideTargetError(frame, action, label, point, targetDesc, box) {
  const error = new Error(
    `preview-interact: action "${action}" refused: ` +
      outsideTargetMessage(label, point, targetDesc, box, await devicePixelRatioOf(frame)),
  );
  error.outsideTarget = true;
  return error;
}

// Where a pointer step landed, in the target's own CSS-pixel frame, beside the
// target's size — what a report needs to answer "where did the pointer go?"
// without opening a captured frame. `end` is a drag's release point.
function pointerGeometry(box, start, end) {
  const relative = (p) => ({ x: Math.round(p.x - box.x), y: Math.round(p.y - box.y) });
  const geometry = {
    targetBox: { width: Math.round(box.width), height: Math.round(box.height) },
    landedAt: relative(start),
  };
  if (end) geometry.landedTo = relative(end);
  return geometry;
}

// `click` / `hover` hand `position` to Playwright, which does not check that it
// lies inside the target — so measure the box first and refuse a point outside
// it. A position-less step aims at the centre; its box is best-effort (no box
// means no geometry, and Playwright's own actionability error stands).
async function locatorPointGeometry(frame, locator, targetDesc, action, position) {
  if (!position) {
    if (typeof locator.boundingBox !== "function") return undefined;
    const box = await locator.boundingBox().catch(() => null);
    return box ? pointerGeometry(box, pointIn(box)) : undefined;
  }
  const box = await targetBox(locator, targetDesc);
  const at = pointIn(box, position);
  if (!at.inside) {
    throw await outsideTargetError(frame, action, "position", position, targetDesc, box);
  }
  return pointerGeometry(box, at);
}

module.exports = {
  INTERACTIVE_SELECTOR,
  collectInteractiveLabels,
  candidateLabelSummary,
  noMatchGuidance,
  describeMatchCandidates,
  resolveTextTarget,
  pickBestCandidate,
  pageOf,
  targetBox,
  pointIn,
  devicePixelRatioOf,
  outsideTargetMessage,
  outsideTargetError,
  pointerGeometry,
  locatorPointGeometry,
};
