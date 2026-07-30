// Pure helpers extracted from extract-session.mjs so they're importable
// in tests without auto-running the script's top-level CLI dispatch.

/**
 * Decide the transcript format from the file path alone.
 *
 * Returns `'gemini'` for Gemini CLI paths (`/.gemini/` or `/chats/session-`),
 * `'claude'` for `/.claude/` paths, and `null` when the path is inconclusive
 * (e.g. a transcript fetched to `/tmp` during a fleet review). The caller
 * then falls back to a content scan via `detectFormatFromRecords`.
 */
export function detectFormatFromPath(inputFile) {
  if (inputFile.includes('/.gemini/') || /\/chats\/session-/.test(inputFile)) return 'gemini';
  if (inputFile.includes('/.claude/')) return 'claude';
  return null;
}

/**
 * Decide the transcript format by scanning a window of parseable records for
 * the first content-bearing Claude or Gemini shape. Returns `'claude'`,
 * `'gemini'`, or `null` when no record in the window is decisive.
 *
 * Critically, a bare top-level `sessionId` is NOT a Gemini signal: current
 * Claude transcripts lead with `last-prompt` / `bridge-session` records that
 * carry `sessionId` but no message body. Treating `sessionId` as Gemini (the
 * old heuristic) misclassified the entire file and parsed zero messages.
 */
export function detectFormatFromRecords(records) {
  for (const obj of records) {
    if (!obj || typeof obj !== 'object') continue;
    // Unambiguous Claude message/summary shapes.
    if ((obj.type === 'user' || obj.type === 'assistant') && obj.message) return 'claude';
    if (obj.type === 'summary' && 'summary' in obj) return 'claude';
    // Unambiguous Gemini shapes (never a bare `sessionId`).
    if (obj.kind === 'main') return 'gemini';
    if (obj.type === 'gemini') return 'gemini';
    if (obj.type === 'info' && typeof obj.content === 'string') return 'gemini';
    // Generic Claude fallback: a message body without an explicit recognised type.
    if (obj.message) return 'claude';
  }
  return null;
}

/**
 * Resolve the transcript format: prefer the path, then a content scan over the
 * sampled records, then `fallback` (historically `'gemini'`) only once the
 * window is exhausted — so a leading metadata preamble can't short-circuit it.
 */
export function detectFormat(inputFile, records, fallback = 'gemini') {
  return detectFormatFromPath(inputFile) ?? detectFormatFromRecords(records) ?? fallback;
}

/**
 * Truncate `s` to `max` characters, appending a `...[truncated]`
 * marker when the value was cut.
 */
export function truncate(s, max) {
  return s.length > max ? s.slice(0, max) + '...[truncated]' : s;
}

/**
 * Format a timestamp as an `HH:MM:SS` string, returning `'?'` when
 * the value is falsy or unparseable.
 */
export function formatTs(ts) {
  if (!ts) return '?';
  try {
    return new Date(ts).toISOString().replace('T', ' ').slice(11, 19);
  } catch {
    return String(ts);
  }
}

/**
 * Push a Claude transcript record onto `messages`, normalizing
 * user / assistant / tool_use / tool_result shapes into the shared
 * review-session message format.
 */
