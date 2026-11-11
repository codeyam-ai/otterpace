// codeyam-generated — DO NOT EDIT.
// codeyam-editor: 0.1.7  build: 283adba28f3fc30f058c87b4f92900dccc81f9e5  source-sha256: 04879a603a70426d302141cf4efad69bece3d2790334c0b84d8126a1be4ee628
const {
  hasLoadingMarkers,
  isCanvasDominated,
  shouldStopWaitingForImages,
} = require("./scenario-metrics");
const {
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
} = require("./scenario-targeting");
const fs = require("fs");

// PROTOTYPE (improve35 capture diagnostics): append a per-phase timing line to
// a file so we can see WHERE a slow/timed-out capture spends its budget — even
// when the editor kills this script on timeout (stderr is lost then, but the
// file survives because each line is flushed synchronously). The cwd is the
// project dir (scenario_check.rs sets `.current_dir(project_dir)`), so this
// lands at `<project>/.codeyam/logs/capture-timing.log`. Diagnostics only —
// never throws, never affects the capture result.
function logCaptureTiming(phase, data) {
  try {
    const line = `[${new Date().toISOString()}] [capture-timing] phase=${phase} ${JSON.stringify(
      data,
    )}\n`;
    fs.appendFileSync(".codeyam/logs/capture-timing.log", line);
  } catch (_) {
    /* diagnostics must never break a capture */
  }
}

const net = require("net");

