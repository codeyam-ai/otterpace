// Labels a Bash tool call by the command(s) it ran, so a token report can
// attribute the call's output to something a reader recognises.
//
// A chained call (`codeyam-editor editor track-step created; codeyam-editor
// editor scenarios …`) is split into one label per command. Labelling the
// whole chain after its FIRST command is the defect this exists to prevent:
// it once blamed `track-step`, which prints one line, for 30% of a session's
// context. The split is quote- and heredoc-aware, so a `;` inside
// `node -e '…'` or a heredoc body is not mistaken for a separator.

const EDITOR_RE = /\bcodeyam-editor(?:-dev)?\s+editor\s+([A-Za-z0-9][\w-]*)/;
const HEREDOC_RE = /<<-?\s*(['"]?)([A-Za-z_]\w*)\1/;

/** Split a shell command list on `;`, `&&`, `||` and newlines outside quotes and heredoc bodies. */
export function splitCommandList(command) {
  const segments = [];
  let current = '';
  let quote = null;
  let heredoc = null;
  const lines = command.split('\n');
  for (let li = 0; li < lines.length; li++) {
    const line = lines[li];
    if (heredoc) {
      if (line.trim() === heredoc) heredoc = null;
      continue;
    }
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (quote) {
        if (ch === quote) quote = null;
        else if (ch === '\\' && quote === '"') {
          current += ch + (line[i + 1] ?? '');
          i++;
          continue;
        }
        current += ch;
        continue;
      }
      if (ch === "'" || ch === '"') {
        quote = ch;
        current += ch;
        continue;
      }
      const two = line.slice(i, i + 2);
      if (ch === ';' || two === '&&' || two === '||') {
        segments.push(current);
        current = '';
        if (ch !== ';') i++;
        continue;
      }
      current += ch;
    }
    if (quote) {
      current += '\n';
      continue;
    }
    const hd = HEREDOC_RE.exec(current);
    if (hd) heredoc = hd[2];
    segments.push(current);
    current = '';
  }
  if (current) segments.push(current);
  return segments.map((s) => s.trim()).filter(Boolean);
}

/** Label one command segment, or null for a segment that only sets up the shell. */
function labelSegment(segment) {
  const editor = EDITOR_RE.exec(segment);
  if (editor) return `editor ${editor[1]}`;
  const words = segment.split('|')[0].trim().split(/\s+/);
  while (words.length && /^[A-Za-z_]\w*=/.test(words[0])) words.shift();
  const head = words[0];
  if (!head || head === 'cd' || head === 'export' || head === 'set' || head === 'echo') return null;
  return `bash:${head.split('/').pop()}`;
}

/** Labels for every command in a Bash call, in order. Empty when none is labelable. */
export function labelBashCommand(command) {
  return splitCommandList(command).map(labelSegment).filter(Boolean);
}

/**
 * The context sources a `tool_use` block's result is attributed to, as
 * `[{ label, weight }]` with weights summing to 1. A chained Bash call goes
 * to its last command (`attribution: 'last'`) or is split evenly across every
 * command (`'even'`); any other tool is attributed to its own name.
 */
export function sourcesForToolUse(item, attribution) {
  if (item.name === 'Bash' && typeof item.input?.command === 'string') {
    const labels = labelBashCommand(item.input.command);
    if (labels.length === 0) return [{ label: 'Bash', weight: 1 }];
    if (attribution === 'last') return [{ label: labels[labels.length - 1], weight: 1 }];
    return labels.map((label) => ({ label, weight: 1 / labels.length }));
  }
  return [{ label: item.name || '?', weight: 1 }];
}
