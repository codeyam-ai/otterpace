// codeyam-generated — DO NOT EDIT.
// codeyam-editor: 0.1.7  build: 283adba28f3fc30f058c87b4f92900dccc81f9e5  source-sha256: bdeacdc1165b33aff68a5ea99da19e26c12d3c74e76cf25f0fd699b91556d461
// npm/scenario-check-run.js — the decision half of one scenario capture: the
// context options it opens with, the page collectors that turn console and
// network events into issues, the navigation-status verdict, the settle
// budgets, the content and error-marker checks, the single-interaction effect
// verdict, and the result decoration. `runScenarioCheckOnce` in
// scenario-check.js keeps the browser/page lifecycle and the phase order.
// Split out of scenario-check.js, which re-exports the helpers its tests name.
"use strict";

const { createIssue, pushIssue } = require("./scenario-issues");
const { isDeclaredErrorMock, unmockedRouteFrom } = require("./scenario-mocks");
const {
  waitForStablePage,
  collectContentState,
  collectVisibleTextLength,
  isCanvasInteraction,
  resolveInteractionTarget,
  performInteraction,
  pixelSnapshot,
  samePixels,
  waitForPixelStable,
} = require("./scenario-playwright");
const {
  findScenarioError,
  SCENARIO_ERROR_MARKER,
  hasRenderableContent,
  describeBlankReason,
} = require("./scenario-metrics");
const {
  handleConsoleMessage,
  handlePageError,
  handleRequestFailed,
} = require("./scenario-handlers");

// The sentinel the reverse proxy stamps on its dev-server-down placeholder —
// the other half of this contract is
// `crates/proxy-http/src/reverse_proxy.rs::DEV_SERVER_DOWN_HEADER`, and the two
// spellings are deliberately greppable from each other. Keyed on the header
// rather than the placeholder's copy for two reasons: the response is a 200, so
// no status check can see it, and the copy is per-framework prose that drifts
// the moment `render_placeholder` is reworded.
const DEV_SERVER_DOWN_HEADER = "x-codeyam-dev-server-down";

// Cold-start retry pause. waitForStablePage settles as soon as the page is
// HTML-stable, which for a lazy/Suspense app is the empty `<div id="root">`
// shell — stable for the ~3s the dynamic chunk takes to load (longer when the
// scenario's mocks slow the boot). 500ms re-checked before the chunk resolved
// and reported a false blank; this pause must comfortably exceed that window
// while staying under the test runner's default per-case timeout.
const BLANK_RETRY_DELAY_MS = 3000;

// Classify what a driven interaction actually did, from the DOM fingerprint on
// either side of it plus the page's hydration state. Pure, so the distinction
// this encodes is unit-tested without a browser.
//
// A click that changed nothing has two very different causes, and reporting both
// as "none" is what let a dead page masquerade as a flaky harness: a page that
// NEVER HYDRATED could not have responded to ANY interaction (no client JS is
// running), whereas a hydrated page with an unchanged DOM really does mean the
// control is inert. Keeping them apart is what tells a reader whether to go look
// at their component or at the environment.
//
// `hydrated` is the three-valued signal from `waitForHydration`: only a PROVEN
// dead page (`false`) earns "unhydrated". `null` means the wait could not judge
// (unknown framework, no controls, probe threw) and must keep reporting "none" —
// never invent a hydration fault we cannot prove.
//
// `pixelsChanged` is the second effect signal, for apps that paint into a
// `<canvas>`: their DOM never changes, so a working click there used to read as
// "none". An effect counts when EITHER signal moved; a pixel change alone also
// rules out "unhydrated", since something on the page responded.
function classifyInteractionEffect(
  beforeFingerprint,
  afterFingerprint,
  hydrated,
  pixelsChanged = false,
) {
  if (beforeFingerprint !== afterFingerprint) return "changed";
  if (pixelsChanged === true) return "changed";
  if (hydrated === false) return "unhydrated";
  return "none";
}