// Resolve a URL to the TCP {host, port} a pre-flight connect should target, or
// null when there is nothing to pre-check — an unparseable URL, or a non-http(s)
// target like `data:`/blank that the capture renders with no network origin.
// Pure (no socket) so the parse, protocol gate, and default-port rules are
// unit-tested without opening a connection.
function resolveTcpTarget(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch (_) {
    return null;
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
  return {
    host: parsed.hostname,
    port: Number(parsed.port) || (parsed.protocol === "https:" ? 443 : 80),
  };
}

// Fast pre-flight (improve35): is anything accepting TCP on the app port? A
// refused connection (the editor's reverse proxy is down) fails in milliseconds;
// without this, the iframe's `waitForLoadState("load")` hangs the FULL 30s on a
// dead origin (the observed capture failure — capture-timing showed
// navigate-iframe elapsedMs=30004, status=null). A connection that ACCEPTS is
// good enough to proceed — a slow HTTP response *after* connect is a cold
// compile, handled by the normal load wait + the editor's retry. So we only bail
// on a hard refusal/timeout, never on slowness.
async function assertAppPortReachable(url, { timeoutMs = 2500 } = {}) {
  const target = resolveTcpTarget(url);
  if (!target) return; // non-http target (data:, blank) — nothing to pre-check
  const { host, port } = target;
  const started = Date.now();
  await new Promise((resolve, reject) => {
    const socket = net.connect({ host, port });
    const finish = (err) => {
      socket.destroy();
      const elapsedMs = Date.now() - started;
      logCaptureTiming("app-port-reachable", {
        host,
        port,
        reachable: !err,
        elapsedMs,
        error: err ? err.message : null,
      });
      if (err) reject(err);
      else resolve();
    };
    socket.setTimeout(timeoutMs, () =>
      finish(
        new Error(
          `app port unreachable: TCP connect to ${host}:${port} timed out after ${timeoutMs}ms — the editor's reverse proxy is not accepting connections (proxy down?)`,
        ),
      ),
    );
    socket.once("connect", () => finish());
    socket.once("error", (e) =>
      finish(
        new Error(
          `app port unreachable: ${host}:${port} ${e.code || e.message} — is the editor's reverse proxy up? (a capture cannot render a dead app port)`,
        ),
      ),
    );
  });
}

function escapeHtmlAttribute(value) {
  return String(value).replaceAll("&", "&amp;").replaceAll('"', "&quot;");
}

// The harness background defaults to transparent so the iframe's own
// <body> background paints through — matching what users see in the Live
// Preview. Callers (via scenario-check.js) pass a concrete color when the
// UI has detected a background it wants the capture to paint behind the
// iframe, e.g. `var(--bg-deep)` from the editor shell.
// The iframe is named `codeyam-preview` (CODEYAM_PREVIEW_FRAME_NAME in
// ui/src/helpers/previewMockPolicy.ts) so a framed editor page knows it is
// inside codeyam's own capture, not a hosting IDE's pane.
function buildIframeHarness(url, { background = "transparent" } = {}) {
  const escapedUrl = escapeHtmlAttribute(url);
  const bg = String(background);
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <style>
      html, body {
        margin: 0;
        width: 100%;
        height: 100%;
        overflow: hidden;
        background: ${bg};
      }

      iframe {
        display: block;
        width: 100%;
        height: 100%;
        border: 0;
        background: ${bg};
      }
    </style>
  </head>
  <body>
    <iframe id="scenario-frame" name="codeyam-preview" title="Scenario Preview" src="${escapedUrl}"></iframe>
  </body>
</html>`;
}

const path = require("path");

// The reserved route the editor serves the secure-context iframe harness from.
// Mirrors `HARNESS_PATH` in crates/control-api/src/preview_proxy_route.rs — the
// canonical source of the harness markup now lives in that Rust handler; the
// `buildIframeHarness` template above survives only as the degraded fallback
// below for when the harness origin can't be resolved.
const HARNESS_PATH = "/__codeyam_harness";

// Read `.codeyam/server-state.json` (cwd is the project dir — see the timing
// log note above) and return its parsed object, or null when it is absent.
function defaultReadServerState() {
  const statePath = path.join(process.cwd(), ".codeyam", "server-state.json");
  if (!fs.existsSync(statePath)) return null;
  return JSON.parse(fs.readFileSync(statePath, "utf8"));
}

// Resolve the loopback origin that serves the iframe-harness route. The harness
// is mounted on the editor's control-api listener, whose port is recorded in
// `.codeyam/server-state.json` as `controlPort` (the same file the top-level
// loader already reads for `appPort`). Returns `http://127.0.0.1:<controlPort>`
// — a secure context the nested iframe inherits, exactly as `localhost` is — or
// null when the state file is missing/unreadable, in which case the caller falls
// back to the legacy in-page `setContent` harness. `readStateFile` is injectable
// so the resolver is unit-testable without disk.
//
// The HOST is taken from `targetUrl` — the URL the iframe will load — and only
// the port comes from server-state. That mirroring is load-bearing, because the
// two capture modes address the editor by different loopback spellings:
// `/__codeyam_preview` captures are pinned to `127.0.0.1` (PROXY_CAPTURE_LOOPBACK
// in handlers.rs, matching the forwarder's own pinning) while direct app-port
// captures use `localhost`. `localhost` and `127.0.0.1` are DIFFERENT sites to
// the cookie jar, so whenever the harness host and the iframe host disagree the
// nested load is cross-site — and the `cy_session` cookie is `SameSite=Lax`,
// which rides top-level navigations only. It is therefore withheld from the
// iframe request (and from the `/api/*` calls the framed page makes), and the
// token-gated routes answer 401 on a non-loopback bind.
//
// Hardcoding EITHER spelling only moves the failure between the two modes:
// `localhost` 401s every `/__codeyam_preview` capture, `127.0.0.1` 401s the
// framed page's own `/api/scenarios` + `/api/render-environment` calls. Raising
// the cookie to `SameSite=None` fixes neither — Chromium rejects `None` without
// `Secure`, and these origins are plain http. Mirroring the target's host is what
// keeps the harness same-site in both modes, which is also the same-origin model
// the `/__codeyam_preview` subpath proxy exists to provide.
//
// `targetUrl` omitted or unparseable falls back to `127.0.0.1`, the spelling the
// proxy-route capture (the token-gated one) uses.
function resolveHarnessOrigin({
  readStateFile = defaultReadServerState,
  targetUrl = null,
} = {}) {
  try {
    const state = readStateFile();
    const port = state && state.controlPort;
    if (typeof port === "number" && port > 0) {
      let host = "127.0.0.1";
      if (targetUrl) {
        try {
          host = new URL(targetUrl).hostname || host;
        } catch (_) {
          /* unparseable target — keep the proxy-route default */
        }
      }
      return `http://${host}:${port}`;
    }
  } catch (_) {
    /* missing/unreadable state — fall back to setContent */
  }
  return null;
}

// Build the top-level harness URL for a scenario `url` and background. The
// editor-served harness document embeds `src` as the iframe URL, so the nested
// scenario inherits the harness's secure context. The background rides along as
// `bg`. Pure — `URLSearchParams` does the percent-encoding so a scenario URL
// with its own query string survives intact. Pure.
function buildHarnessUrl(harnessOrigin, url, background) {
  const params = new URLSearchParams({ src: url });
  if (background != null && background !== "") {
    params.set("bg", String(background));
  }
  return `${harnessOrigin}${HARNESS_PATH}?${params.toString()}`;
}

async function collectContentState(target) {
  return target.evaluate(() => {
    const root = document.getElementById("root");
    const imgs = Array.from(document.images || []);
    const loadedImageCount = imgs.filter(
      (img) => img.complete && img.naturalWidth > 0,
    ).length;
    // Media is counted inside open shadow roots too. `querySelectorAll` stops
    // at a shadow boundary, and an app that paints inside a web component —
    // Flutter web draws its canvas under <flutter-view>'s shadow root — would
    // otherwise read as zero media and zero text, failing the blank gate on a
    // fully rendered frame.
    const scopes = [document];
    for (let i = 0; i < scopes.length; i++) {
      for (const el of scopes[i].querySelectorAll("*")) {
        if (el.shadowRoot) scopes.push(el.shadowRoot);
      }
    }
    const mediaSelectors = ["svg", "canvas", "video"];
    let mediaBboxCount = 0;
    for (const selector of mediaSelectors) {
      const nodes = scopes.flatMap((scope) =>
        Array.from(scope.querySelectorAll(selector)),
      );
      for (const node of nodes) {
        const rect = node.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          mediaBboxCount += 1;
        }
      }
    }
    return {
      bodyTextLength: document.body ? document.body.innerText.trim().length : 0,
      rootChildCount: root ? root.childElementCount : 0,
      rootTextLength: root ? (root.textContent || "").trim().length : 0,
      imageCount: imgs.length,
      loadedImageCount,
      mediaBboxCount,
    };
  });
}

// Trip scroll-gated entrance animations before capture. Many web/visual
// stacks reveal sections with an IntersectionObserver that flips an
// `opacity:0` element to its final state once it scrolls into view. Captured
// in isolation — where the app shell that wires those observers is absent —
// or on a tall page captured at a fixed viewport, the observers never fire and
// the content stays invisible, so the screenshot is blank. Scroll the document
// end-to-end in steps to trip every observer, then return to the top so the
// captured frame starts where the app does. Stack-agnostic: it drives the same
// scroll a real user would, touching no framework API. A frame whose document
// fits in (or is shorter than) the viewport still gets a nudge-and-restore so a
// single-screen page's scroll-triggered reveal fires too. Returns the measured
// document height (0 when there is nothing to scroll).
async function scrollThroughDocument(target) {
  return target.evaluate(() => {
    const doc = document.scrollingElement || document.documentElement;
    const total = Math.max(
      (doc && doc.scrollHeight) || 0,
      document.body ? document.body.scrollHeight : 0,
    );
    if (typeof window.scrollTo !== "function") return total;
    const viewport = window.innerHeight || 0;
    if (total <= viewport || total === 0) {
      // Even a single-viewport page may gate a reveal on the first scroll
      // event; a nudge-and-restore fires those observers without moving the
      // captured frame off the top.
      window.scrollTo(0, 1);
      window.scrollTo(0, 0);
      return total;
    }
    const stride = Math.max(1, Math.floor((total - viewport) / 8));
    for (let y = 0; y <= total; y += stride) {
      window.scrollTo(0, y);
    }
    window.scrollTo(0, 0);
    return total;
  });
}

// Sum the length of text that is actually PAINTED to the frame — text whose
// element ancestor chain is not hidden by `display:none` / `visibility:hidden`
// and is not collapsed to `opacity:0`, and which occupies a non-zero box. This
// is the signal the blank-frame gate uses to catch a reveal-suppressed capture:
// a frame whose DOM rendered text (so `bodyTextLength > 0`) but whose every
// section is still sitting at the `opacity:0` start of an entrance animation
// that never fired, leaving the screenshot blank. Counts text mid-transition
// (any opacity above exactly 0) as visible, so a reveal that has begun is not
// flagged. Returns `undefined` when the DOM-walking / computed-style APIs are
// unavailable (e.g. a stubbed test target) so callers fall back to the legacy
// DOM-presence behavior rather than treating an un-measurable frame as blank.
async function collectVisibleTextLength(target) {
  return target.evaluate(() => {
    if (
      typeof document.createTreeWalker !== "function" ||
      typeof window.getComputedStyle !== "function" ||
      typeof NodeFilter === "undefined"
    ) {
      return undefined;
    }
    const root = document.body || document.documentElement;
    if (!root) return 0;
    const isHidden = (el) => {
      for (
        let node = el;
        node && node.nodeType === 1;
        node = node.parentElement
      ) {
        const style = window.getComputedStyle(node);
        if (!style) continue;
        if (style.display === "none" || style.visibility === "hidden")
          return true;
        if (parseFloat(style.opacity) === 0) return true;
      }
      return false;
    };
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let total = 0;
    let node;
    while ((node = walker.nextNode())) {
      const text = (node.nodeValue || "").trim();
      if (!text) continue;
      const el = node.parentElement;
      if (!el || isHidden(el)) continue;
      const rect = el.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) continue;
      total += text.length;
    }
    return total;
  });
}

