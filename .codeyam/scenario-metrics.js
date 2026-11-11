// codeyam-generated — DO NOT EDIT.
// codeyam-editor: 0.1.7  build: 283adba28f3fc30f058c87b4f92900dccc81f9e5  source-sha256: e1b0f970e834371fe7faec93943aaa33d2e9217311ebb759fe60910fff046bd0
const LOADING_MARKERS = [
  "Loading scenario...",
  "Loading tests...",
  "Loading scenarios...",
  "disconnected",
];

// `extraMarkers` are project-supplied (from stack.json `capture.loadingMarkers`)
// because an app's own loading copy ("Loading…", "Please wait") is
// app-specific and must NOT be hardcoded into the shared harness — only the
// four codeyam-harness markers above are universal. Matching is
// case-insensitive so "Loading…" and "loading…" both count; without the
// project markers a stable app loading screen looks "ready" to
// waitForStablePage and gets captured mid-hydration.
function hasLoadingMarkers(text, extraMarkers = []) {
  if (!text) return false;
  const lower = text.toLowerCase();
  const markers = LOADING_MARKERS.concat(
    Array.isArray(extraMarkers) ? extraMarkers : [],
  );
  return markers.some(
    (marker) => marker && lower.includes(String(marker).toLowerCase()),
  );
}

function hasRenderableContent(state) {
  if (!state) return false;

  // Reveal-suppression guard. A scroll-gated entrance animation starts its
  // content at `opacity:0` and reveals it via an IntersectionObserver wired
  // from the app shell. Captured in isolation (no shell), the observer never
  // fires, so the text renders into the DOM — `bodyTextLength`/`rootTextLength`
  // are non-zero — yet stays visually invisible and the screenshot is blank.
  // `visibleTextLength` is the length of text actually PAINTED to the frame
  // (computed-style opacity/visibility aware). When the DOM carries text but
  // none of it is visible AND there is no visible media, the frame is
  // near-blank: report no content so the blank gate rejects it instead of
  // waving through an empty shell. `visibleTextLength` is optional — older
  // capture configs (and stubbed test targets) omit it, in which case the
  // original DOM-presence behavior below is preserved byte-for-byte.
  const domTextLength = Math.max(
    state.bodyTextLength || 0,
    state.rootTextLength || 0,
  );
  const hasVisibleMedia =
    (state.loadedImageCount || 0) > 0 || (state.mediaBboxCount || 0) > 0;
  if (
    typeof state.visibleTextLength === "number" &&
    domTextLength > 0 &&
    state.visibleTextLength === 0 &&
    !hasVisibleMedia
  ) {
    return false;
  }

  if (
    state.rootChildCount > 0 ||
    state.rootTextLength > 0 ||
    state.bodyTextLength > 0
  ) {
    return true;
  }
  if ((state.loadedImageCount || 0) > 0) return true;
  if ((state.mediaBboxCount || 0) > 0) return true;
  return false;
}

function describeBlankReason(state) {
  if (!state) return "no content state collected";
  const parts = [];
  // Distinguish "no text in the DOM at all" from "text rendered but nothing is
  // visible" — the latter is the reveal-suppression symptom (opacity:0
  // entrance content whose observer never fired in isolation), which points
  // the author at a different fix than a genuinely empty page.
  if (
    typeof state.visibleTextLength === "number" &&
    state.bodyTextLength > 0 &&
    state.visibleTextLength === 0
  ) {
    parts.push("text rendered but not visible (reveal-suppressed?)");
  } else if (!(state.bodyTextLength > 0)) {
    parts.push("no text");
  }
  const imageCount = state.imageCount || 0;
  const loadedImageCount = state.loadedImageCount || 0;
  if (imageCount > 0 && loadedImageCount === 0) {
    parts.push(`${imageCount} unloaded image${imageCount === 1 ? "" : "s"}`);
  } else if (imageCount === 0) {
    parts.push("no images");
  }
  if (!((state.mediaBboxCount || 0) > 0)) {
    parts.push("no svg/canvas/video");
  }
  return parts.join(", ");
}

function shouldStopWaitingForImages(images, options = {}) {
  const { elapsedMs = 0, overallTimeoutMs = 5000 } = options;
  if (!Array.isArray(images) || images.length === 0) return true;
  if (elapsedMs >= overallTimeoutMs) return true;
  return images.every((img) => img && img.complete === true);
}

const ERROR_PATTERNS = [
  "not found in registry",
  "Component not found",
  "Scenario Error",
];

