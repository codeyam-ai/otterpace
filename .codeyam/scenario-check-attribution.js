// codeyam-generated — DO NOT EDIT.
// codeyam-editor: 0.1.7  build: 283adba28f3fc30f058c87b4f92900dccc81f9e5  source-sha256: 8ea8bb4c6058e15e73171807e0ab911594af67483b7b72ff8f46633140692567
// The rendered-sources record inside the capture. Two sources feed it: the
// app's own `capture.renderedSourcesSignal`, and rendered-source attribution —
// watching which of the app's own functions run while the scenario loads. Both
// become the record `rendered_sources.rs` reads beside the screenshot:
//   {"sources": [...], "attribution": "complete", "universe": [...]}
//
// Opt-in per stack through `capture.renderedSourcesAttribution` in
// `.codeyam/stack.json`. A stack that declares nothing keeps today's static
// render sets. See docs/rendered-source-attribution.md.

const fs = require("fs");
const path = require("path");
const { parseWasmFunctionNames } = require("./wasm-name-section");
const {
  workspaceCrates,
  filesForFunctionName,
  functionRangeAt,
  retirableBreakpoints,
} = require("./wasm-source-attribution");

// Every strategy this capture knows how to run. An unknown value is reported,
// never guessed at.
const ATTRIBUTION_STRATEGIES = ["wasm-function-entry"];

// The declared strategy from `.codeyam/stack.json`, or null. Never throws; an
// unreadable stack.json declares no strategy.
function readStackRenderedSourcesAttribution() {
  try {
    const raw = fs.readFileSync(path.join(".codeyam", "stack.json"), "utf8");
    const stack = JSON.parse(raw);
    const value = stack && stack.capture && stack.capture.renderedSourcesAttribution;
    return value === undefined ? null : value;
  } catch (_) {
    return null;
  }
}

// The strategy this capture runs: `{ strategy }` for a known one, `{ strategy:
// null }` for none, and `{ strategy: null, warning }` for a value that names no
// known strategy. A value injected through config wins over stack.json, and an
// injected `null` turns attribution off (the unarmed retry uses that).
function resolveRenderedSourcesAttribution(
  config,
  readStack = readStackRenderedSourcesAttribution,
) {
  const raw =
    config && Object.prototype.hasOwnProperty.call(config, "renderedSourcesAttribution")
      ? config.renderedSourcesAttribution
      : readStack();
  if (raw === null || raw === undefined || raw === false) return { strategy: null };
  const value = typeof raw === "string" ? raw.trim() : raw;
  if (value === "") return { strategy: null };
  if (ATTRIBUTION_STRATEGIES.includes(value)) return { strategy: value };
  return {
    strategy: null,
    warning: `rendered-sources: capture.renderedSourcesAttribution ${JSON.stringify(raw)} is not a known strategy (accepted: ${ATTRIBUTION_STRATEGIES.join(", ")}); no attribution record was written, so staleness keeps this scenario's full static render set.`,
  };
}

// Workspace crates per project dir, so a worker that serves many captures runs
// `cargo metadata` once.
const cratesCache = new Map();

function cachedWorkspaceCrates(projectDir, load = workspaceCrates) {
  if (!cratesCache.has(projectDir)) cratesCache.set(projectDir, load(projectDir));
  return cratesCache.get(projectDir);
}

// Pause the page the moment a wasm module finishes compiling, before the glue
// code can call its start function. The `scriptParsed` event that queued the
// breakpoint setup precedes this pause on the CDP stream, and the pause is held
// until every breakpoint is set — so startup code is watched too.
async function installWasmCompilePause(page) {
  await page.addInitScript(() => {
    const W = WebAssembly;
    for (const name of ["instantiateStreaming", "instantiate", "compileStreaming", "compile"]) {
      const orig = W[name];
      if (typeof orig !== "function") continue;
      W[name] = async function (...args) {
        const result = await orig.apply(this, args);
        // Reason: this `debugger` is the mechanism, not leftover debugging. It
        // is what pauses the page the instant a wasm module finishes compiling
        // and before the glue code calls its start function, which is the only
        // window in which the per-function breakpoints can be set in time to
        // watch startup code. It runs solely inside the capture's own
        // CDP-driven Chromium page, never in a user's app.
        // eslint-disable-next-line no-debugger
        debugger;
        return result;
      };
    }
  });
}