// Inject a capture-only stylesheet that snaps entrance animations to their
// FINAL frame: remove animation/transition timing, then reveal the elements an
// entrance animation left INVISIBLE. This is the belt to
// `scrollThroughDocument`'s suspenders — it covers pure-CSS keyframe entrances
// that are mid-flight or stuck at an `opacity:0` start state even after the
// observers fired. It targets the generic CSS symptom, not any framework's
// reveal class, so it works for any stack. The caller gates this OFF when a
// scenario declares an interactive state, so an intentionally animated /
// collapsed interactive frame is never clobbered. Idempotent (a single injected
// style id) and best-effort. Returns true when the style is present after the
// call.
//
// The reveal is conditional on ANIMATION EVIDENCE, not on transparency alone:
// an element is revealed only when, before the reset lands, an animation or a
// transition was actually holding it back. An element resting at `opacity: 0`
// with neither is hidden BY INTENT — a closed dropdown, a hover-only action, an
// empty toast slot, an off-screen drawer — and is left exactly as the app
// rendered it. Elements carrying an explicit hidden-intent signal
// (`aria-hidden="true"`, `inert`, or `pointer-events: none`), on themselves or
// on an ancestor, are skipped even when a transition is declared — that is the
// resting shape of a closed popover which animates on open.
//
// It is never a blanket `opacity: 1 !important` / `transform: none !important`
// over `*`. A blanket rule cannot tell an entrance animation's `opacity: 0` from
// DELIBERATE, resting state — a disabled control's dim, a muted row, a
// collapsed chevron's rotation — so it silently flattened every one of them out
// of every screenshot the capture pipeline produced. Two scenarios differing
// only in such a state then captured byte-identically and collided in the
// distinct-capture gate, and the collision was unfixable in the component: the
// state rendered correctly in a real browser (verified: computed opacity 0.4 vs
// 1) and was erased only at capture time. Anything already visible is now left
// exactly as the app rendered it.
//
// The reveal's TRANSFORM half additionally stops at the SVG boundary, because a
// CSS `transform` overrides the SVG `transform` presentation attribute: inside
// an `<svg>` it erases the static geometry that CONSTRUCTS the drawing instead
// of neutralizing an entrance animation, so a revealed SVG node lands on the
// origin. Invisible SVG nodes are therefore revealed in place — opacity forced,
// transform left alone. See the loop below for why the boundary is
// `ownerSVGElement` rather than `closest("svg")`.
async function forceFinalVisualState(target) {
  return target.evaluate(() => {
    const STYLE_ID = "__codeyam_force_final_state";
    if (
      typeof document.getElementById === "function" &&
      document.getElementById(STYLE_ID)
    ) {
      return true;
    }
    if (typeof document.createElement !== "function") return false;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    // Temporal properties only — these carry no resting state, so removing
    // them cannot erase anything the app meant to show.
    style.textContent =
      "*, *::before, *::after {" +
      "animation: none !important;" +
      "transition: none !important;" +
      "}";
    const head = document.head || document.documentElement;
    if (!head || typeof head.appendChild !== "function") return false;

    // Which elements is an animation or a transition ACTUALLY holding back?
    // Snapshot that BEFORE the stylesheet lands, because injecting it destroys
    // the evidence: `animation: none` / `transition: none` clears
    // `animationName`, empties the running-animation list, and zeroes every
    // duration. Only elements in this set are eligible for the reveal below.
    const isAnimationHeld = (el) => {
      let animations = null;
      if (typeof el.getAnimations === "function") {
        try {
          animations = el.getAnimations();
        } catch (_) {
          animations = null;
        }
      }
      if (animations && animations.length > 0) return true;
      // No `getAnimations` (older engines) falls through to the computed-style
      // evidence below — never to "reveal every invisible element".
      let computed = null;
      try {
        computed = getComputedStyle(el);
      } catch (_) {
        return false;
      }
      if (!computed) return false;
      const animationName = computed.animationName;
      if (
        typeof animationName === "string" &&
        animationName !== "" &&
        animationName !== "none"
      ) {
        return true;
      }
      const properties = computed.transitionProperty;
      if (
        typeof properties !== "string" ||
        properties === "" ||
        properties === "none"
      ) {
        return false;
      }
      const coversVisibility = properties
        .split(",")
        .map((property) => property.trim())
        .some(
          (property) =>
            property === "opacity" ||
            property === "transform" ||
            property === "all",
        );
      if (!coversVisibility) return false;
      const durations = computed.transitionDuration;
      if (typeof durations !== "string") return false;
      // A declared transition with a zero duration animates nothing, so it is
      // not holding anything back.
      return durations.split(",").some((duration) => parseFloat(duration) > 0);
    };

    // Explicit "this is hidden on purpose" signals, which outrank animation
    // evidence. A closed popover carries its open-transition while resting
    // closed, so a transition alone cannot distinguish it from an entrance the
    // capture should finish. An ancestor counts: hiding a whole subtree is the
    // common spelling.
    const hasHiddenIntent = (el, computed) => {
      if (computed && computed.pointerEvents === "none") return true;
      if (typeof el.closest === "function") {
        try {
          if (el.closest('[aria-hidden="true"], [inert]')) return true;
        } catch (_) {
          // Fall through to the self-only checks below.
        }
      }
      if (el.inert === true) return true;
      if (
        typeof el.getAttribute === "function" &&
        el.getAttribute("aria-hidden") === "true"
      ) {
        return true;
      }
      return false;
    };

    const heldByAnimation = new Set();
    if (typeof document.querySelectorAll === "function") {
      for (const el of document.querySelectorAll("*")) {
        if (isAnimationHeld(el)) heldByAnimation.add(el);
      }
    }

    head.appendChild(style);

    // With animations disabled above, an element held back by an entrance
    // animation now computes to its pre-animation resting state — typically
    // `opacity: 0`, often paired with a translate/scale that parks it offscreen.
    // Reveal exactly those, and only those: membership in the pre-reset
    // `heldByAnimation` snapshot is what separates them from UI the app is
    // deliberately holding at `opacity: 0`, which stays hidden. An element at
    // any visible opacity is left untouched either way.
    //
    // The transform half of the reveal STOPS at the SVG boundary. A CSS
    // `transform` overrides the SVG `transform` presentation attribute, so
    // inside an `<svg>` a forced `transform: none` does not neutralize an
    // entrance animation — it erases the static rotate/translate/scale that
    // CONSTRUCTS the drawing, revealing the node collapsed on the origin. The
    // opacity half is still right there (a node at ~0 shows nothing either
    // way), so an invisible SVG node is revealed IN PLACE. The boundary test is
    // `ownerSVGElement` and NOT `closest("svg")`: HTML inside a
    // `<foreignObject>` is a real HTMLElement with no `ownerSVGElement`, so it
    // keeps the full reveal — `closest("svg")` would silently strand its
    // genuine CSS entrance transform.
    if (typeof document.querySelectorAll !== "function") return true;
    const INVISIBLE_EPSILON = 0.01;
    for (const el of document.querySelectorAll("*")) {
      let computed = null;
      try {
        computed = getComputedStyle(el);
      } catch (_) {
        continue;
      }
      if (!computed) continue;
      const opacity = parseFloat(computed.opacity);
      if (!Number.isFinite(opacity) || opacity > INVISIBLE_EPSILON) continue;
      if (!heldByAnimation.has(el)) continue;
      if (hasHiddenIntent(el, computed)) continue;
      if (!el.style || typeof el.style.setProperty !== "function") continue;
      const inSvg =
        el.ownerSVGElement != null ||
        (typeof el.tagName === "string" && el.tagName.toLowerCase() === "svg");
      el.style.setProperty("opacity", "1", "important");
      if (!inSvg) el.style.setProperty("transform", "none", "important");
    }
    return true;
  });
}