// Where to look for a pixel effect, and whether the pixel signal applies at all.
// The shot is clipped to the target's box, so an unrelated spinner elsewhere on
// the page cannot pass for an effect; page-level keyboard verbs have no target
// and use the whole viewport (`clip: null`). A target that cannot be resolved
// here is left for `performInteraction` to fail on with its full no-match
// guidance, so this never throws.
//
// `targetIsCanvas` is what scopes the pixel signal to canvas work. On an
// ordinary DOM control an inert click still paints a focus ring or a pressed
// state, and counting that as an effect would hide exactly the dead handler the
// "none" verdict exists to report.
async function resolvePixelClip(frame, interaction, resolve = resolveInteractionTarget) {
  if (["key", "type"].includes((interaction || {}).action)) {
    return { clip: null, targetIsCanvas: false };
  }
  try {
    const { locator } = await resolve(frame, interaction);
    const clip = await locator.boundingBox();
    const targetIsCanvas = await locator.evaluate(
      (el) => el.tagName === "CANVAS" || !!el.querySelector("canvas"),
    );
    return { clip, targetIsCanvas: targetIsCanvas === true };
  } catch (_) {
    return { clip: null, targetIsCanvas: false };
  }
}

// Which signal proved the effect: `dom` wins when both moved, because it is the
// stronger and more specific evidence. `null` when neither moved.
function interactionEffectSignal(beforeFingerprint, afterFingerprint, pixelsChanged) {
  if (beforeFingerprint !== afterFingerprint) return "dom";
  if (pixelsChanged === true) return "pixels";
  return null;
}

// Hash serialized markup into a compact `<length>-<hash>` fingerprint, so two
// snapshots compare by value. Pure; `getDOMFingerprint` decides what markup
// goes in.
function fingerprintHtml(html) {
  const text = String(html || "");
  let hash = 0;
  for (let i = 0; i < text.length; i++) {
    hash = (hash << 5) - hash + text.charCodeAt(i);
    hash |= 0;
  }
  return `${text.length}-${hash}`;
}

async function getDOMFingerprint(frame) {
  try {
    // On a clone, so the live page is untouched: drop each inline `cursor`
    // and re-serialize every inline style in its canonical form.
    //
    // The cursor is pointer feedback, not app state — egui/eframe rewrites its
    // canvas's cursor every time the pointer crosses a widget, so counting it
    // made a click on empty canvas read as "changed", hiding exactly the dead
    // step the verdict exists to name. It is removed through the style object,
    // never a text regex, which would also eat visible text like "cursor: 4,2".
    // Canonical form matters because the first script write to `el.style`
    // re-serializes the WHOLE attribute (`display:block` → `display: block;`),
    // which alone would move the fingerprint.
    const html = await frame.evaluate(() => {
      if (!document.body) return null;
      const clone = document.body.cloneNode(true);
      for (const el of clone.querySelectorAll("[style]")) {
        el.style.removeProperty("cursor");
        el.setAttribute("style", el.style.cssText);
      }
      return clone.innerHTML;
    });
    return html === null ? "" : fingerprintHtml(html);
  } catch (err) {
    return "";
  }
}

// Measure the frame's visible (painted, non-opacity:0) text and fold it into
// the content state in place, so the blank gate can distinguish "text rendered
// but invisible" from a populated frame. Best-effort: a frame/target that
// cannot be measured (a stubbed test target returns a non-number, an evaluate
// throws) leaves the state untouched, so `hasRenderableContent` falls back to
// its DOM-presence behavior rather than treating an un-measurable frame as
// blank.
async function mergeVisibleTextLength(contentState, frame) {
  if (!contentState) return;
  let visible;
  try {
    visible = await collectVisibleTextLength(frame);
  } catch (_) {
    return;
  }
  if (typeof visible === "number") {
    contentState.visibleTextLength = visible;
  }
}

// True when `url` targets a different origin than `appOrigin`. Used to decide
// whether the codeyam capture markers must be stripped before the request
// leaves (cross-origin) or may ride along (same-origin, the app's own dev
// server). A malformed URL counts as same-origin (false) so we never strip
// markers from a request we can't classify — the conservative default keeps
// same-origin behavior unchanged. `url` may be a string or a URL-like object.
function isCrossOriginRequest(url, appOrigin) {
  try {
    const href = typeof url === "string" ? url : url.href;
    return new URL(href).origin !== appOrigin;
  } catch (_) {
    return false;
  }
}

