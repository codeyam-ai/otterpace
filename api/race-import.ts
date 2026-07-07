import type { VercelRequest, VercelResponse } from "@vercel/node";
import Anthropic from "@anthropic-ai/sdk";
import { allow, clientIp } from "./_lib/ratelimit.js";

// Otterpace race import — stateless BYO-key proxy (URL -> structured race).
//
// The iOS app POSTs { url } here with the user's own Anthropic key in the
// `x-anthropic-key` header. We fetch the race's web page server-side, strip it to
// bounded text, and ask Claude to extract a structured race (name, date, distance,
// location) constrained to a strict JSON schema. The app opens its normal race
// editor pre-filled with the result, so the human always confirms before saving.
//
// Why server-side fetch + extraction (not on-device): the app must not fetch
// arbitrary HTML (privacy, SSRF surface, CSP, page-size blowups), and keeping the
// extraction prompt here means it can be tuned without an App Store release. Like
// the coach proxy, the key is used for this one request and never stored or logged.

const MODEL = process.env.COACH_MODEL || "claude-opus-4-8";

const SYSTEM_PROMPT = `You extract structured details about a single running race from the text of its web page. You return ONLY the fields you can find; you never invent or guess a value that is not clearly supported by the text.

Rules:
- name: the race's proper name (e.g. "October Trail Half Marathon"). Use the most specific event name, not the org or series alone.
- date: the race date as yyyy-MM-dd. If only a month and year are given, or the date is ambiguous, omit it rather than guessing a day.
- distanceMiles: the race distance in miles as a number. Convert from km if the page lists km (1 mi = 1.609344 km). A marathon is 26.2, a half is 13.1, a 10K is 6.2, a 5K is 3.1. If several distances are offered (a race with multiple events), pick the single most prominent one and note the others in the notes.
- unit: "miles" or "kilometers" — the unit the page primarily expresses the distance in, so the app can display it the way the runner expects. Default to "miles" if unclear.
- location: city and state/region, or the venue (e.g. "Bend, OR").
- notes: a short, optional free-text note only if the page states something genuinely useful (start time, elevation, other distances offered). Keep it under 140 characters. Omit if nothing stands out.
- confidence: your overall confidence that the extracted race is correct, 0.0 to 1.0.
- missingFields: an array naming any of ["name","date","distanceMiles","location"] you could NOT determine from the text, so the app can flag them for the user to fill in.

Never fabricate. If the page does not clearly describe a specific race, return empty/omitted fields, a low confidence, and list what is missing.`;

// Structured output: constrain Claude to exactly the shape the Swift
// RaceImportResult decoder expects. All race fields optional (a sparse page may
// yield only some), so the app can pre-fill what was found and flag the rest.
const FORMAT = {
  type: "json_schema" as const,
  schema: {
    type: "object",
    properties: {
      race: {
        type: "object",
        properties: {
          name: { type: "string" },
          date: { type: "string", description: "yyyy-MM-dd, omitted if unknown" },
          distanceMiles: { type: "number" },
          unit: { type: "string", enum: ["miles", "kilometers"] },
          location: { type: "string" },
          notes: { type: "string" },
        },
        additionalProperties: false,
      },
      confidence: { type: "number", description: "0.0 to 1.0" },
      missingFields: { type: "array", items: { type: "string" } },
    },
    required: ["race", "confidence", "missingFields"],
    additionalProperties: false,
  },
};

// Bounds. The URL is short; the fetched page is capped so a huge page can't blow
// up token spend on the user's key, and the fetch has a short timeout + no
// redirect-following so it can't be steered onto an internal host mid-redirect.
const MAX_URL_LEN = 2048;
const MAX_PAGE_BYTES = 512 * 1024;
const MAX_EXTRACT_CHARS = 24 * 1024;
const FETCH_TIMEOUT_MS = 8000;