// Center the isolated-component wrapper in the viewport before the shot.
//
// The capture pipeline always shoots the full viewport (`page.screenshot({
// fullPage: false })`) and never an element clip, so an isolation page that
// does not center its own component strands it in the top-left corner of every
// frame. Next.js does this in its isolation layout and the query-param stacks
// do it in `.codeyam/harness/isolate.tsx`, but the server-rendered scaffolds
// historically did not — and neither do pages hand-authored before that was
// fixed. This pass closes the gap at capture time, for any stack.
//
// It MEASURES rather than assumes: a wrapper that is already centered is left
// alone, so pages that already do the right thing are byte-identical. The
// `#codeyam-capture` marker (the cross-stack isolation convention; expo emits
// it via `nativeID`) is the gate, so an ordinary route capture is never
// touched. Centering is applied to `<body>` and to each ancestor strictly
// between body and the wrapper — never to the wrapper itself, which frequently
// carries the component's own padding/background and must keep its own box.
// Each axis independently falls back to `flex-start` when the wrapper overflows
// the viewport, so an oversized component loses its bottom/right edge rather
// than being clipped symmetrically out of its top/left one.
//
// Idempotent (a single injected style id), best-effort, and returns a small
// result object describing what it did.
async function centerCaptureWrapper(target) {
  return target.evaluate(() => {
    const STYLE_ID = "__codeyam_center_capture";
    const ANCESTOR_CLASS = "__codeyam-center-ancestor";
    // Subpixel layout and fractional scrollbar widths make exact gap equality
    // unreliable; a couple of px of slop keeps already-centered pages on the
    // no-op branch.
    const TOLERANCE_PX = 2;

    if (typeof document.getElementById !== "function") {
      return { applied: false, reason: "no-dom" };
    }
    if (document.getElementById(STYLE_ID)) {
      return { applied: false, reason: "already-applied" };
    }
    const wrapper = document.getElementById("codeyam-capture");
    if (!wrapper || typeof wrapper.getBoundingClientRect !== "function") {
      return { applied: false, reason: "no-capture-marker" };
    }

    const rect = wrapper.getBoundingClientRect();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;

    const leftGap = rect.left;
    const rightGap = viewportWidth - rect.right;
    const topGap = rect.top;
    const bottomGap = viewportHeight - rect.bottom;

    const fitsHorizontally = rect.width <= viewportWidth;
    const fitsVertically = rect.height <= viewportHeight;
    const centeredHorizontally =
      fitsHorizontally && Math.abs(leftGap - rightGap) <= TOLERANCE_PX;
    const centeredVertically =
      fitsVertically && Math.abs(topGap - bottomGap) <= TOLERANCE_PX;

    if (centeredHorizontally && centeredVertically) {
      return { applied: false, reason: "already-centered" };
    }

    const horizontal = fitsHorizontally ? "center" : "flex-start";
    const vertical = fitsVertically ? "center" : "flex-start";

    // Stamp the ancestor chain so the injected rule targets exactly the
    // elements between <body> and the wrapper and cannot leak elsewhere.
    let node = wrapper.parentElement;
    while (node && node !== document.body) {
      if (node.classList && typeof node.classList.add === "function") {
        node.classList.add(ANCESTOR_CLASS);
      }
      node = node.parentElement;
    }

    if (typeof document.createElement !== "function") {
      return { applied: false, reason: "no-dom" };
    }
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent =
      "body, ." +
      ANCESTOR_CLASS +
      " {" +
      "margin: 0;" +
      "min-height: 100vh;" +
      "display: flex;" +
      "align-items: " +
      vertical +
      ";" +
      "justify-content: " +
      horizontal +
      ";" +
      "}";
    const head = document.head || document.documentElement;
    if (!head || typeof head.appendChild !== "function") {
      return { applied: false, reason: "no-dom" };
    }
    head.appendChild(style);
    return { applied: true, horizontal, vertical };
  });
}

async function collectImageStates(target) {
  return target.evaluate(() =>
    Array.from(document.images || []).map((img) => ({
      complete: img.complete,
      naturalWidth: img.naturalWidth,
      src: img.currentSrc || img.src || "",
    })),
  );
}

async function waitForImagesSettled(
  target,
  { overallTimeoutMs = 5000, pollIntervalMs = 100 } = {},
) {
  const started = Date.now();
  let images = await collectImageStates(target);
  while (
    !shouldStopWaitingForImages(images, {
      elapsedMs: Date.now() - started,
      overallTimeoutMs,
    })
  ) {
    await new Promise((r) => setTimeout(r, pollIntervalMs));
    images = await collectImageStates(target);
  }
  const elapsedMs = Date.now() - started;
  const allComplete = images.every((img) => img && img.complete === true);
  const incompleteSrcs = images
    .filter((img) => !img || img.complete !== true || !(img.naturalWidth > 0))
    .map((img) => (img && img.src) || "")
    .slice(0, 6);
  logCaptureTiming("images-settled", {
    elapsedMs,
    settled: allComplete,
    total: images.length,
    incompleteCount: incompleteSrcs.length,
    incompleteSrcs,
    overallTimeoutMs,
  });
  return { settled: allComplete, images, elapsedMs };
}

async function waitForAnimationsSettled(
  target,
  { timeoutMs = 2000, pollIntervalMs = 100 } = {},
) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const runningCount = await target.evaluate(() =>
      document
        .getAnimations()
        .filter((a) => a.playState === "running").length,
    );
    if (runningCount === 0) {
      return { settled: true, elapsedMs: Date.now() - started };
    }
    await new Promise((r) => setTimeout(r, pollIntervalMs));
  }
  return { settled: false, elapsedMs: Date.now() - started };
}

// Track in-flight network requests on a Playwright page so a capture can wait
// for client-side data fetches to settle before screenshotting. The
// resource-timing API (`performance.getEntriesByType("resource")`) only records
// COMPLETED requests, so it cannot see a fetch that is still in flight — the
// exact window where a client-fetch page shows a loading skeleton. We count
// request starts against finishes/failures instead. Returns a live view:
// `inFlight()` is the current outstanding count and `lastActivityMs()` is the
// timestamp of the most recent request start OR completion (0 when the page has
// made no requests since the tracker attached). Attach BEFORE navigation so
// every request is counted. Stack-agnostic — it observes raw HTTP activity, not
// any framework's fetch wrapper.
function createNetworkTracker(page) {
  let inFlight = 0;
  let lastActivityMs = 0;
  const bump = () => {
    lastActivityMs = Date.now();
  };
  if (page && typeof page.on === "function") {
    page.on("request", () => {
      inFlight += 1;
      bump();
    });
    const settle = () => {
      inFlight = Math.max(0, inFlight - 1);
      bump();
    };
    page.on("requestfinished", settle);
    page.on("requestfailed", settle);
  }
  return {
    inFlight: () => inFlight,
    lastActivityMs: () => lastActivityMs,
  };
}

// Bounded network-quiet wait: after the DOM is stable a client-side data fetch
// can still be in flight — the loading skeleton is gone but the fetched rows
// haven't replaced it yet, so a screenshot here catches the in-between frame.
// Wait until no request has been outstanding for `quietWindowMs`, hard-capped at
// `overallTimeoutMs`. Two properties matter:
//   - A page that made NO requests (lastActivityMs stays 0) is already quiet and
//     returns on the first poll, so server-rendered captures incur no extra wait.
//   - A streaming / long-poll endpoint that never goes idle hits the cap and the
//     caller captures anyway — the wait can never hang the capture.
async function waitForNetworkQuiet(
  tracker,
  { quietWindowMs = 500, overallTimeoutMs = 5000, pollIntervalMs = 100 } = {},
) {
  const started = Date.now();
  while (Date.now() - started < overallTimeoutMs) {
    const idleForMs = Date.now() - tracker.lastActivityMs();
    if (tracker.inFlight() === 0 && idleForMs >= quietWindowMs) {
      const elapsedMs = Date.now() - started;
      logCaptureTiming("network-quiet", { outcome: "quiet", elapsedMs });
      return { quiet: true, elapsedMs };
    }
    await new Promise((r) => setTimeout(r, pollIntervalMs));
  }
  const elapsedMs = Date.now() - started;
  logCaptureTiming("network-quiet", {
    outcome: "capped",
    elapsedMs,
    inFlight: tracker.inFlight(),
  });
  return { quiet: false, elapsedMs };
}