// Decide whether a failed request should fail the capture. Only a failure
// targeting the captured page's OWN origin counts — a first-party route that
// 500s or a same-origin asset that 404s is a real capture problem. A
// cross-origin failure (the mocked app's dev port being down, an external
// CDN/API) is an external resource and is tolerated, so the editor-shell
// screenshot still succeeds. Mirrors the console handler's tolerance for
// declared error-mock URLs. When `appOrigin` is unknown (malformed capture
// URL) the failure stays fatal — the conservative default preserves today's
// behavior rather than silently swallowing every failure. Pure, so the
// decision is unit-testable without a live browser.
function isCaptureFatalRequestFailure(url, appOrigin) {
  if (!appOrigin) return true;
  return !isCrossOriginRequest(url, appOrigin);
}

// True when this response is the reverse proxy's dev-server-down placeholder
// rather than the app. The proxy stamps `DEV_SERVER_DOWN_HEADER` on exactly
// that response and four Rust consumers already key on it; this is the fifth,
// and the first on the capture side. Header names are compared
// case-insensitively — Playwright lowercases them, but the contract is the
// header, not Playwright's normalization of it. A null response is not a
// placeholder (the null-response case has its own branch). Pure, so the
// decision is unit-testable without a live browser or a downed dev server.
function isDevServerPlaceholderResponse(response) {
  if (!response || typeof response.headers !== "function") return false;
  const headers = response.headers() || {};
  return Object.keys(headers).some(
    (name) => name.toLowerCase() === DEV_SERVER_DOWN_HEADER,
  );
}

// The `browser.newContext` options one capture opens with: the scenario's
// viewport and render environment, plus `ignoreHTTPSErrors` for an https
// capture origin only. Pure.
function buildCaptureContextOptions(config, appOrigin) {
  const { width, height } = config;
  const contextOptions = {
    viewport: { width: width || 1440, height: height || 900 },
    // Explicit, because a flow step that exports a file must produce evidence
    // rather than a download nobody waits on (see `saveFlowDownload`).
    acceptDownloads: true,
  };
  if (config.colorScheme) contextOptions.colorScheme = config.colorScheme;
  if (config.deviceScaleFactor)
    contextOptions.deviceScaleFactor = config.deviceScaleFactor;
  if (config.userAgent) contextOptions.userAgent = config.userAgent;
  if (config.locale) contextOptions.locale = config.locale;
  if (config.timezoneId) contextOptions.timezoneId = config.timezoneId;
  if (config.reduceMotion) contextOptions.reducedMotion = config.reduceMotion;
  if (config.forcedColors) contextOptions.forcedColors = config.forcedColors;
  // When the opt-in HTTPS preview (`proxy.httpsPreview`) is on, the capture
  // origin is `https://localhost:<port>` served by the reverse proxy's
  // self-signed cert. Accept it for capture only — gated on the https origin so
  // plain-HTTP captures keep full TLS-error fidelity.
  if (typeof appOrigin === "string" && appOrigin.startsWith("https://")) {
    contextOptions.ignoreHTTPSErrors = true;
  }
  return contextOptions;
}

