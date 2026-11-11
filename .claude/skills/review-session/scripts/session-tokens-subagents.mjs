// Locates and reads the subagent transcripts Claude Code stores beside a
// session transcript, so the token report can show subagent cost separately
// from the main thread's.
//
// Layout: `<dir>/<uuid>.jsonl` is the session; its subagents live under
// `<dir>/<uuid>/subagents/*.jsonl`. Older transcripts instead inline subagent
// turns with `isSidechain: true`, which session-tokens.mjs handles directly.

import { readdir, readFile } from 'node:fs/promises';
import { basename, dirname, join } from 'node:path';

/** The directory holding `transcript`'s subagent transcripts (it may not exist). */
export function subagentTranscriptDir(transcript) {
  return join(dirname(transcript), basename(transcript, '.jsonl'), 'subagents');
}

/** Lines of every `.jsonl` subagent transcript beside `transcript`, or `[]` when there are none. */
export async function readSubagentLines(transcript) {
  const dir = subagentTranscriptDir(transcript);
  let names;
  try {
    names = (await readdir(dir)).filter((n) => n.endsWith('.jsonl')).sort();
  } catch {
    return []; // No subagent transcripts — the common case.
  }
  const lines = [];
  for (const name of names) lines.push(...(await readFile(join(dir, name), 'utf8')).split('\n'));
  return lines;
}