// `loadingMarkers` are the project's app-specific loading strings (from
// stack.json `capture.loadingMarkers`); they extend the codeyam-harness
// defaults so a stable-but-still-loading app screen counts as "not ready"
// and the loop keeps waiting instead of capturing the loading flash.
//
// `confirmOnly` is for a page whose app already signalled ready (see
// `waitForReadySignal`). The signal answers "has it painted?", so a single
// sample, taken 100 ms in rather than 500, only confirms that no loading marker
// is up and the root is painted. It does not wait for two identical polls,
// which put a 1.5 s floor under every capture.
async function waitForStablePage(
  page,
  target,
  timeoutMs = 10000,
  loadingMarkers = [],
  { confirmOnly = false } = {},
) {
  const started = Date.now();
  const pollIntervalMs = confirmOnly ? 100 : 500;
  const requiredStableSamples = confirmOnly ? 1 : 2;
  let lastHtml = "";
  let stableCount = 0;
  let lastHadLoadingMarkers = false;
  let lastHtmlChanged = false;

  while (Date.now() - started < timeoutMs) {
    await page.waitForTimeout(pollIntervalMs);

    const pageState = await target.evaluate(() => {
      const getById = document.getElementById;
      const root =
        typeof getById === "function" ? document.getElementById("root") : null;
      return {
        bodyText: document.body?.innerText ?? "",
        html: document.body?.innerHTML ?? "",
        // Whether the SPA mount point exists AND has painted anything. An
        // existing-but-empty `<div id="root">` is the pre-paint window of a
        // slow-first-paint scenario (e.g. a live-session app that spends a few
        // seconds connecting before the gate UI mounts). `rootExists` lets us
        // distinguish that from a mid-redirect/teardown `null` body, where
        // there is no root to wait on and a stable-empty page is legitimately
        // settled.
        rootExists: !!root,
        rootChildCount: root ? root.childElementCount : 0,
      };
    });

    lastHadLoadingMarkers = hasLoadingMarkers(pageState.bodyText, loadingMarkers);
    lastHtmlChanged = pageState.html !== lastHtml;

    // A mounted-but-unpainted root is "still loading", not "settled": the HTML
    // can sit byte-stable for a second or two while the SPA boots, which would
    // otherwise satisfy the stability check and capture a blank frame before
    // first paint. Treat an existing root with zero children AND no body text
    // as not-ready so the loop keeps polling until the app actually paints (or
    // the overall timeout fires, by which point real content is present). A
    // `null` body (rootExists=false) is unaffected — it stays trivially stable.
    const rootUnpainted =
      pageState.rootExists &&
      pageState.rootChildCount === 0 &&
      (pageState.bodyText ?? "").trim().length === 0;

    if (!lastHadLoadingMarkers && (confirmOnly || !lastHtmlChanged) && !rootUnpainted) {
      stableCount += 1;
      if (stableCount >= requiredStableSamples) {
        const remaining = () => Math.max(0, timeoutMs - (Date.now() - started));
        await waitForAnimationsSettled(target, {
          timeoutMs: Math.min(2000, remaining()),
        });
        await waitForImagesSettled(target, { overallTimeoutMs: remaining() });
        logCaptureTiming("stable-page", {
          outcome: "stabilized",
          elapsedMs: Date.now() - started,
        });
        return { stabilized: true, hadLoadingMarkers: false };
      }
    } else {
      stableCount = 0;
    }

    lastHtml = pageState.html;
  }
  // Hit the cap without stabilizing — record WHY: a persistent loading marker
  // (app stuck) vs HTML still mutating each poll (HMR / animation / re-render).
  // The returned `hadLoadingMarkers` is the signal the capture advisory keys
  // off: a marker still on screen at the cap means the page never finished its
  // (likely client-side) load, so the screenshot caught its loading state.
  logCaptureTiming("stable-page", {
    outcome: "timed-out",
    elapsedMs: Date.now() - started,
    timeoutMs,
    lastHadLoadingMarkers,
    lastHtmlStillChanging: lastHtmlChanged,
  });
  return { stabilized: false, hadLoadingMarkers: lastHadLoadingMarkers };
}

// Poll an app-declared ready-signal expression (stack.json
// `capture.readySignal`) in `target` until it is truthy or `timeoutMs` elapses.
// This is how a canvas app says "first frame painted": its pixels never move
// `innerHTML`, so `waitForStablePage` reads it as settled before the wasm has
// drawn anything. An expression that throws (the app global not yet defined)
// counts as not-ready rather than failing the wait. Never throws; the caller
// turns `ready: false` into a capture issue.
async function waitForReadySignal(target, signal, timeoutMs) {
  if (!signal) return { awaited: false, ready: true, elapsedMs: 0 };
  const started = Date.now();
  const guarded = `(() => { try { return !!(${signal}); } catch (_) { return false; } })()`;
  try {
    await target.waitForFunction(guarded, undefined, {
      timeout: timeoutMs,
      polling: 100,
    });
    const elapsedMs = Date.now() - started;
    logCaptureTiming("ready-signal", { outcome: "ready", elapsedMs });
    return { awaited: true, ready: true, elapsedMs };
  } catch (_) {
    const elapsedMs = Date.now() - started;
    logCaptureTiming("ready-signal", { outcome: "timed-out", elapsedMs, timeoutMs });
    return { awaited: true, ready: false, elapsedMs };
  }
}

// Start watching for `frame` to navigate, from the moment its ready signal
// arrived. A navigation after that point means something reloaded the page
// under the capture (a dev server's live reload): the frame about to be shot is
// no longer the one that signalled ready. Returns `{ navigated() }`, read just
// before the screenshot. A page that cannot report navigations (a stubbed test
// target) reads as never navigated.
function watchNavigationAfterReady(page, frame) {
  let navigated = false;
  if (page && typeof page.on === "function") {
    page.on("framenavigated", (navigatedFrame) => {
      if (navigatedFrame === frame) navigated = true;
    });
  }
  return { navigated: () => navigated };
}