// The DOM attribute codeyam's own ScenarioRenderer stamps on its error and
// seed-error fallback frames. Error detection anchors on this marker rather
// than scanning the whole page body for ERROR_PATTERNS: a legitimately-mocked
// scenario whose *content* quotes one of those harness phrases (a journal entry
// describing the error component, say) must not be flagged as a failed capture.
// Arbitrary client apps that never render a codeyam ScenarioRenderer never emit
// the marker, so their pages are treated as healthy regardless of body text —
// these patterns were always codeyam-harness-specific, never generic.
const SCENARIO_ERROR_MARKER = "data-codeyam-scenario-error";

function hasErrorPatterns(text) {
  return ERROR_PATTERNS.some((pattern) => text.includes(pattern));
}

function findErrorPattern(text) {
  if (!text) return null;
  for (const pattern of ERROR_PATTERNS) {
    if (text.includes(pattern)) return pattern;
  }
  return null;
}

const ERROR_CONTEXT_RADIUS = 60;

function buildErrorContextSnippet(text, pattern) {
  if (!text || !pattern) return null;
  const index = text.indexOf(pattern);
  if (index < 0) return null;
  const start = Math.max(0, index - ERROR_CONTEXT_RADIUS);
  const end = Math.min(text.length, index + pattern.length + ERROR_CONTEXT_RADIUS);
  const slice = text.slice(start, end).replace(/\s+/g, " ").trim();
  const prefix = start > 0 ? "…" : "";
  const suffix = end < text.length ? "…" : "";
  return `${prefix}${slice}${suffix}`;
}

// Classify a scenario-error fallback into a `{ matchedPattern, contextSnippet }`
// from the marker info collected off the page. `marker` is the
// `{ reason, text }` read from the `[data-codeyam-scenario-error]` element, or
// null when no such element is present. Returns null when there is no marked
// fallback — the page is healthy and no error-content failure is raised.
//
// When the marked fallback text contains a known ERROR_PATTERN (the render-error
// path renders `Component "X" not found in registry`), that pattern is named so
// the downstream Rust classifier can still extract the component; otherwise the
// marker's `reason` attribute classifies it (the seed-error fallback, whose
// "Seed Error" copy is intentionally not an ERROR_PATTERN). Because the text is
// scoped to the fallback element — not the whole body — content elsewhere on the
// page can quote these phrases freely without tripping detection.
function findScenarioError(marker) {
  // The capture passes the `frame.evaluate` result of querying the marker
  // element: either null (no fallback rendered) or a `{reason, text}` object.
  // Anything else (a bare string, a primitive) is not a marked error — guard
  // so a non-object never reads as a present marker and false-flags the page.
  if (!marker || typeof marker !== "object") return null;
  const text = marker.text || "";
  const reason = marker.reason || "";
  const matchedPattern = findErrorPattern(text) || reason || "scenario error";
  const contextSnippet =
    buildErrorContextSnippet(text, matchedPattern) ||
    (text ? text.replace(/\s+/g, " ").trim().slice(0, 200) : null);
  return { matchedPattern, contextSnippet };
}

// Build the non-blocking "this page looks client-fetched" advisory from the two
// settle signals the capture already computes: `stableOutcome` from
// waitForStablePage (did the page settle, and was a loading marker still up at
// the cap?) and `networkOutcome` from waitForNetworkQuiet (did in-flight network
// go quiet, or did the bounded wait cap out?). Captures settle within a bounded
// window so a never-idle stream can't hang them — which means a slower
// client-side fetch lands AFTER the window and the screenshot catches the
// loading/initial state instead of the populated one. When either signal fires,
// name the cause and the two reliable fixes (server-render the data, or drive a
// props-driven isolated component scenario) so the agent reaches for those up
// front instead of rediscovering the constraint by trial and error. Returns the
// advisory string, or null when the page settled cleanly (the SSR / props-driven
// happy path — no advisory, so a healthy capture stays noise-free).
function buildSettleAdvisory(stableOutcome, networkOutcome) {
  const causes = [];
  if (
    stableOutcome &&
    stableOutcome.stabilized === false &&
    stableOutcome.hadLoadingMarkers === true
  ) {
    causes.push("a loading marker was still on the page");
  }
  if (networkOutcome && networkOutcome.quiet === false) {
    causes.push("network requests were still in flight");
  }
  if (causes.length === 0) return null;
  return (
    `When this page was captured, ${causes.join(" and ")} — it likely fetches ` +
    `its data on the client. Captures settle within a bounded window, so data ` +
    `that arrives via a client-side fetch after that window renders as the ` +
    `loading/initial state, not the populated state. To capture a populated ` +
    `state, server-render the data (SSR/RSC) or drive a props-driven isolated ` +
    `component scenario.`
  );
}

