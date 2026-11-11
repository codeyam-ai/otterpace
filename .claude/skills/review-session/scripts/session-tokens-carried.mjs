// Carried context: what a piece of context costs over its whole lifetime.
//
// A tool result is not paid for once. It sits in the prompt of every later
// turn until a compaction drops it, so its real cost is its size × the turns
// it is carried. This tracker records each addition against the turn it
// arrived on and settles the carried total when the context is flushed.

/**
 * Create a tracker. `add` records context arriving now; `turn` marks one
 * more main-thread turn; `flush` settles everything still in context (call
 * it at a compaction and at the end of the session); `rows` returns one row
 * per source label, most carried first.
 */
export function createCarriedTracker() {
  const sources = new Map(); // label → { label, count, tokens, carried }
  let active = []; // { parts, tokens, turnAt }
  let turns = 0;

  const row = (label) => {
    if (!sources.has(label)) sources.set(label, { label, count: 0, tokens: 0, carried: 0 });
    return sources.get(label);
  };

  return {
    /** Record `tokens` of context, split across `parts` (`[{ label, weight }]`, weights summing to 1). */
    add(parts, tokens) {
      for (const p of parts) {
        const r = row(p.label);
        r.count += p.weight;
        r.tokens += tokens * p.weight;
      }
      active.push({ parts, tokens, turnAt: turns });
    },
    turn() {
      turns++;
    },
    flush() {
      for (const a of active) {
        const carriedTurns = turns - a.turnAt;
        for (const p of a.parts) row(p.label).carried += a.tokens * p.weight * carriedTurns;
      }
      active = [];
    },
    rows() {
      return [...sources.values()].sort((a, b) => b.carried - a.carried);
    },
  };
}