// `preflight` is injectable so unit tests that drive a mock page can stay
// network-free; production callers use the default real reachability check.
async function loadScenarioInIframe(
  page,
  url,
  { background, preflight = assertAppPortReachable, harnessOrigin } = {},
) {
  await preflight(url);
  // `undefined` (the default) means "resolve from server-state"; an explicit
  // value (including `null`) is honored as-is so tests can force either path.
  const resolvedHarnessOrigin =
    harnessOrigin !== undefined ? harnessOrigin : resolveHarnessOrigin();
  const navStarted = Date.now();
  const responsePromise = page
    .waitForResponse(
      (response) =>
        response.request().resourceType() === "document" &&
        response.url() === url,
      { timeout: 30000 },
    )
    .catch(() => null);

  if (resolvedHarnessOrigin) {
    // Navigate the page TOP-LEVEL to the harness document served from the
    // editor's `localhost` origin, so the ancestor document is a secure context
    // and the nested scenario iframe inherits it (the Sveltia-class fix). The
    // inner iframe `src` is still `url`, so the document-response probe above is
    // unchanged.
    const harnessUrl = buildHarnessUrl(resolvedHarnessOrigin, url, background);
    const harnessResponse = await page.goto(harnessUrl, {
      waitUntil: "domcontentloaded",
    });
    // Fail loudly on a fail-closed harness-auth rejection BEFORE the blind 30s
    // `#scenario-frame` wait below. On a non-loopback (0.0.0.0 / cloud) bind the
    // harness control-API route is session-token-gated; a generated
    // `.codeyam/capture.js` (or an editor binary) that predates the `cy_session`
    // cookie injection navigates without a token -> the server refuses the
    // request with 401 -> the harness document never renders -> every component
    // scenario times out on `#scenario-frame` with a generic Playwright error
    // that hides the real cause. Surfacing the 401 here turns that blind timeout
    // into a one-line root cause on the very first failing capture, naming both
    // fixes. (Route/page scenarios navigate top-level to the un-gated app proxy,
    // so they never hit this path.)
    if (harnessResponse && harnessResponse.status() === 401) {
      throw new Error(
        `Capture harness route ${harnessUrl} returned 401 (fail-closed ` +
          `session-token auth on a non-loopback bind). The capture script did not ` +
          `send the \`cy_session\` token — most often a generated ` +
          `\`.codeyam/capture.js\` (or an editor binary) that predates session-token ` +
          `injection. Fixes: refresh the editor binary on this VM, or set ` +
          `\`CODEYAM_INSECURE_BIND=1\` and restart the editor.`,
      );
    }
  } else {
    // Degraded fallback: no resolvable harness origin (server-state missing), so
    // use the legacy in-page harness. The top-level document is then
    // `about:blank` — NOT a secure context — so a secure-context-gated app may
    // refuse to mount, but every non-secure-context scenario captures exactly as
    // before.
    await page.setContent(buildIframeHarness(url, { background }), {
      waitUntil: "domcontentloaded",
    });
  }

  const frameHandle = await page.waitForSelector("#scenario-frame", {
    state: "attached",
    timeout: 30000,
  });
  const frame = await frameHandle.contentFrame();
  if (!frame) {
    throw new Error("Scenario iframe did not attach");
  }

  await frame.waitForLoadState("load", { timeout: 30000 });
  const response = await responsePromise;
  logCaptureTiming("navigate-iframe", {
    elapsedMs: Date.now() - navStarted,
    status: response ? response.status() : null,
    url,
  });
  return { frame, response };
}

// Load the scenario as a top-level navigation instead of embedding it in
// the iframe harness. A top-level document is a first-party context, so a
// `SameSite=Lax` session cookie is sent on the navigation — which is what
// auth-gated application routes need to render the authenticated page
// rather than redirecting to /login. The returned `frame` is the page's
// main frame so callers can treat it uniformly with the iframe path
// (`frame.url()`, `frame.evaluate(...)`, `waitForStablePage(page, frame)`).
async function loadScenarioTopLevel(
  page,
  url,
  { preflight = assertAppPortReachable } = {},
) {
  await preflight(url);
  const navStarted = Date.now();
  try {
    const response = await page.goto(url, {
      waitUntil: "load",
      timeout: 30000,
    });
    logCaptureTiming("navigate-toplevel", {
      elapsedMs: Date.now() - navStarted,
      status: response ? response.status() : null,
      url,
    });
    return { frame: page.mainFrame(), response };
  } catch (error) {
    if (error.message && error.message.toLowerCase().includes("timeout")) {
      let parsed = null;
      try {
        parsed = new URL(url);
      } catch (_) {}
      if (parsed) {
        let appPort = null;
        try {
          const path = require("path");
          const statePath = path.join(process.cwd(), ".codeyam", "server-state.json");
          if (fs.existsSync(statePath)) {
            const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
            appPort = state.appPort;
          }
        } catch (_) {}

        if (appPort) {
          let appHealthy = false;
          try {
            await assertAppPortReachable(`http://127.0.0.1:${appPort}/`, { timeoutMs: 500 });
            appHealthy = true;
          } catch (_) {}

          if (appHealthy) {
            throw new Error(
              `proxy navigation timed out: the proxy at 127.0.0.1:${parsed.port} did not respond within 30000ms. app healthy on :${appPort}, proxy dead on :${parsed.port}.`
            );
          } else {
            throw new Error(
              `proxy navigation timed out: the proxy at 127.0.0.1:${parsed.port} did not respond within 30000ms. app also unresponsive on :${appPort}.`
            );
          }
        } else {
          throw new Error(
            `proxy navigation timed out: the proxy at 127.0.0.1:${parsed.port} did not respond within 30000ms. proxy dead/hung?`
          );
        }
      }
    }
    throw error;
  }
}

// Text matching prefers an EXACT, INTERACTIVE element over a looser substring /
// plain-text hit (see `resolveTextTarget`), so the first attempt lands on the
// chip or button the agent meant. When a genuine ambiguity survives that
// resolution (>1 candidate in the winning tier), we still act — on the best
// visible candidate — but push an actionable warning naming every candidate
// into the optional `warnings` array so the agent can switch to an exact
// selector; a zero-match throws an error that spells out the substring caveat
// and the exact-selector / URL-query-param alternatives.
// Verbs that drive the page's mouse / keyboard directly rather than a located
// element's own handlers — the canvas verbs. A `<canvas>` paints every control
// into one element, so these aim at a position inside a DOM target (or, for
// `key` / `type`, at whatever already has focus).
const PAGE_KEYBOARD_ACTIONS = ["key", "type"];
const DEFAULT_DRAG_STEPS = 10;

// True for a step whose effect is painted rather than written to the DOM: any
// positional click/hover, any drag or wheel, and page-level keyboard input.
// Callers use it to settle on pixels instead of `innerHTML`, and to skip the
// DOM-only hydration-race retry, which would turn one canvas click into two.
function isCanvasInteraction(interaction) {
  const { action, position } = interaction || {};
  return (
    action === "drag" ||
    action === "wheel" ||
    PAGE_KEYBOARD_ACTIONS.includes(action) ||
    (position != null && (action === "click" || action === "hover"))
  );
}

// Page-level keyboard input. Deliberately not `locator.press`: a `<canvas>`
// without `tabindex` never receives focus, so a locator-scoped press is
// delivered nowhere. A preceding click on the canvas gives the app focus.
async function performKeyboardInteraction(frame, { action, value }) {
  const keyboard = pageOf(frame).keyboard;
  if (action === "key") {
    await keyboard.press(value || "Enter");
  } else {
    await keyboard.type(value ?? "");
  }
}

