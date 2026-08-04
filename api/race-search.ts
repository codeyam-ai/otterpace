import type { VercelRequest, VercelResponse } from "@vercel/node";
import { allow, clientIp } from "./_lib/ratelimit.js";
import { complete, credentialsFromHeaders, LlmError } from "./_lib/llm.js";

// Otterpace race search — stateless BYO-key proxy (name -> candidate races).
//
// The iOS app POSTs { query } here with the user's own provider key (any of the
// three the shared router supports). We ask
// Claude to propose a short list of real races matching the name, each with a
// best-effort source URL, and return them for the user to pick from. Picking a
// candidate opens the app's race editor pre-filled (optionally re-importing full
// detail from the candidate's sourceUrl via api/race-import), so the human always
// confirms before saving.
//
// NOTE: this returns model-proposed candidates, not verified search results. A
// server-side web-search dependency (a search API key env var) would make these
// authoritative; until then the confirm-in-editor step and the per-candidate
// sourceUrl are what keep a wrong guess from being saved silently.


const SYSTEM_PROMPT = `You help a runner find a specific upcoming race by name. Given a short query (a race name, possibly with a city or year), propose up to 5 real races that plausibly match.

Rules:
- Return real, well-known races when the query clearly names one. Do NOT invent races to pad the list. If you are unsure a race exists, return fewer results (or none) rather than fabricating.
- name: the race's proper name.
- date: the next likely running as yyyy-MM-dd if you are reasonably sure; otherwise omit it (the app will ask the user).
- distanceMiles: the race's distance in miles as a number (convert from km if needed; marathon 26.2, half 13.1, 10K 6.2, 5K 3.1). Omit if a race offers many distances with no single primary one.
- unit: "miles" or "kilometers", how the race usually expresses its distance.
- location: city and state/region.
- sourceUrl: the race's official website if you know it, so the user can open it or import full detail. Omit rather than guess a URL that may not exist.
- Order by how well each matches the query (best first).

Prefer precision over volume. A single confident match is better than five vague ones.`;

// Structured output: a small, capped list of candidates. Every field except name
// is optional so a partially-known race still lists.
const FORMAT = {
  type: "json_schema" as const,
  schema: {
    type: "object",
    properties: {
      results: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            date: { type: "string", description: "yyyy-MM-dd, omitted if unknown" },
            distanceMiles: { type: "number" },
            unit: { type: "string", enum: ["miles", "kilometers"] },
            location: { type: "string" },
            sourceUrl: { type: "string" },
          },
          required: ["name"],
          additionalProperties: false,
        },
      },
    },
    required: ["results"],
    additionalProperties: false,
  },
};

const MAX_QUERY_LEN = 200;
const MAX_RESULTS = 5;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  if (!allow(`race-search:${clientIp(req)}`, 20, 60_000, Date.now())) {
    res.status(429).json({ error: "rate_limited", message: "One sec. Too many searches just now. Try again in a moment." });
    return;
  }

  const contentType = (req.headers["content-type"] ?? "").toString();
  if (!contentType.includes("application/json")) {
    res.status(415).json({ error: "unsupported_media_type" });
    return;
  }

  const credentials = credentialsFromHeaders(req.headers as Record<string, unknown>);
  if (!credentials) {
    res.status(400).json({ error: "missing_key", message: "Connect an AI provider API key in Settings." });
    return;
  }

  const body = (req.body ?? {}) as { query?: string };
  const query = (body.query ?? "").toString().trim();
  if (!query) {
    res.status(400).json({ error: "missing_query" });
    return;
  }
  if (query.length > MAX_QUERY_LEN) {
    res.status(413).json({ error: "query_too_long" });
    return;
  }

  try {
    const result = await complete(credentials, {
      system: SYSTEM_PROMPT,
      schema: FORMAT.schema,
      schemaName: "race_search",
      maxTokens: 1024,
      messages: [{ role: "user", content: `Find races matching: ${query}` }],
    });

    if (result.kind === "empty") {
      res.status(502).json({ error: "no_text" });
      return;
    }
    // No candidates is a normal outcome for a search, so a refusal or an
    // unusable reply degrades to an empty result list rather than an error.
    if (result.kind !== "json") {
      res.status(200).json({ results: [] });
      return;
    }

    const parsed = result.value;
    const results = Array.isArray(parsed.results) ? parsed.results.slice(0, MAX_RESULTS) : [];
    res.status(200).json({ results });
  } catch (err) {
    if (err instanceof LlmError) {
      res.status(err.status).json({ error: err.code, message: err.message });
      return;
    }
    res.status(502).json({ error: "upstream_error" });
  }
}
