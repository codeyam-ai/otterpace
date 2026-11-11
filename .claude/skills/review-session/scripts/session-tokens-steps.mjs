// Workflow-step tagging for the token report: which editor step a turn ran in.
//
// Two signals mark a step. The editor's PostToolUse hook prefixes its context
// line with `[Step N: Label]`, and every step hand-off prints a
// `STEP N: Label ━━━` banner. A step is keyed by label as well as number,
// because UI and backend flows number the same step differently.

const HOOK_STEP_RE = /^\[Step (\d+): ([^\]]+)\]/;
const BANNER_STEP_RE = /STEP (\d+): ([^━\n]+?) ━━━/g;

/** The step key a hook attachment's content announces, or null. Only a LEADING tag counts. */
export function stepFromHook(content) {
  const m = HOOK_STEP_RE.exec(content);
  return m ? `${m[1]}: ${m[2].trim()}` : null;
}

/** The step key of the LAST hand-off banner in a tool result's text, or null. */
export function stepFromBanner(text) {
  let last = null;
  for (const m of text.matchAll(BANNER_STEP_RE)) last = m;
  return last ? `${last[1]}: ${last[2].trim()}` : null;
}

/** A step key without its number (`"9: Extract TDD"` → `"Extract TDD"`); other keys pass through. */
export function stepLabel(key) {
  const i = key.indexOf(': ');
  return i >= 0 && /^\d+$/.test(key.slice(0, i)) ? key.slice(i + 2) : key;
}