// Resolve a step's target to the single element to act on. Shared by
// `performInteraction` and by callers that need the target's box BEFORE
// acting (the pixel-effect signal clips its before/after shots to it).
async function resolveInteractionTarget(
  frame,
  interaction,
  { warnings, canvasProbe = probeCanvasDominated } = {},
) {
  const { action, selector, text } = interaction || {};

  let baseLocator;
  let targetDesc;
  let matchedByText = false;
  let matchCount;
  if (typeof text === "string" && text.length > 0) {
    const resolved = await resolveTextTarget(frame, text, action);
    baseLocator = resolved.baseLocator;
    matchCount = resolved.matchCount;
    targetDesc = `text "${text}"`;
    matchedByText = true;
  } else if (typeof selector === "string" && selector.length > 0) {
    baseLocator = frame.locator(selector);
    matchCount = await baseLocator.count();
    targetDesc = `selector "${selector}"`;
  } else {
    throw new Error(
      "preview-interact: interaction requires a `text` or `selector` target",
    );
  }

  if (matchCount === 0) {
    // Candidate labels are collected ONLY for the text branch — see
    // `noMatchGuidance` for why a CSS-selector miss neither needs them nor
    // should echo the user's page content back at them.
    throw new Error(
      noMatchGuidance({
        targetDesc,
        matchedByText,
        candidateLabels: matchedByText
          ? await candidateLabelSummary(frame)
          : null,
        canvasDominated: matchedByText ? await canvasProbe(frame) : false,
      }),
    );
  }

  const locator = await pickBestCandidate(baseLocator, matchCount);

  // Ambiguity warning: a text target that still resolves >1 element within the
  // winning tier acts on the best visible candidate, which may not be the one
  // intended. Name the competing elements instead of silently proceeding. Only
  // fires for text matches — an explicit selector that matches many is the
  // caller's deliberate choice.
  if (matchedByText && matchCount > 1 && Array.isArray(warnings)) {
    warnings.push(
      `preview-interact: ${targetDesc} matched ${matchCount} elements — acting on the best visible candidate. ` +
        `Text resolution prefers an exact, interactive match, but several remain, so this may not be the element you meant. ` +
        `Candidates: ${(await describeMatchCandidates(baseLocator, matchCount)).join(" | ")}. ` +
        `Use an exact/role/testid selector to disambiguate.`,
    );
  }

  return { locator, targetDesc };
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
async function performInteraction(
  frame,
  interaction,
  { timeoutMs = 5000, warnings } = {},
) {
  const { action, value, position, from, to, steps, button, deltaX, deltaY } =
    interaction || {};

  if (PAGE_KEYBOARD_ACTIONS.includes(action)) {
    try {
      await performKeyboardInteraction(frame, { action, value });
    } catch (error) {
      throw new Error(
        `preview-interact: action "${action}" failed: ${error.message || String(error)}`,
      );
    }
    return;
  }

  const { locator, targetDesc } = await resolveInteractionTarget(frame, interaction, {
    warnings,
  });

  // Only the keys Playwright accepts, so an absent field never reaches it as
  // an explicit `undefined`.
  const pointerOpts = { timeout: timeoutMs };
  if (position) pointerOpts.position = { x: position.x, y: position.y };
  if (button) pointerOpts.button = button;

  // Pointer verbs report where they landed; every other verb returns undefined.
  let geometry;
  try {
    switch (action) {
      case "click":
        geometry = await locatorPointGeometry(frame, locator, targetDesc, action, position);
        await locator.click(pointerOpts);
        break;
      case "fill":
        await locator.fill(value ?? "", { timeout: timeoutMs });
        break;
      case "press":
        await locator.press(value || "Enter", { timeout: timeoutMs });
        break;
      case "hover":
        // Reveals hover-only affordances (an action bar, a tooltip) — one of the
        // most common ephemeral states a resting-render screenshot misses.
        geometry = await locatorPointGeometry(frame, locator, targetDesc, action, position);
        await locator.hover(pointerOpts);
        break;
      case "drag": {
        // Pan / select-box / move: built from raw mouse events because a canvas
        // has no drop target for `locator.dragTo`.
        const box = await targetBox(locator, targetDesc);
        const mouse = pageOf(frame).mouse;
        const start = pointIn(box, from);
        if (!start.inside) {
          throw await outsideTargetError(frame, action, "from", from, targetDesc, box);
        }
        const end = pointIn(box, to);
        geometry = pointerGeometry(box, start, end);
        // Ending off the target can be deliberate (dragging something off the
        // canvas), so it warns rather than refuses.
        if (!end.inside) {
          geometry.warning =
            `drag ends outside the target: ` +
            outsideTargetMessage("to", to, targetDesc, box, await devicePixelRatioOf(frame));
          if (Array.isArray(warnings)) warnings.push(`preview-interact: ${geometry.warning}`);
        }
        const mouseButton = { button: button || "left" };
        await mouse.move(start.x, start.y);
        await mouse.down(mouseButton);
        await mouse.move(end.x, end.y, {
          steps: typeof steps === "number" && steps > 0 ? steps : DEFAULT_DRAG_STEPS,
        });
        await mouse.up(mouseButton);
        break;
      }
      case "wheel": {
        // Zoom / scroll: the wheel event lands wherever the pointer is, so move
        // there first.
        const box = await targetBox(locator, targetDesc);
        const mouse = pageOf(frame).mouse;
        const at = pointIn(box, position);
        if (!at.inside) {
          throw await outsideTargetError(frame, action, "position", position, targetDesc, box);
        }
        geometry = pointerGeometry(box, at);
        await mouse.move(at.x, at.y);
        await mouse.wheel(deltaX || 0, deltaY || 0);
        break;
      }
      default:
        throw new Error(
          `preview-interact: unknown action "${action}" (expected click | fill | press | hover | drag | wheel | key | type)`,
        );
    }
  } catch (error) {
    if (error && error.outsideTarget) throw error;
    throw new Error(
      `preview-interact: action "${action}" failed against ${targetDesc}: ${error.message || String(error)}. ` +
        `Candidate interactive labels: ${await candidateLabelSummary(frame)}`,
    );
  }
  return geometry;
}

// One screenshot of `page`, clipped to `clip` when given, as a Buffer. The
// pixel half of the interaction-effect signal and of the canvas settle. A
// failed shot returns null, which compares unequal to everything — so a flaky
// screenshot reads as "changed / not yet settled", never as a false "inert".
async function pixelSnapshot(page, clip) {
  try {
    const opts = { fullPage: false };
    if (clip && clip.width > 0 && clip.height > 0) opts.clip = clip;
    return await page.screenshot(opts);
  } catch (_) {
    return null;
  }
}

function samePixels(a, b) {
  return Buffer.isBuffer(a) && Buffer.isBuffer(b) && a.equals(b);
}

// Settle a canvas-painted page: `waitForStablePage` compares `innerHTML`, which
// a canvas never changes, so after a canvas verb it reads "settled" while the
// app is still animating a pan or zoom. Wait instead for two consecutive equal
// screenshots, bounded by `timeoutMs` — the same "real signal, safety bound"
// rule the DOM settle follows.
async function waitForPixelStable(
  page,
  { clip, timeoutMs = 5000, intervalMs = 150, snapshot = pixelSnapshot } = {},
) {
  const deadline = Date.now() + timeoutMs;
  let previous = await snapshot(page, clip);
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
    const current = await snapshot(page, clip);
    if (samePixels(previous, current)) return true;
    previous = current;
  }
  return false;
}

// Hold until a visible-text or selector predicate becomes true, bounded by a
// wall-clock timeout. Behavioral demos hinge on transient states (an overlay
// appears, then a new round renders); a flow step waits for that real signal
// instead of a fixed sleep — the same "hold to a real signal with a safety
// bound" rule the rest of the capture pipeline follows. THROWS on timeout
// naming the predicate and the bound, so the capture script's outer catch
// turns a never-appearing predicate into an actionable failure rather than an
// infinite hang. `text` is matched case-insensitively as a substring (the
// agent reliably knows the copy it rendered); `selector` is a CSS selector.
//
// A text predicate on a canvas-dominated page is refused at once rather than
// after the full bound: canvas-painted words are never DOM text, so the wait
// could only time out. A hybrid page (DOM text beside a canvas) is not
// canvas-dominated and keeps the ordinary wait; a canvas that mounts late is
// caught on the timeout path, which re-checks and appends the same guidance.
// A selector predicate is never refused — naming the canvas element itself is
// a legitimate wait for that element. `canvasProbe` is injectable so unit
// tests classify the page without a browser.
async function waitForPredicate(
  frame,
  predicate,
  { defaultTimeoutMs = 8000, canvasProbe = probeCanvasDominated } = {},
) {
  const { text, selector, timeoutMs } = predicate || {};
  const bound =
    typeof timeoutMs === "number" && timeoutMs > 0 ? timeoutMs : defaultTimeoutMs;

  let locator;
  let desc;
  const byText = typeof text === "string" && text.length > 0;
  if (byText) {
    if (await canvasProbe(frame)) {
      throw new Error(`waitFor: predicate text "${text}" ${canvasTextWaitGuidance()}`);
    }
    locator = frame.getByText(text, { exact: false }).first();
    desc = `text "${text}"`;
  } else if (typeof selector === "string" && selector.length > 0) {
    locator = frame.locator(selector).first();
    desc = `selector "${selector}"`;
  } else {
    throw new Error("waitFor: predicate requires a `text` or `selector` target");
  }

  try {
    await locator.waitFor({ state: "visible", timeout: bound });
  } catch (_) {
    const lateCanvas = byText && (await canvasProbe(frame));
    throw new Error(
      `waitFor: predicate ${desc} did not become visible within ${bound}ms` +
        (lateCanvas ? `. The page is now canvas-dominated: ${canvasTextWaitGuidance()}` : ""),
    );
  }
}