// Wire the page's `pageerror` / `console` / `response` / `requestfailed`
// events to the capture's verdict: each fatal event becomes an issue on
// `issues`, and each same-origin 4xx no scenario mock covers is appended to
// `unmockedRoutes`. Attach BEFORE navigation so nothing the load does is missed.
function attachCaptureCollectors(
  page,
  { issues, unmockedRoutes, httpMocks, appOrigin, expectedConsoleErrors },
) {
  const unmockedRouteKeys = new Set();

  page.on("pageerror", (error) => {
    pushIssue(issues, handlePageError(error));
  });

  page.on("console", (message) => {
    const issue = handleConsoleMessage(message);
    if (!issue) return;
    // Per-scenario allowance: a scenario that provokes console errors by design
    // (a broken-image fallback whose `<img>` is meant to 404) opts in via
    // `expectedConsoleErrors`. Load-bearing: without it the console-error guard
    // fails the capture instead of screenshotting the intended fallback UI. A
    // non-opted-in scenario still fails, so an unexpected console error is never
    // silently tolerated.
    if (expectedConsoleErrors) return;
    // Console errors produced by the scenario's OWN declared error mocks
    // (status >= 400) are the intended behavior of an error-state scenario,
    // not a capture problem — skip them so "History - Load Error"-style
    // scenarios can screenshot the failure UI they exist to demonstrate.
    const sourceUrl = message.location && message.location().url;
    if (sourceUrl && isDeclaredErrorMock(httpMocks, sourceUrl)) return;
    // A console error originating from a cross-origin resource — the "Failed to
    // load resource" Chromium logs alongside a cross-origin requestfailed (the
    // down app dev port, an external CDN) — is an external-resource failure, not
    // an editor-shell problem. Tolerate it for the same reason, and via the same
    // predicate, as the requestfailed handler below.
    if (sourceUrl && !isCaptureFatalRequestFailure(sourceUrl, appOrigin)) return;
    pushIssue(issues, issue);
  });

  page.on("response", (response) => {
    // Collect same-origin 4xx responses that no scenario mock covers — the set
    // a stub mock would fix. Mirrors the console-guard predicates exactly so the
    // reported set matches the guard's tolerances: a scenario that provokes
    // errors by design (`expectedConsoleErrors`) reports none, and a route the
    // scenario already declares an error mock for is the mock's intended 4xx,
    // not a missing mock.
    if (expectedConsoleErrors) return;
    const req = response.request();
    const reqUrl = req.url();
    // Same-origin only — mirror the console/requestfailed origin gate so a
    // cross-origin sub-resource 4xx is never reported as an unmocked route.
    if (!isCaptureFatalRequestFailure(reqUrl, appOrigin)) return;
    // The status-threshold, declared-mock, and path-extraction decision is the
    // pure `unmockedRouteFrom` helper; the listener keeps only the stateful
    // same-origin gate above and the dedup below.
    const route = unmockedRouteFrom(req.method(), reqUrl, response.status(), httpMocks);
    if (!route) return;
    const key = `${route.method} ${route.path}`;
    if (unmockedRouteKeys.has(key)) return;
    unmockedRouteKeys.add(key);
    unmockedRoutes.push(route);
  });

  page.on("requestfailed", (request) => {
    // Per-scenario allowance: the broken-image fallback scenario's `<img>` 404
    // is a SAME-origin request failure it exists to demonstrate, so
    // `expectedConsoleErrors` tolerates it here too (the console guard above
    // relaxes the paired "Failed to load resource" error). Load-bearing for the
    // same reason; a non-opted-in same-origin failure still fails the capture.
    if (expectedConsoleErrors) return;
    // A cross-origin sub-resource failing must not fail an editor-shell
    // screenshot — only the captured page's OWN origin counts. The most common
    // case here is the live preview pane reaching the mocked project's app dev
    // port (e.g. http://localhost:3000), which is not running in the
    // self-hosting capture container.
    if (!isCaptureFatalRequestFailure(request.url(), appOrigin)) return;
    const issue = handleRequestFailed(request);
    if (issue) {
      pushIssue(issues, issue);
    }
  });
}

