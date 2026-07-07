import type { VercelRequest, VercelResponse } from "@vercel/node";
import Anthropic from "@anthropic-ai/sdk";
import { allow, clientIp } from "./_lib/ratelimit.js";

// Otterpace race search — stateless BYO-key proxy (name -> candidate races).
//
// The iOS app POSTs { query } here with the user's own Anthropic key. We ask
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

const MODEL = process.env.COACH_MODEL || "claude-opus-4-8";

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

  const apiKey = req.headers["x-anthropic-key"];
  if (typeof apiKey !== "string" || apiKey.length < 8) {
    res.status(400).json({ error: "missing_key", message: "Connect your Anthropic API key in Settings." });
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

  const client = new Anthropic({ apiKey });
  try {
    const message = await client.messages.create({
      model: MODEL,
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      output_config: { format: FORMAT },
      messages: [{ role: "user", content: `Find races matching: ${query}` }],
    });

    if (message.stop_reason === "refusal") {
      res.status(200).json({ results: [] });
      return;
    }

    const textBlock = message.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      res.status(502).json({ error: "no_text" });
      return;
    }

    let parsed: { results?: unknown };
    try {
      parsed = JSON.parse(textBlock.text);
    } catch {
      res.status(200).json({ results: [] });
      return;
    }
    const results = Array.isArray(parsed.results) ? parsed.results.slice(0, MAX_RESULTS) : [];
    res.status(200).json({ results });
  } catch (err) {
    const status = (err as { status?: number }).status;
    if (status === 401) {
      res.status(401).json({ error: "invalid_key", message: "That API key was rejected by Anthropic." });
      return;
    }
    if (status === 429) {
      res.status(429).json({ error: "rate_limited", message: "Your Anthropic account is rate limited. Try again shortly." });
      return;
    }
    res.status(502).json({ error: "upstream_error" });
  }
}