// One range per function in `bytecode` that maps to a workspace file:
// `{ start, end, files, name, breakpointId: null }`, in body order. A function
// with no name, or whose name maps to no workspace file, is not watched.
function functionRangesFor(bytecode, { crates, projectDir, exists = fs.existsSync }) {
  const { importedFunctions, names, bodies } = parseWasmFunctionNames(bytecode);
  const ranges = [];
  for (let i = 0; i < bodies.length; i++) {
    const name = names.get(importedFunctions + i);
    if (!name) continue;
    const files = filesForFunctionName(name, crates, projectDir, exists);
    if (files.size === 0) continue;
    const [start, end] = bodies[i];
    ranges.push({ start, end, files, name, breakpointId: null });
  }
  return ranges;
}

// The breakpoint ids to remove after a hit: the ones that fired plus every
// range `retirableBreakpoints` says is done, deduplicated. Clears each retired
// range's `breakpointId`, so a range is never retired twice.
function takeRetiredBreakpointIds(ranges, hitBreakpoints, sources, granularity) {
  const done = retirableBreakpoints(ranges, sources, granularity);
  const ids = new Set([...hitBreakpoints, ...done.map((r) => r.breakpointId)]);
  done.forEach((r) => {
    r.breakpointId = null;
  });
  return [...ids];
}

// Watch every workspace function's entry in the wasm modules `page` compiles,
// from before the module's start function runs. Call before navigation.
// Returns `{ finish }`: `finish()` stops watching and returns `{ record, stats }`.
//
// Stack assumption: a Rust workspace compiled to wasm with the name section
// kept (a trunk dev build keeps it), crate roots from `cargo metadata` — see
// wasm-source-attribution.js.
//
// `granularity: "function"` keeps every breakpoint until its own function runs
// and adds the names that ran to the record as `functions` — a measurement
// mode, at one pause per distinct function.
async function watchWasmFunctionEntries(
  context,
  page,
  { crates, projectDir, granularity = "file", exists = fs.existsSync },
) {
  await installWasmCompilePause(page);
  const cdp = await context.newCDPSession(page);
  await cdp.send("Debugger.enable");

  const modules = new Map(); // scriptId → [{ start, end, files, name, breakpointId }]
  const universe = new Set();
  const sources = new Set();
  const functions = new Set();
  let breakpoints = 0;
  let hits = 0;
  let setupMs = 0;
  let pending = Promise.resolve();
  let finished = false;

  cdp.on("Debugger.scriptParsed", (e) => {
    if (e.scriptLanguage !== "WebAssembly") return;
    pending = pending.then(async () => {
      const setupStartedAt = Date.now();
      const { bytecode } = await cdp.send("Debugger.getScriptSource", { scriptId: e.scriptId });
      const ranges = functionRangesFor(Buffer.from(bytecode, "base64"), {
        crates,
        projectDir,
        exists,
      });
      ranges.forEach((r) => r.files.forEach((f) => universe.add(f)));
      await Promise.all(
        ranges.map((range) =>
          cdp
            .send("Debugger.setBreakpoint", {
              location: { scriptId: e.scriptId, lineNumber: 0, columnNumber: range.start },
            })
            .then(({ breakpointId }) => {
              range.breakpointId = breakpointId;
              breakpoints++;
            })
            .catch(() => {}),
        ),
      );
      modules.set(e.scriptId, ranges);
      setupMs += Date.now() - setupStartedAt;
    });
  });

  cdp.on("Debugger.paused", async (e) => {
    await pending;
    const frame = e.callFrames[0];
    const ranges = frame && modules.get(frame.location.scriptId);
    if (!finished && ranges && e.hitBreakpoints && e.hitBreakpoints.length > 0) {
      hits++;
      const hit = functionRangeAt(ranges, frame.location.columnNumber);
      if (hit) {
        hit.files.forEach((f) => sources.add(f));
        functions.add(hit.name.replace(/\[[0-9a-f]+\]/g, ""));
      }
      const ids = takeRetiredBreakpointIds(ranges, e.hitBreakpoints, sources, granularity);
      await Promise.all(
        ids.map((id) =>
          cdp.send("Debugger.removeBreakpoint", { breakpointId: id }).catch(() => {}),
        ),
      );
    }
    await cdp.send("Debugger.resume").catch(() => {});
  });

  async function finish() {
    finished = true;
    // Disabling the domain drops every remaining breakpoint and resumes a
    // paused page, so whatever the capture does next runs unwatched.
    await cdp.send("Debugger.disable").catch(() => {});
    if (typeof cdp.detach === "function") await cdp.detach().catch(() => {});
    return {
      record: {
        sources: [...sources].sort(),
        attribution: "complete",
        universe: [...universe].sort(),
        ...(granularity === "function" ? { functions: [...functions].sort() } : {}),
      },
      stats: { breakpoints, hits, setupMs },
    };
  }

  return { finish };
}