// Is the frame canvas-dominated right now — visible canvas/svg/video and no
// visible text? Reads the same content state the blank gate classifies on.
// Best-effort: a frame that cannot be measured reads as NOT canvas, so the
// caller keeps its ordinary DOM behavior instead of refusing on a guess.
async function probeCanvasDominated(frame) {
  try {
    const state = await collectContentState(frame);
    const visible = await collectVisibleTextLength(frame);
    if (typeof visible === "number") state.visibleTextLength = visible;
    return isCanvasDominated(state);
  } catch (_) {
    return false;
  }
}

// The redirect a text wait on a canvas page gets: why it cannot work, and the
// three forms that do.
function canvasTextWaitGuidance() {
  return (
    `cannot be awaited: this page is canvas-dominated (it paints into a ` +
    `canvas with no visible page text), and canvas-painted words are never ` +
    `in the DOM, so a text wait could only time out. Instead: wait for the ` +
    `painted frame to stop changing with {"waitFor":{"canvas":true,"timeoutMs":8000}}; ` +
    `click by position on the canvas ` +
    `({"click":{"selector":"canvas","position":{"x":120,"y":40}}}, CSS pixels ` +
    `from its top-left, read off the frame captured just before the step); or ` +
    `drop the wait and capture — the capture already settles on pixels.`
  );
}

// Drive an ordered sequence of interactions against the settled frame, settling
// the page between each so a later step sees the DOM the earlier one produced.
// This is the persisted-scenario path (`scenario.interactions`): unlike the
// single fire-and-forget `preview-interact`, the whole sequence is replayed on
// every capture and recapture. Any step that matches nothing throws (with the
// candidate-labels hint from `performInteraction`), and the caller turns that
// into a failed capture — never a silent resting-state screenshot for a
// sequence that didn't fully run.
// `settle` is injectable so unit tests that drive a mock frame stay
// network-free and fast; production callers use the default real
// `waitForStablePage` re-settle between steps.
async function performInteractionSequence(
  page,
  frame,
  interactions,
  {
    timeoutMs = 5000,
    settleMs = 5000,
    loadingMarkers,
    settle = waitForStablePage,
    pixelSettle = waitForPixelStable,
    warnings,
  } = {},
) {
  for (let i = 0; i < interactions.length; i += 1) {
    try {
      await performInteraction(frame, interactions[i], { timeoutMs, warnings });
    } catch (err) {
      // Prefix the failing step's index so a miss in a multi-step sequence is
      // locatable, matching the model-side `interactions[i]` validator.
      throw new Error(`interactions[${i}]: ${err.message}`);
    }
    await settle(page, frame, settleMs, loadingMarkers);
    if (isCanvasInteraction(interactions[i])) {
      await pixelSettle(page, { timeoutMs: settleMs });
    }
  }
}

// The query-param isolation harness renders a placeholder instead of the
// component when the component manifest has no entry for it (most often a fresh
// checkout, where the gitignored manifest is absent). That placeholder is a
// perfectly stable page, so nothing else in the capture path notices it: an
// interaction against it was reported as a selector miss, and a recapture
// saved it over the scenario's good committed screenshot. The shipped harness
// marks it with this attribute; harnesses scaffolded before the marker existed
// are matched by codeyam's own placeholder wording inside `#codeyam-capture`
// (a compatibility shim for text codeyam wrote, never app text).
const ISOLATE_MISSING_ATTR = "data-codeyam-isolate-missing";
const LEGACY_ISOLATE_MISSING_PATTERN = /^\s*No such component "([^"]*)"/;

// The component name the harness placeholder reports as missing, or null when
// the frame rendered something else.
async function isolateMissingComponent(frame) {
  return frame
    .evaluate(
      ({ attr, pattern }) => {
        const marked = document.querySelector(`[${attr}]`);
        if (marked) return marked.getAttribute(attr) || "";
        const wrapper = document.getElementById("codeyam-capture");
        if (!wrapper) return null;
        const match = (wrapper.textContent || "").match(new RegExp(pattern));
        return match ? match[1] : null;
      },
      {
        attr: ISOLATE_MISSING_ATTR,
        pattern: LEGACY_ISOLATE_MISSING_PATTERN.source,
      },
    )
    .catch(() => null);
}

// `routing.componentManifest` from `.codeyam/stack.json`, for naming the file
// in the error; a generic phrase when the stack declares none.
function componentManifestPath() {
  try {
    const stack = JSON.parse(
      fs.readFileSync(require("path").join(".codeyam", "stack.json"), "utf8"),
    );
    const manifest = stack && stack.routing && stack.routing.componentManifest;
    if (typeof manifest === "string" && manifest) return manifest;
  } catch (_) {}
  return "the component manifest";
}

function isolateMissingComponentMessage(name, manifestPath) {
  return (
    `isolation harness has no component "${name}" — the component manifest ` +
    `(${manifestPath}) is missing it. Run codeyam-editor editor isolate --all, ` +
    `or restart the dev server to regenerate it.`
  );
}

// Fail the capture when the frame is the harness placeholder. Called after the
// scenario loads and before any interaction or screenshot, so an interaction
// never runs against the placeholder and the committed PNG is never replaced.
async function assertIsolatedComponentResolved(
  frame,
  { manifestPath = componentManifestPath } = {},
) {
  const missing = await isolateMissingComponent(frame);
  if (missing !== null) {
    throw new Error(isolateMissingComponentMessage(missing, manifestPath()));
  }
}

module.exports = {
  logCaptureTiming,
  defaultReadServerState,
  resolveTcpTarget,
  assertAppPortReachable,
  escapeHtmlAttribute,
  buildIframeHarness,
  HARNESS_PATH,
  resolveHarnessOrigin,
  buildHarnessUrl,
  collectContentState,
  scrollThroughDocument,
  collectVisibleTextLength,
  forceFinalVisualState,
  centerCaptureWrapper,
  collectImageStates,
  waitForImagesSettled,
  waitForAnimationsSettled,
  createNetworkTracker,
  waitForNetworkQuiet,
  waitForStablePage,
  waitForReadySignal,
  watchNavigationAfterReady,
  loadScenarioInIframe,
  loadScenarioTopLevel,
  isCanvasInteraction,
  resolveInteractionTarget,
  performInteraction,
  pixelSnapshot,
  samePixels,
  waitForPixelStable,
  waitForPredicate,
  probeCanvasDominated,
  performInteractionSequence,
  ISOLATE_MISSING_ATTR,
  isolateMissingComponent,
  isolateMissingComponentMessage,
  assertIsolatedComponentResolved,
};