/** Reject non-http(s) URLs and hosts that point at the local network (SSRF). */
function isSafePublicUrl(raw: string): URL | null {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return null;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return null;
  const host = u.hostname.toLowerCase();
  if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local")) return null;
  if (host === "0.0.0.0" || host === "::1" || host === "[::1]") return null;
  // Block IPv4 literals in private / loopback / link-local ranges.
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (m) {
    const [a, b] = [Number(m[1]), Number(m[2])];
    if (a === 127 || a === 10 || a === 0) return null;
    if (a === 169 && b === 254) return null; // link-local (incl. cloud metadata 169.254.169.254)
    if (a === 192 && b === 168) return null;
    if (a === 172 && b >= 16 && b <= 31) return null;
  }
  return u;
}

/** Crudely reduce HTML to readable text: drop scripts/styles/tags, collapse space. */
function htmlToText(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim();
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  if (!allow(`race-import:${clientIp(req)}`, 15, 60_000, Date.now())) {
    res.status(429).json({ error: "rate_limited", message: "One sec. Too many imports just now. Try again in a moment." });
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

  const body = (req.body ?? {}) as { url?: string };
  const rawUrl = (body.url ?? "").toString().trim();
  if (!rawUrl) {
    res.status(400).json({ error: "missing_url" });
    return;
  }
  if (rawUrl.length > MAX_URL_LEN) {
    res.status(413).json({ error: "url_too_long" });
    return;
  }
  const url = isSafePublicUrl(rawUrl);
  if (!url) {
    res.status(400).json({ error: "invalid_url", message: "That doesn't look like a valid public race URL." });
    return;
  }

  // Fetch the page server-side, bounded by a timeout and no redirect-following so
  // it can't be bounced onto an internal host after the safety check.
  let pageText: string;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    let pageRes: Response;
    try {
      pageRes = await fetch(url.toString(), {
        method: "GET",
        redirect: "error",
        signal: controller.signal,
        headers: { "user-agent": "OtterpaceBot/1.0 (+https://otterpace.com)", accept: "text/html" },
      });
    } finally {
      clearTimeout(timer);
    }
    if (!pageRes.ok) {
      res.status(422).json({ error: "fetch_failed", message: "Couldn't load that page. Check the link, or add the race manually." });
      return;
    }
    const buf = await pageRes.arrayBuffer();
    if (buf.byteLength > MAX_PAGE_BYTES) {
      res.status(413).json({ error: "page_too_large", message: "That page is too large to import. Add the race manually." });
      return;
    }
    pageText = htmlToText(new TextDecoder().decode(buf)).slice(0, MAX_EXTRACT_CHARS);
  } catch {
    res.status(422).json({ error: "fetch_failed", message: "Couldn't load that page. Check the link, or add the race manually." });
    return;
  }

  if (!pageText) {
    res.status(200).json({ race: {}, confidence: 0, missingFields: ["name", "date", "distanceMiles", "location"] });
    return;
  }

  const client = new Anthropic({ apiKey });
  try {
    const message = await client.messages.create({
      model: MODEL,
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      output_config: { format: FORMAT },
      messages: [
        {
          role: "user",
          content: `Source URL: ${url.toString()}\n\nPage text:\n${pageText}\n\nExtract the race.`,
        },
      ],
    });

    if (message.stop_reason === "refusal") {
      res.status(200).json({ race: {}, confidence: 0, missingFields: ["name", "date", "distanceMiles", "location"] });
      return;
    }

    const textBlock = message.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      res.status(502).json({ error: "no_text" });
      return;
    }

    let parsed: { race?: unknown; confidence?: unknown; missingFields?: unknown };
    try {
      parsed = JSON.parse(textBlock.text);
    } catch {
      res.status(200).json({ race: {}, confidence: 0, missingFields: ["name", "date", "distanceMiles", "location"] });
      return;
    }
    res.status(200).json({
      race: parsed.race ?? {},
      confidence: typeof parsed.confidence === "number" ? parsed.confidence : 0,
      missingFields: Array.isArray(parsed.missingFields) ? parsed.missingFields : [],
    });
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