// Arm the declared strategy on a fresh capture page, before navigation.
// Returns `{ strategy, finish }` — `finish()` yields `{ record }` or `{ warning }`
// — or null when nothing is armed. A strategy that cannot start (no cargo, an
// unreadable workspace) returns null and pushes a warning: attribution is never
// allowed to fail the capture.
async function armRenderedSourcesAttribution(
  context,
  page,
  strategy,
  { projectDir = process.cwd(), warnings = [], loadCrates = workspaceCrates } = {},
) {
  if (strategy !== "wasm-function-entry") return null;
  let watch;
  try {
    const crates = cachedWorkspaceCrates(projectDir, loadCrates);
    watch = await watchWasmFunctionEntries(context, page, { crates, projectDir });
  } catch (e) {
    warnings.push(
      `rendered-sources: wasm-function-entry attribution could not start (${(e && e.message) || e}); no attribution record was written, so staleness keeps this scenario's full static render set.`,
    );
    return null;
  }
  return {
    strategy,
    async finish() {
      const { record, stats } = await watch.finish();
      return { ...attributedRecordVerdict(record), stats };
    },
  };
}

// Judge a finished attribution: a record that watched nothing (the name section
// was stripped, or no function mapped to a workspace file) or saw nothing run
// is no information, never "drew nothing".
function attributedRecordVerdict(record) {
  if (record.universe.length === 0) {
    return {
      warning:
        "rendered-sources: wasm-function-entry attribution watched no workspace function (is the wasm name section stripped? a release build through wasm-opt drops it); no attribution record was written.",
    };
  }
  if (record.sources.length === 0) {
    return {
      warning:
        "rendered-sources: wasm-function-entry attribution saw no workspace function run before the screenshot; no attribution record was written.",
    };
  }
  return { record };
}

// The record to write beside the screenshot from what the signal reported
// (`signalSources`, possibly null) and what attribution saw (`attributed`,
// possibly null). With attribution, sources are the union and the claim is
// kept; without it, the plain marker-based record. Null when neither has
// anything to say.
function mergeRenderedSourcesRecord(signalSources, attributed) {
  if (attributed) {
    const sources = [...new Set([...(signalSources || []), ...attributed.sources])].sort();
    return { ...attributed, sources };
  }
  return signalSources ? { sources: signalSources } : null;
}

// The record beside a screenshot: `<screenshot>.rendered.json`. The editor's
// staleness check (`rendered_sources.rs`) reads the same spelling.
function renderedSourcesRecordPath(outputPath) {
  return `${outputPath}.rendered.json`;
}

// Evaluate the rendered-sources signal expression in `frame`: `{ value }`, or
// `{ error }` when the expression threw or the evaluation itself failed.
async function evaluateRenderedSourcesSignal(frame, signal) {
  try {
    return await frame.evaluate((expr) => {
      try {
        return { value: (0, eval)(expr) };
      } catch (e) {
        return { error: String((e && e.message) || e) };
      }
    }, signal);
  } catch (e) {
    return { error: String((e && e.message) || e) };
  }
}