// The verdict on the initial load's response: `issue` is the navigation issue
// it earns (or null), and `devServerPlaceholder` says the document was the
// proxy's dev-server-down placeholder, which must never be screenshotted.
// Pure over a Playwright-shaped response.
function navigationStatusIssue(response, config, url) {
  // The proxy's dev-server-down placeholder is a 200 carrying codeyam's own
  // sentinel header, so it is checked BEFORE the status branches below —
  // status alone cannot tell it from the app. Left unchecked, the capture
  // photographs codeyam's "Ready to scaffold" card, reports success, and
  // leaves that frame on disk to be shown later as the app's real state.
  if (isDevServerPlaceholderResponse(response)) {
    return {
      devServerPlaceholder: true,
      issue: createIssue(
        "navigation",
        "Captured the editor's dev-server placeholder, not the app. The proxy " +
          `answered with \`${DEV_SERVER_DOWN_HEADER}\`, which means the proxy ` +
          "could not reach the app for this request. That happens two ways: the " +
          "app's dev server is not running, or it is running and the proxy could " +
          "not reach it this time. The screenshot would be of codeyam's own " +
          "placeholder card. Re-run the capture first — it is the cheaper check, " +
          "and a transient miss clears. If the same capture fails this way again, " +
          "confirm the app's dev server is up and accepting connections.",
        { url, devServerDown: true },
      ),
    };
  }
  if (response && response.status() >= 400) {
    return {
      devServerPlaceholder: false,
      issue: createIssue("navigation", `Navigation returned HTTP ${response.status()}`, {
        url: response.url(),
        status: response.status(),
      }),
    };
  }
  if (!response && config.navigation === "topLevel") {
    // A real top-level document load always yields a response. A null one
    // means the status could never be checked — and an unverified status is
    // not a passing status: a 500 whose error body renders text would
    // otherwise satisfy `hasContent` and pass as `ok`. Fail loudly instead.
    // The iframe path stays tolerant: there the app response is matched by
    // exact URL and is legitimately allowed to miss.
    return {
      devServerPlaceholder: false,
      issue: createIssue(
        "navigation",
        "Navigation response unavailable — could not verify the HTTP status of the top-level document",
        { url },
      ),
    };
  }
  return { devServerPlaceholder: false, issue: null };
}

// The three settle budgets a capture reads from its config. Pure.
function resolveSettleBudgets(config) {
  // Content-stability window. Defaults to 10s; the editor's own WS-driven
  // terminal/build route under self-hosting passes a longer `stableTimeoutMs`
  // (its network never goes idle, so the default expired before the WS replay
  // landed and the capture came back blank — VM1). Every other route omits the
  // field and keeps the 10s default.
  const stableTimeoutMs =
    typeof config.stableTimeoutMs === "number" && config.stableTimeoutMs > 0
      ? config.stableTimeoutMs
      : 10000;
  // Hydration wait cap. Mirrors `stableTimeoutMs`: defaults to 10s, but a slow
  // Turbopack cold-compile route can extend it via `config.hydrationTimeoutMs`
  // without a code change. Bounded and near-zero on a healthy page (attaches in
  // a poll or two); only a genuinely dead page pays the full cap.
  const hydrationTimeoutMs =
    typeof config.hydrationTimeoutMs === "number" &&
    config.hydrationTimeoutMs > 0
      ? config.hydrationTimeoutMs
      : 10000;
  // A scenario's declared `captureTiming` moment, as a FLOOR on when the
  // frame may be taken. Distinct from `stableTimeoutMs` above, which is a
  // CAP: `waitForStablePage` returns the moment two consecutive polls match,
  // so a cap can only ever make a capture happen *sooner*, never later. That
  // asymmetry is what made a declared capture moment unreachable on a canvas
  // surface — a scripted terminal replay paints into a <canvas>, so
  // `document.body.innerHTML` never changes while it plays, the page reads as
  // stable on the first two polls, and the frame was taken ~1.2s in no matter
  // what the scenario declared. A scenario whose interesting state arrives
  // later than that (a `blocked` banner scripted at 1800ms) could never be
  // captured, and raising `atMs` did nothing because it only raised the cap.
  const captureAtMs =
    typeof config.captureAtMs === "number" && config.captureAtMs > 0
      ? config.captureAtMs
      : null;
  return { stableTimeoutMs, hydrationTimeoutMs, captureAtMs };
}