// A canvas-dominated capture: visible media (canvas/svg/video) and no visible
// text. Its DOM says nothing about whether anything was painted — an unpainted
// or black canvas still has a bounding box, so `hasRenderableContent` passes
// it — so its frame's pixels are the only honest content check. Falls back to
// the DOM text length when `visibleTextLength` was not collected.
function isCanvasDominated(state) {
  if (!state || !((state.mediaBboxCount || 0) > 0)) return false;
  const textLength =
    typeof state.visibleTextLength === "number"
      ? state.visibleTextLength
      : Math.max(state.bodyTextLength || 0, state.rootTextLength || 0);
  return textLength === 0;
}

// Mirrors `frame_has_visual_content` in
// crates/control-api/src/screenshot/frame_settle.rs, which the simulator capture
// paths use: downsample the frame's luma to CONTENT_SAMPLE_EDGE² cells and call
// it content when the spread between the darkest and brightest cell reaches
// MIN_CONTENT_LUMA_SPREAD. The constants and the Rec.709 luma weights match
// the Rust side so one frame cannot pass one and fail the other.
const CONTENT_SAMPLE_EDGE = 32;
const MIN_CONTENT_LUMA_SPREAD = 8;

// True for a usable decoded RGBA frame: `{ width, height, data }` with
// non-zero dimensions and at least 4 bytes per pixel. Every pixel measure
// below treats anything else as an empty frame.
function isDecodedFrame(image) {
  return !!(
    image &&
    image.width > 0 &&
    image.height > 0 &&
    image.data &&
    image.data.length >= image.width * image.height * 4
  );
}

// `image` is a decoded RGBA frame: `{ width, height, data }`, 4 bytes per pixel.
// An empty or malformed frame is not content.
function frameHasVisualContent(image) {
  if (!isDecodedFrame(image)) return false;
  const { width, height, data } = image;
  const cells = CONTENT_SAMPLE_EDGE;
  const sums = new Float64Array(cells * cells);
  const counts = new Uint32Array(cells * cells);
  for (let y = 0; y < height; y += 1) {
    const cy = Math.min(cells - 1, Math.floor((y * cells) / height));
    for (let x = 0; x < width; x += 1) {
      const cx = Math.min(cells - 1, Math.floor((x * cells) / width));
      const i = (y * width + x) * 4;
      const luma = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
      sums[cy * cells + cx] += luma;
      counts[cy * cells + cx] += 1;
    }
  }
  let min = 255;
  let max = 0;
  for (let c = 0; c < sums.length; c += 1) {
    if (counts[c] === 0) continue;
    const mean = sums[c] / counts[c];
    if (mean < min) min = mean;
    if (mean > max) max = mean;
  }
  return Math.round(max) - Math.round(min) >= MIN_CONTENT_LUMA_SPREAD;
}

// A pixel counts as painted when any channel differs from the frame's dominant
// colour by more than this, so a lossless frame's ±1 dithering stays unpainted.
const PAINTED_CHANNEL_DELTA = 3;

// How much a frame painted, measured against its dominant colour at native
// resolution: `{ paintedPixels, bbox }`, where `bbox` is `{ x, y, width,
// height }` around every painted pixel, or null when nothing was painted.
// `frameHasVisualContent` averages a small widget into one or two cells and
// cannot tell it from an empty frame; this can. Deliberately separate from that
// boolean (which is pinned to its Rust twin) and only worth paying for on a
// frame that already failed it. A malformed frame reads as unpainted.
function frameContentStats(image) {
  if (!isDecodedFrame(image)) return { paintedPixels: 0, bbox: null };
  const { width, height, data } = image;
  const tally = new Map();
  let dominant = 0;
  let dominantCount = 0;
  for (let i = 0; i < width * height * 4; i += 4) {
    const key = (data[i] << 16) | (data[i + 1] << 8) | data[i + 2];
    const count = (tally.get(key) || 0) + 1;
    tally.set(key, count);
    if (count > dominantCount) {
      dominant = key;
      dominantCount = count;
    }
  }
  const r = (dominant >> 16) & 0xff;
  const g = (dominant >> 8) & 0xff;
  const b = dominant & 0xff;
  let paintedPixels = 0;
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      if (
        Math.abs(data[i] - r) <= PAINTED_CHANNEL_DELTA &&
        Math.abs(data[i + 1] - g) <= PAINTED_CHANNEL_DELTA &&
        Math.abs(data[i + 2] - b) <= PAINTED_CHANNEL_DELTA
      ) {
        continue;
      }
      paintedPixels += 1;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  const bbox =
    paintedPixels === 0
      ? null
      : { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
  return { paintedPixels, bbox };
}

// Reduce a selector to the part a settled DOM can answer. Pseudo-elements
// (`::before`, `::placeholder`, legacy `:after`) and interaction-state
// pseudo-classes (`:hover`, `:focus-visible`, …) are dropped, so
// `.btn:hover::after` asks whether a `.btn` exists. Deliberately
// over-inclusive: the staleness check ignores edits only to rules that
// matched NOTHING, so counting a rule as matched can cost a recapture but
// never hides one. An emptied compound (`:hover` alone) becomes `*`.
function stripStateSelector(selector) {
  const stripped = String(selector)
    .replace(/::[\w-]+(\([^)]*\))?/g, "")
    .replace(/:(before|after|first-line|first-letter)(?![\w-])/gi, "")
    .replace(
      /:(hover|focus-visible|focus-within|focus|active|visited|target|link|any-link)(?![\w-])/gi,
      "",
    );
  return stripped
    .split(",")
    .map((part) => {
      const trimmed = part.trim();
      if (trimmed === "") return "*";
      return /[>+~]$/.test(trimmed) ? `${trimmed} *` : trimmed;
    })
    .join(", ");
}