// Evaluate the rendered-sources signal in the captured frame and record the
// answer beside the screenshot as `{"sources": [...]}`. Any earlier record is
// removed first, so a recapture that yields no usable answer never leaves the
// previous capture's report standing. An empty array means "no information"
// (no record, no warning); a throw or a non-array / non-string value is a
// warning — non-blocking, because the editor then simply keeps the full static
// render set. `attributed` is a complete-attribution record from
// `capture.renderedSourcesAttribution`; with one, the written record is the
// union of both reports and keeps the attribution claim. Returns the warning
// string, or null.
async function recordRenderedSources(
  frame,
  signal,
  outputPath,
  { fsImpl = fs, attributed = null } = {},
) {
  const recordPath = renderedSourcesRecordPath(outputPath);
  try {
    fsImpl.rmSync(recordPath, { force: true });
  } catch (_) {}
  let signalSources = null;
  let warning = null;
  if (signal) {
    const outcome = await evaluateRenderedSourcesSignal(frame, signal);
    ({ sources: signalSources = null, warning } = renderedSourcesFromOutcome(outcome, signal));
  }
  const record = mergeRenderedSourcesRecord(signalSources, attributed);
  if (record) {
    fsImpl.writeFileSync(recordPath, `${JSON.stringify(record, null, 2)}\n`);
  }
  return warning;
}

// Judge what the signal evaluated to: `{ sources }` (sorted, deduped, blanks
// dropped) for a usable answer, `{ warning }` for a throw or a value that is not
// an array of strings, and neither for an empty answer — "no information",
// which the editor already treats as "keep the static render set".
function renderedSourcesFromOutcome(outcome, signal) {
  if (outcome && outcome.error != null) {
    return {
      warning: `rendered-sources: \`${signal}\` threw (${outcome.error}); staleness keeps this scenario's full static render set. Fix capture.renderedSourcesSignal in .codeyam/stack.json or the app code that publishes it.`,
    };
  }
  const value = outcome ? outcome.value : undefined;
  if (!Array.isArray(value) || value.some((s) => typeof s !== "string")) {
    const shape = Array.isArray(value) ? "an array with non-string entries" : typeof value;
    return {
      warning: `rendered-sources: \`${signal}\` returned ${shape}, not an array of source paths; staleness keeps this scenario's full static render set.`,
    };
  }
  const sources = [...new Set(value.map((s) => s.trim()).filter((s) => s.length > 0))].sort();
  return sources.length > 0 ? { sources, warning: null } : { warning: null };
}

// A capture that armed attribution and then missed its ready signal is retried
// once unarmed: the attribution pauses can be what stalled the app's startup,
// and a slow attribution must never cost a screenshot. The retry writes no
// attribution record, and says so on its result.
async function retryUnarmedOnReadyTimeout(first, config, attempt) {
  const armed = first && first.renderedSourcesAttribution;
  const timedOut =
    first && Array.isArray(first.issues) && first.issues.some((i) => i.kind === "ready-signal");
  if (!armed || !timedOut) return first;
  const second = await attempt({ ...config, renderedSourcesAttribution: null });
  second.warnings = [
    ...(second.warnings || []),
    `rendered-sources: the capture missed its ready signal with ${armed.strategy} attribution armed, so it was retried without attribution and no attribution record was written; staleness keeps this scenario's full static render set.`,
  ];
  second.renderedSourcesAttribution = { ...armed, retriedUnarmed: true };
  return second;
}

module.exports = {
  ATTRIBUTION_STRATEGIES,
  resolveRenderedSourcesAttribution,
  cachedWorkspaceCrates,
  installWasmCompilePause,
  functionRangesFor,
  takeRetiredBreakpointIds,
  watchWasmFunctionEntries,
  renderedSourcesRecordPath,
  evaluateRenderedSourcesSignal,
  recordRenderedSources,
  renderedSourcesFromOutcome,
  armRenderedSourcesAttribution,
  attributedRecordVerdict,
  mergeRenderedSourcesRecord,
  retryUnarmedOnReadyTimeout,
};
