// Renders a session-tokens.mjs profile (one session, or an aggregate) as
// markdown. Every cost figure is RELATIVE — weighted by list-price ratios —
// and the report says so, so nobody reads it as a bill.

import { CHARS_PER_TOKEN, IMAGE_TOKENS } from './session-tokens.mjs';

const TOP_SOURCES = 15;

function fmt(n) {
  if (n >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `${(n / 1e6).toFixed(2)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)}k`;
  return String(Math.round(n));
}

function pct(part, whole) {
  return whole > 0 ? `${((100 * part) / whole).toFixed(1)}%` : '—';
}

function costSplitLines(usage, weights) {
  const parts = [
    ['Cache reads', usage.cacheRead, weights.cacheRead],
    ['Cache writes', usage.cacheWrite, weights.cacheWrite],
    ['Output', usage.output, weights.output],
    ['Uncached input', usage.input, weights.input],
  ];
  const total = parts.reduce((a, [, t, w]) => a + t * w, 0);
  const tokenTotal = parts.reduce((a, [, t]) => a + t, 0);
  const lines = ['| Category | Tokens | Token share | Weight | Cost share |', '|---|---:|---:|---:|---:|'];
  for (const [name, tokens, w] of parts) {
    lines.push(`| ${name} | ${fmt(tokens)} | ${pct(tokens, tokenTotal)} | ${w}× | ${pct(tokens * w, total)} |`);
  }
  return lines;
}

/** Markdown token report for a profile from `profileSession` or `aggregate`. */
export function renderTokensMarkdown(profile, { title = 'Token Cost' } = {}) {
  const out = [`## ${title}`, ''];
  if (profile.sessions !== undefined) out.push(`Sessions: ${profile.sessions}`);
  if (profile.turns === 0) {
    out.push('No assistant turns with a `usage` block — nothing to report.', '');
    return out.join('\n');
  }
  const w = profile.priceWeights;
  out.push(
    `Main-thread turns: ${profile.turns} · Compactions: ${profile.compactions}`,
    `Relative cost: ${fmt(profile.weightedCost)} input-token-equivalents ` +
      `(list-price ratios: cache read ${w.cacheRead}×, cache write ${w.cacheWrite}×, output ${w.output}× the input price — relative, not billing)`,
    '',
    '### Context per turn',
    '',
    `Average ${fmt(profile.context.average)} · Peak ${fmt(profile.context.peak)} · Floor ${fmt(profile.context.floor)}`,
    '',
    '### Cost split',
    '',
    ...costSplitLines(profile.usage, w),
    '',
    `### Carried context by source (top ${TOP_SOURCES})`,
    '',
    'Carried = a result\'s estimated size × the main-thread turns it stays in context until the next compaction. ' +
      `Images count a fixed ${IMAGE_TOKENS} tokens each; text as chars/${CHARS_PER_TOKEN}. Chained \`codeyam-editor editor\` calls are attributed ` +
      (profile.attribution === 'even' ? 'evenly across every subcommand.' : 'to the LAST subcommand in the chain.'),
    '',
    '| Source | Results | Tokens added | Carried | Share of carried |',
    '|---|---:|---:|---:|---:|',
  );
  const carriedTotal = profile.sources.reduce((a, s) => a + s.carried, 0);
  for (const s of profile.sources.slice(0, TOP_SOURCES)) {
    out.push(`| ${s.label} | ${Number(s.count.toFixed(1))} | ${fmt(s.tokens)} | ${fmt(s.carried)} | ${pct(s.carried, carriedTotal)} |`);
  }
  out.push('', '### Cost per workflow step', '', '| Step | Turns | Avg context | Relative cost | Share |', '|---|---:|---:|---:|---:|');
  for (const s of profile.steps) {
    out.push(`| ${s.step} | ${s.turns} | ${fmt(s.contextSum / s.turns)} | ${fmt(s.cost)} | ${pct(s.cost, profile.weightedCost)} |`);
  }
  const sub = profile.subagents;
  out.push('', '### Subagents (sidechain)', '');
  if (sub.turns === 0) {
    out.push('None.');
  } else {
    out.push(
      `Turns: ${sub.turns} · Relative cost: ${fmt(sub.weightedCost)} (not included in the figures above)`,
      '',
      ...costSplitLines(sub.usage, w),
    );
  }
  out.push('');
  return out.join('\n');
}