// Runs IN THE PAGE (via `frame.evaluate`), so it is self-contained and takes
// the selector stripper as an argument rather than closing over it. Records,
// per stylesheet, which style rules matched an element in the captured DOM.
// Rules inside `@media` / `@supports` / `@container` / `@layer` are tested
// whatever their condition, so a viewport difference never under-counts.
//
// A sheet is named by Vite's `data-vite-dev-id` (an absolute source path) or
// its href's pathname; an unnamed inline `<style>` is skipped, since no
// project file can be resolved from it. Cross-origin sheets whose `cssRules`
// throw are skipped too — they are not project source. Shadow roots with their
// own styles and `adoptedStyleSheets` are invisible to this walk, so either
// marks the whole record `unsupported` and the editor falls back to digesting
// whole files. A nested style rule marks its sheet `unsupported` the same way.
function collectCssRuleMatches(strip) {
  const out = { unsupported: false, sheets: [] };
  if (document.adoptedStyleSheets && document.adoptedStyleSheets.length > 0) {
    out.unsupported = true;
  }
  for (const el of Array.from(document.querySelectorAll("*"))) {
    const root = el.shadowRoot;
    if (
      root &&
      ((root.adoptedStyleSheets && root.adoptedStyleSheets.length > 0) ||
        root.querySelector("style, link[rel~='stylesheet']"))
    ) {
      out.unsupported = true;
      break;
    }
  }
  const matches = (selectorText) => {
    try {
      return document.querySelector(strip(selectorText)) !== null;
    } catch (_) {
      return true;
    }
  };
  for (const sheet of Array.from(document.styleSheets)) {
    let rules;
    try {
      rules = sheet.cssRules;
    } catch (_) {
      continue;
    }
    const owner = sheet.ownerNode;
    const viteId =
      owner && owner.getAttribute ? owner.getAttribute("data-vite-dev-id") : null;
    let id = viteId;
    if (!id && sheet.href) {
      try {
        id = new URL(sheet.href).pathname;
      } catch (_) {
        id = null;
      }
    }
    if (!id) continue;
    const entry = { id, matched: [], unmatched: [], unsupported: false };
    const walk = (list) => {
      for (const rule of Array.from(list)) {
        if (typeof CSSStyleRule !== "undefined" && rule instanceof CSSStyleRule) {
          (matches(rule.selectorText) ? entry.matched : entry.unmatched).push(
            rule.selectorText,
          );
          if (rule.cssRules && rule.cssRules.length > 0) entry.unsupported = true;
        } else if (rule.cssRules) {
          walk(rule.cssRules);
        }
      }
    };
    walk(rules);
    out.sheets.push(entry);
  }
  return out;
}

module.exports = {
  stripStateSelector,
  collectCssRuleMatches,
  hasLoadingMarkers,
  hasRenderableContent,
  isCanvasDominated,
  isDecodedFrame,
  frameHasVisualContent,
  frameContentStats,
  CONTENT_SAMPLE_EDGE,
  MIN_CONTENT_LUMA_SPREAD,
  buildSettleAdvisory,
  describeBlankReason,
  shouldStopWaitingForImages,
  hasErrorPatterns,
  findErrorPattern,
  findScenarioError,
  buildErrorContextSnippet,
  ERROR_PATTERNS,
  SCENARIO_ERROR_MARKER,
  ERROR_CONTEXT_RADIUS,
};
