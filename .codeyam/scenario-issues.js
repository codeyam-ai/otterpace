// codeyam-generated — DO NOT EDIT.
// codeyam-editor: 0.1.7  build: 283adba28f3fc30f058c87b4f92900dccc81f9e5  source-sha256: c582b56a39e0e81fcc30bf0053446089722d89857bc658efd594d671dea84cb2
function createIssue(kind, message, extra = {}) {
  const issue = {
    kind,
    message,
    url: extra.url ?? null,
    status: extra.status ?? null,
  };
  if (extra.matchedPattern != null) issue.matchedPattern = extra.matchedPattern;
  if (extra.contextSnippet != null) issue.contextSnippet = extra.contextSnippet;
  // The hydration gate's cross-origin ATTRIBUTION, carried as data rather than
  // only as prose. A consumer that must act on the verdict — escalating the
  // preview off the subpath when the counterpart origin hydrates — would
  // otherwise have to regex the English message, which breaks the moment the
  // wording is improved. Same conditional shape as the two fields above so an
  // issue that carries no attribution serializes exactly as it did before.
  if (extra.crossOrigin != null) issue.crossOrigin = extra.crossOrigin;
  if (extra.counterpartUrl != null) issue.counterpartUrl = extra.counterpartUrl;
  // The dev-server-down verdict, carried as data for the same reason as the
  // attribution fields above: a consumer that must distinguish "the app served
  // an error" from "the app was not serving at all" should branch on a field,
  // not on the prose of the message.
  if (extra.devServerDown != null) issue.devServerDown = extra.devServerDown;
  return issue;
}

function pushIssue(issues, issue) {
  const key = JSON.stringify(issue);
  if (!issues.some((existing) => JSON.stringify(existing) === key)) {
    issues.push(issue);
  }
}

// Derive which origin a capture actually loaded from, and whether that differs
// from the origin the VIEWER's browser is served.
//
// The two can legitimately differ: the capture browser runs where the app is,
// the viewer may not, and aiming them independently is what makes a capture
// work on a cloud VM at all. A capture that renders perfectly from the app's
// own origin while the user's pane sits on `/__codeyam_preview` is a USEFUL
// result — but only if the difference travels with it instead of having to be
// inferred from a URL the reader must parse themselves.
//
// Both unknowns resolve toward "no split", never toward a guess. A caller that
// supplies no `viewerOrigin` (every pre-existing call site) and a `url` with no
// parseable origin both yield `false`, so no existing consumer sees a changed
// verdict and an unclassifiable capture is never reported as diverging.
//
// Deliberately not reusing `isCrossOriginRequest` from scenario-check.js: that
// module imports THIS one, so depending on it would invert the dependency, and
// its fail-safe answers a different question (never strip markers) than this
// one does (never claim a split).
function deriveOriginSplit(url, viewerOrigin) {
  let captureOrigin = null;
  try {
    captureOrigin = new URL(url).origin;
  } catch (_) {
    /* a malformed or relative capture URL has no origin to report */
  }
  return {
    captureOrigin,
    viewerOrigin: viewerOrigin ?? null,
    captureOriginDiffersFromViewer:
      captureOrigin != null &&
      viewerOrigin != null &&
      captureOrigin !== viewerOrigin,
  };
}

function buildResult({
  loaded,
  hasContent,
  issues,
  outputPath,
  url,
  unmockedRoutes = [],
  mockUsage = { used: [], unused: [] },
  externalRequests = [],
  viewerOrigin = null,
}) {
  const { captureOrigin, captureOriginDiffersFromViewer } = deriveOriginSplit(
    url,
    viewerOrigin,
  );

  return {
    ok: loaded && hasContent && issues.length === 0,
    loaded,
    hasContent,
    url,
    outputPath: outputPath ?? null,
    issues,
    // Diagnostic-only: same-origin 4xx routes with no scenario mock. Does NOT
    // affect `ok` — the paired console error already fails the capture; this is
    // the actionable route list the failure message and `stub-unmocked-routes`
    // consume. Defaults to `[]` so callers that omit it are unchanged.
    unmockedRoutes,
    // Diagnostic-only, and deliberately NOT part of `ok`: an unused mock is not
    // automatically an error (a scenario may legitimately declare a mock for a
    // request the page makes only on interaction). Reporting it turns a silent
    // inertness into a visible fact; failing on it would break working scenarios
    // for a heuristic.
    mockUsage,
    // Requests grouped by origin, split mocked/unmocked and same/cross-origin.
    // The line that ends a "why is this page blank" misdiagnosis.
    externalRequests,
    // The two hops, named. See `deriveOriginSplit` for why they can differ and
    // why reporting the difference is not optional.
    captureOrigin,
    viewerOrigin,
    captureOriginDiffersFromViewer,
  };
}

// The message a capture fails with when the scenario frame navigated after its
// ready signal arrived — a dev server's live reload swapping the page under the
// shot.
const RELOADED_AFTER_READY =
  "The scenario page navigated after it signalled ready (a dev-server live reload)";

// Failure messages that mean the page was reloaded mid-capture rather than that
// the app is broken: Playwright's destroyed-context and detached-frame errors,
// and the marker above. Any dev server with live reload (Vite full reload,
// trunk, Flutter) produces them, so the match names no stack.
const LIVE_RELOAD_FAILURE_PATTERNS = [
  /Execution context was destroyed/i,
  /Frame was detached/i,
  /navigated after it signalled ready/,
];

// The first issue of a failed capture whose message names a mid-capture
// reload, or null. A capture that passed, or failed for any other reason, is
// never a reload candidate.
function liveReloadIssue(result) {
  if (!result || result.ok) return null;
  return (
    (result.issues || []).find((issue) =>
      LIVE_RELOAD_FAILURE_PATTERNS.some((re) => re.test(String(issue.message || ""))),
    ) || null
  );
}

// Run a capture `attempt`, and run it ONCE more when a dev server's live reload
// interrupted it: the reload is a temporary condition, and the second attempt
// waits for the ready signal on the reloaded page from scratch. The retry is
// recorded on the returned result (`reloadRetry`) so it is visible rather than
// silently absorbed, and a second failure is returned as-is, with its own
// reason. `onRetry` is told the first failure before the retry starts.
async function retryOnLiveReload(attempt, { onRetry = () => {} } = {}) {
  const first = await attempt();
  const reload = liveReloadIssue(first);
  if (!reload) return first;
  onRetry(reload.message);
  const second = await attempt();
  second.reloadRetry = { retried: true, firstError: reload.message };
  return second;
}

module.exports = {
  createIssue,
  pushIssue,
  buildResult,
  deriveOriginSplit,
  RELOADED_AFTER_READY,
  liveReloadIssue,
  retryOnLiveReload,
};