export function appendClaudeMessage(obj, messages) {
  if (!obj.type) return;

  if (obj.type === 'user') {
    const content = obj.message?.content;
    if (!content) return;
    if (typeof content === 'string') {
      messages.push({ role: 'user', text: content, ts: obj.timestamp });
    } else if (Array.isArray(content)) {
      const parts = [];
      let hasError = false;
      for (const item of content) {
        if (item.type === 'tool_result') {
          const t = typeof item.content === 'string' ? item.content : JSON.stringify(item.content);
          if (item.is_error) hasError = true;
          parts.push({ kind: 'tool_result', error: !!item.is_error, text: truncate(t, 800) });
        } else if (typeof item === 'string') {
          parts.push({ kind: 'text', text: item });
        } else if (item.type === 'text') {
          parts.push({ kind: 'text', text: item.text });
        }
      }
      messages.push({ role: 'user_complex', parts, hasError, ts: obj.timestamp });
    }
    return;
  }

  if (obj.type === 'assistant') {
    const items = obj.message?.content;
    if (!Array.isArray(items)) return;
    const parts = [];
    for (const item of items) {
      if (item.type === 'text' && item.text) {
        parts.push({ kind: 'text', text: item.text });
      } else if (item.type === 'thinking') {
        const t = item.thinking || '';
        parts.push({ kind: 'thinking', text: truncate(t, 1500) });
      } else if (item.type === 'tool_use') {
        const inputStr = typeof item.input === 'string' ? item.input : JSON.stringify(item.input);
        parts.push({ kind: 'tool', name: item.name, input: truncate(inputStr, 500) });
      }
    }
    if (parts.length > 0) messages.push({ role: 'assistant', parts, ts: obj.timestamp });
  }
}

/**
 * Pull the textual `output` / `error` payload out of a Gemini tool
 * call's `result[]` array, returning `{ error, text }` or `null` when
 * no functionResponse was attached.
 */
export function extractGeminiToolResult(tc) {
  if (!Array.isArray(tc.result) || tc.result.length === 0) return null;
  const texts = [];
  let error = false;
  for (const r of tc.result) {
    const fr = r?.functionResponse?.response;
    if (!fr) continue;
    if (fr.error) {
      error = true;
      if (typeof fr.error === 'string') texts.push(fr.error);
      else texts.push(JSON.stringify(fr.error));
      continue;
    }
    if (typeof fr.output === 'string') texts.push(fr.output);
    else if (fr.output !== undefined) texts.push(JSON.stringify(fr.output));
    else texts.push(JSON.stringify(fr));
  }
  if (texts.length === 0) texts.push(JSON.stringify(tc.result));
  return { error, text: truncate(texts.join('\n'), 800) };
}

/**
 * Push a Gemini transcript record onto `messages`, normalizing
 * user / gemini / info shapes (including thoughts and tool calls)
 * into the shared review-session message format.
 */
export function appendGeminiMessage(obj, messages) {
  if (obj.type === 'user') {
    let text;
    if (typeof obj.content === 'string') {
      text = obj.content;
    } else if (Array.isArray(obj.content)) {
      text = obj.content
        .map((p) => (typeof p === 'string' ? p : p?.text || ''))
        .filter(Boolean)
        .join('\n');
    } else {
      return;
    }
    if (text && text.trim()) messages.push({ role: 'user', text, ts: obj.timestamp });
    return;
  }

  if (obj.type === 'gemini') {
    const parts = [];
    if (Array.isArray(obj.thoughts)) {
      for (const t of obj.thoughts) {
        const txt = typeof t === 'string' ? t : t?.text || '';
        if (!txt) continue;
        parts.push({ kind: 'thinking', text: truncate(txt, 1500) });
      }
    }
    if (typeof obj.content === 'string' && obj.content.length > 0) {
      parts.push({ kind: 'text', text: obj.content });
    }
    const toolResults = [];
    if (Array.isArray(obj.toolCalls)) {
      for (const tc of obj.toolCalls) {
        const inputStr = JSON.stringify(tc.args ?? {});
        parts.push({ kind: 'tool', name: tc.name || '?', input: truncate(inputStr, 500) });
        const result = extractGeminiToolResult(tc);
        if (result) toolResults.push(result);
      }
    }
    if (parts.length > 0) {
      messages.push({ role: 'assistant', parts, ts: obj.timestamp });
    }
    if (toolResults.length > 0) {
      messages.push({
        role: 'user_complex',
        parts: toolResults.map((r) => ({ kind: 'tool_result', error: r.error, text: r.text })),
        hasError: toolResults.some((r) => r.error),
        ts: obj.timestamp,
      });
    }
    return;
  }

  if (obj.type === 'info') {
    if (typeof obj.content === 'string' && obj.content.trim()) {
      messages.push({ role: 'user', text: `[info] ${obj.content}`, ts: obj.timestamp });
    }
  }
}