// Read what the frame rendered and decide whether it counts as content,
// pushing the `blank` issue when it does not. Returns the content state the
// canvas check later reads, and the `hasContent` verdict.
async function collectRenderedContent(page, frame, { issues, url, allowMinimalRender }) {
  // Cold-start retry: a single re-collect after BLANK_RETRY_DELAY_MS covers
  // the React.lazy / Suspense-fallback race where waitForStablePage settles
  // on the still-empty `<div id="root">` shell before the dynamic chunk
  // resolves. One retry is enough — the pause is sized to outlast the
  // chunk-load window; only a genuinely blank page falls through to the
  // blank issue below.
  let contentState = await collectContentState(frame);
  await mergeVisibleTextLength(contentState, frame);
  let hasContent = hasRenderableContent(contentState);
  if (!hasContent) {
    await new Promise((r) => setTimeout(r, BLANK_RETRY_DELAY_MS));
    contentState = await collectContentState(frame);
    await mergeVisibleTextLength(contentState, frame);
    hasContent = hasRenderableContent(contentState);
  }

  // Per-scenario allowance: a scenario whose intended UI is intrinsically
  // minimal (an empty `<textarea>` the blank heuristic can't "see") opts in
  // via `allowMinimalRender`. Accept the near-blank render as valid content so
  // BOTH the blank issue below is skipped AND `buildResult`'s `ok` (which
  // independently requires `hasContent`) can be true — otherwise the capture
  // would still fail with an empty issue list. The cold-start retry already
  // ran above, so a non-opted-in blank (a genuinely empty render) still falls
  // through to the issue below.
  if (!hasContent && allowMinimalRender) {
    hasContent = true;
  }

  if (!hasContent) {
    pushIssue(
      issues,
      createIssue(
        "blank",
        `Page rendered no visible content (${describeBlankReason(contentState)})`,
        { url: page.url() || url },
      ),
    );
  }
  return { contentState, hasContent };
}

// Check for codeyam's scenario-renderer error fallback. We anchor on the
// DOM marker the ScenarioRenderer stamps on its error / seed-error frames
// rather than scanning the whole page body for ERROR_PATTERNS — a
// legitimately-mocked scenario whose content quotes one of those harness
// phrases must not be flagged. Apps with no codeyam ScenarioRenderer never
// emit the marker, so their pages are treated as healthy regardless of body
// text. The scan is scoped to the marked element's own text. Returns the
// `error-state` issue, or null.
async function scenarioErrorMarkerIssue(page, frame, url) {
  const errorMarker = await frame.evaluate((attr) => {
    const el = document.querySelector(`[${attr}]`);
    if (!el) return null;
    return {
      reason: el.getAttribute(attr) || "",
      text: el.innerText || el.textContent || "",
    };
  }, SCENARIO_ERROR_MARKER);
  const scenarioError = findScenarioError(errorMarker);
  if (!scenarioError) return null;
  const { matchedPattern, contextSnippet } = scenarioError;
  return createIssue(
    "error-state",
    `Page contains error content (matched "${matchedPattern}"): ${contextSnippet ?? ""}`,
    {
      url: page.url() || url,
      matchedPattern,
      contextSnippet,
    },
  );
}

// Drive a scenario's single `interaction` against the settled frame and
// classify what it did. Returns `{ interactionEffect, interactionRetried,
// interactionSignal }`, the fields the result reports for `preview-interact`.
async function driveSingleInteraction(
  page,
  frame,
  interaction,
  { loadingMarkers, warnings, hydrated },
) {
  let interactionRetried = false;
  const { clip: pixelClip, targetIsCanvas } = await resolvePixelClip(
    frame,
    interaction,
  );
  const canvasVerb = isCanvasInteraction(interaction) || targetIsCanvas;

  // Record both fingerprints before interaction
  const beforeFingerprint = await getDOMFingerprint(frame);
  const beforePixels = canvasVerb ? await pixelSnapshot(page, pixelClip) : null;

  // Drive the requested interaction (if any) against the settled frame,
  // then re-settle, so `preview-interact` captures the RESULT of a click /
  // fill / press (expanded accordion, open modal) without editing app
  // source. A no-match target throws here and is caught below as a failed
  // capture with the candidate-labels hint — never a silent blank shot.
  await performInteraction(frame, interaction, {
    warnings,
  });
  await waitForStablePage(page, frame, 5000, loadingMarkers);
  if (canvasVerb) {
    await waitForPixelStable(page, { clip: pixelClip, timeoutMs: 5000 });
  }

  // Record both fingerprints after interaction
  let afterFingerprint = await getDOMFingerprint(frame);
  const pixelsMoved = async () =>
    canvasVerb && !samePixels(beforePixels, await pixelSnapshot(page, pixelClip));
  let pixelsChanged = await pixelsMoved();

  // If NEITHER signal moved and it was a plain DOM click, retry once after
  // 500ms (covers the hydration race). Never for a canvas verb: a canvas
  // click that did land shows no DOM change, and repeating it toggles a
  // selection straight back off.
  if (
    beforeFingerprint === afterFingerprint &&
    !pixelsChanged &&
    interaction.action === "click" &&
    !canvasVerb
  ) {
    interactionRetried = true;
    await new Promise((resolve) => setTimeout(resolve, 500));
    // The retry re-resolves the same target; suppress its ambiguity warning
    // (already captured on the first attempt) to avoid a duplicate.
    await performInteraction(frame, interaction);
    await waitForStablePage(page, frame, 5000, loadingMarkers);
    afterFingerprint = await getDOMFingerprint(frame);
    pixelsChanged = await pixelsMoved();
  }

  return {
    interactionEffect: classifyInteractionEffect(
      beforeFingerprint,
      afterFingerprint,
      hydrated,
      pixelsChanged,
    ),
    interactionRetried,
    interactionSignal: interactionEffectSignal(
      beforeFingerprint,
      afterFingerprint,
      pixelsChanged,
    ),
  };
}

