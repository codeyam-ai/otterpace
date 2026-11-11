// Token-cost profile of a Claude Code session transcript: where the tokens
// went, not just how many there were.
//
// Cost in an agent session is roughly turns × context size, so a total alone
// says nothing actionable. This module reads the `usage` block every assistant
// record carries and reports the drivers: the per-turn context curve, how cost
// splits across cache reads / cache writes / output / uncached input,
// compactions, the context each tool result keeps CARRYING until the next
// compaction, and the cost of each workflow step.
//
// Pure: callers hand it parsed records (or raw JSONL lines) and get a plain
// object back. Rendering lives in session-tokens-report.mjs.

import { createCarriedTracker } from './session-tokens-carried.mjs';
import { sourcesForToolUse } from './session-tokens-labels.mjs';
import { stepFromBanner, stepFromHook, stepLabel } from './session-tokens-steps.mjs';

/**
 * Relative price weights, as multiples of the uncached input price. These are
 * list-price RATIOS for comparing where cost goes, not billing figures.
 */
export const PRICE_WEIGHTS = Object.freeze({ input: 1, cacheWrite: 1.25, cacheRead: 0.1, output: 5 });

/** Fixed token estimate per image block — base64 length overstates it ~50×. */
export const IMAGE_TOKENS = 1600;

/** Text is estimated at ~4 characters per token. */
export const CHARS_PER_TOKEN = 4;

const PRE_STEP = '(before first step)';

/** Parse a JSONL line, or pass an already-parsed record through. */
function toRecord(line) {
  if (line && typeof line === 'object') return line;
  if (typeof line !== 'string' || !line.trim()) return null;
  try {
    return JSON.parse(line);
  } catch {
    return null;
  }
}

/** Estimated tokens for one tool_result `content` value (string or block array). */
export function estimateResultTokens(content) {
  if (content == null) return 0;
  if (typeof content === 'string') return Math.ceil(content.length / CHARS_PER_TOKEN);
  if (!Array.isArray(content)) return Math.ceil(JSON.stringify(content).length / CHARS_PER_TOKEN);
  let tokens = 0;
  for (const block of content) {
    if (block?.type === 'image') tokens += IMAGE_TOKENS;
    else if (block?.type === 'text') tokens += Math.ceil((block.text || '').length / CHARS_PER_TOKEN);
    else tokens += Math.ceil(JSON.stringify(block).length / CHARS_PER_TOKEN);
  }
  return tokens;
}

/** Plain text of a tool_result `content`, for step-banner scanning. */
function resultText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((b) => (b?.type === 'text' ? b.text || '' : '')).join('\n');
}

function emptyUsage() {
  return { input: 0, cacheWrite: 0, cacheRead: 0, output: 0 };
}

function weightedCost(u) {
  return (
    u.input * PRICE_WEIGHTS.input +
    u.cacheWrite * PRICE_WEIGHTS.cacheWrite +
    u.cacheRead * PRICE_WEIGHTS.cacheRead +
    u.output * PRICE_WEIGHTS.output
  );
}

function addUsage(into, u) {
  into.input += u.input;
  into.cacheWrite += u.cacheWrite;
  into.cacheRead += u.cacheRead;
  into.output += u.output;
}

/** Normalize an API `usage` block to the four cost categories. */
function readUsage(usage) {
  return {
    input: usage.input_tokens || 0,
    cacheWrite: usage.cache_creation_input_tokens || 0,
    cacheRead: usage.cache_read_input_tokens || 0,
    output: usage.output_tokens || 0,
  };
}

function isCompaction(obj) {
  return (obj.type === 'system' && obj.subtype === 'compact_boundary') || obj.isCompactSummary === true;
}

/**
 * Profile one session.
 *
 * @param {Iterable<string|object>} lines  main transcript records
 * @param {object} [opts]
 * @param {'last'|'even'} [opts.attribution='last']  how a chained Bash
 *   command's output is split across its subcommands
 * @param {Iterable<string|object>} [opts.subagentLines]  records from a
 *   separate subagent transcript; always counted as sidechain
 */
export function profileSession(lines, { attribution = 'last', subagentLines = [] } = {}) {
  const turns = new Map(); // message.id → { usage, sidechain, step }
  const toolUses = new Map(); // tool_use id → sources
  const carried = createCarriedTracker();
  let compactions = 0;
  let step = PRE_STEP;
  let format = null;

  const visitAssistant = (obj, msg, sidechain) => {
    format = 'claude';
    if (msg.usage && msg.id) {
      const known = turns.get(msg.id);
      if (!known) {
        turns.set(msg.id, { usage: readUsage(msg.usage), sidechain, step });
        if (!sidechain) carried.turn();
      } else {
        // Streaming re-emits the same message with a growing usage block;
        // the last one seen is the settled figure.
        known.usage = readUsage(msg.usage);
      }
    }
    for (const item of Array.isArray(msg.content) ? msg.content : []) {
      if (item?.type === 'tool_use') toolUses.set(item.id, sourcesForToolUse(item, attribution));
    }
  };

  const visitUser = (obj, msg) => {
    if (typeof msg.content === 'string') {
      if (!obj.isCompactSummary) carried.add([{ label: 'user prompt', weight: 1 }], estimateResultTokens(msg.content));
      return;
    }
    for (const item of Array.isArray(msg.content) ? msg.content : []) {
      if (item?.type !== 'tool_result') continue;
      step = stepFromBanner(resultText(item.content)) ?? step;
      const parts = toolUses.get(item.tool_use_id) || [{ label: '(unknown tool)', weight: 1 }];
      carried.add(parts, estimateResultTokens(item.content));
    }
  };

  const visit = (obj, forceSidechain) => {
    const sidechain = forceSidechain || obj.isSidechain === true;
    if (!sidechain && isCompaction(obj)) {
      carried.flush();
      compactions++;
      return;
    }
    if (obj.type === 'attachment') {
      const content = obj.attachment?.content;
      if (typeof content !== 'string' || sidechain) return;
      step = stepFromHook(content) ?? step;
      const { hookEvent, type } = obj.attachment;
      carried.add([{ label: hookEvent ? `hook:${hookEvent}` : `attachment:${type}`, weight: 1 }], estimateResultTokens(content));
      return;
    }
    if (obj.type === 'assistant' && obj.message) visitAssistant(obj, obj.message, sidechain);
    else if (obj.type === 'user' && obj.message && !sidechain) visitUser(obj, obj.message);
  };

  for (const line of lines) {
    const obj = toRecord(line);
    if (obj) visit(obj, false);
  }
  for (const line of subagentLines) {
    const obj = toRecord(line);
    if (obj) visit(obj, true);
  }
  carried.flush();

  return summarize({ turns, sources: carried.rows(), compactions, attribution, format });
}

function summarize({ turns, sources, compactions, attribution, format }) {
  const main = emptyUsage();
  const sub = emptyUsage();
  const contexts = [];
  const steps = new Map();
  let subTurns = 0;
  for (const t of turns.values()) {
    if (t.sidechain) {
      addUsage(sub, t.usage);
      subTurns++;
      continue;
    }
    addUsage(main, t.usage);
    const context = t.usage.input + t.usage.cacheWrite + t.usage.cacheRead;
    contexts.push(context);
    if (!steps.has(t.step)) steps.set(t.step, { step: t.step, turns: 0, cost: 0, contextSum: 0 });
    const row = steps.get(t.step);
    row.turns++;
    row.cost += weightedCost(t.usage);
    row.contextSum += context;
  }
  const contextSum = contexts.reduce((a, b) => a + b, 0);
  return {
    format,
    attribution,
    priceWeights: PRICE_WEIGHTS,
    turns: contexts.length,
    usage: main,
    weightedCost: weightedCost(main),
    context: {
      sum: contextSum,
      average: contexts.length ? contextSum / contexts.length : 0,
      peak: contexts.length ? Math.max(...contexts) : 0,
      floor: contexts.length ? Math.min(...contexts) : 0,
    },
    compactions,
    sources,
    steps: [...steps.values()],
    subagents: { turns: subTurns, usage: sub, weightedCost: weightedCost(sub) },
  };
}

/**
 * True when the transcript's first recorded `cwd` is `projectDir` or inside it.
 * A fleet roll-up filters on this header rather than on file size: health
 * probes are ~200KB each, so a size floor cannot tell them from real sessions.
 */
export function belongsToProject(lines, projectDir) {
  for (const line of lines) {
    const obj = toRecord(line);
    if (typeof obj?.cwd === 'string') return obj.cwd === projectDir || obj.cwd.startsWith(`${projectDir}/`);
  }
  return false;
}

/** Roll many session profiles into one fleet-level profile of the same shape. */
export function aggregateProfiles(profiles) {
  const usage = emptyUsage();
  const subUsage = emptyUsage();
  const sources = new Map();
  const steps = new Map();
  let turns = 0;
  let contextSum = 0;
  let peak = 0;
  let floor = null;
  let compactions = 0;
  let subTurns = 0;
  for (const p of profiles) {
    addUsage(usage, p.usage);
    addUsage(subUsage, p.subagents.usage);
    subTurns += p.subagents.turns;
    turns += p.turns;
    contextSum += p.context.sum;
    compactions += p.compactions;
    if (p.turns > 0) {
      peak = Math.max(peak, p.context.peak);
      floor = floor === null ? p.context.floor : Math.min(floor, p.context.floor);
    }
    for (const s of p.sources) {
      const row = sources.get(s.label) || { label: s.label, count: 0, tokens: 0, carried: 0 };
      row.count += s.count;
      row.tokens += s.tokens;
      row.carried += s.carried;
      sources.set(s.label, row);
    }
    for (const s of p.steps) {
      const label = stepLabel(s.step);
      const row = steps.get(label) || { step: label, turns: 0, cost: 0, contextSum: 0 };
      row.turns += s.turns;
      row.cost += s.cost;
      row.contextSum += s.contextSum;
      steps.set(label, row);
    }
  }
  return {
    sessions: profiles.length,
    attribution: profiles[0]?.attribution ?? 'last',
    priceWeights: PRICE_WEIGHTS,
    turns,
    usage,
    weightedCost: weightedCost(usage),
    context: { sum: contextSum, average: turns ? contextSum / turns : 0, peak, floor: floor ?? 0 },
    compactions,
    sources: [...sources.values()].sort((a, b) => b.carried - a.carried),
    steps: [...steps.values()].sort((a, b) => b.cost - a.cost),
    subagents: { turns: subTurns, usage: subUsage, weightedCost: weightedCost(subUsage) },
  };
}