// Attach everything a successful capture reports beside `buildResult`'s
// verdict: the phase timings, the interaction / flow evidence, the password
// census and any non-fatal warnings. `interaction` is the single-interaction
// outcome, present exactly when the scenario declared one. Mutates and returns
// `result`.
function decorateCaptureResult(
  result,
  {
    timings,
    settleStartedAt,
    interaction,
    flowStepEffects,
    flowDownloads,
    hydration,
    interactionWarnings,
  },
) {
  if (timings.settleMs === undefined) {
    timings.settleMs = Date.now() - settleStartedAt;
  }
  result.timings = timings;

  if (interaction) {
    result.interactionEffect = interaction.interactionEffect;
    result.interactionRetried = interaction.interactionRetried;
    result.effectSignal = interaction.interactionSignal;
  }
  if (flowStepEffects.length > 0) {
    result.stepEffects = flowStepEffects;
  }
  if (flowDownloads.length > 0) {
    result.downloads = flowDownloads;
  }

  // Forward the hydration password census so the in-place auth-gate guard can
  // fire on a route the project never declared. Attached ONLY when the probe
  // actually took a census: a backend/static/unknown stack returns a null
  // census having looked at nothing, and emitting hardcoded `false`s there
  // would read downstream as positive "no password field", "not a credential
  // form" claims the probe never made.
  //
  // Emitted as ONE object rather than three sibling flags because the three
  // facts are only meaningful together — the two corroborating shapes exist
  // precisely to qualify the first, and a consumer that received one without
  // the others would be back to inferring a gate from a bare password field.
  // `hasPasswordInput` is the discriminator for whether a census happened at
  // all; the other two are booleans whenever it is.
  if (typeof hydration.hasPasswordInput === "boolean") {
    result.passwordCensus = {
      hasPasswordInput: hydration.hasPasswordInput,
      credentialForm: hydration.credentialForm === true,
      formIsThePage: hydration.formIsThePage === true,
    };
  }

  // Surface any non-fatal interaction/flow warnings (e.g. an ambiguous
  // substring text match) so the CLI can print them and the agent can switch
  // to a precise selector. Only attached when present — a clean run is
  // byte-for-byte unchanged.
  if (interactionWarnings.length > 0) {
    result.warnings = interactionWarnings.slice();
  }
  return result;
}

module.exports = {
  DEV_SERVER_DOWN_HEADER,
  classifyInteractionEffect,
  resolvePixelClip,
  interactionEffectSignal,
  fingerprintHtml,
  getDOMFingerprint,
  mergeVisibleTextLength,
  isCrossOriginRequest,
  isCaptureFatalRequestFailure,
  isDevServerPlaceholderResponse,
  buildCaptureContextOptions,
  attachCaptureCollectors,
  navigationStatusIssue,
  resolveSettleBudgets,
  collectRenderedContent,
  scenarioErrorMarkerIssue,
  driveSingleInteraction,
  decorateCaptureResult,
};
