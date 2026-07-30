import Anthropic from "@anthropic-ai/sdk";

// Shared BYO-key LLM router.
//
// The three coach-backed endpoints (coach, race-import, race-search) all do the
// same thing: take the user's own key, send a curated system prompt plus some
// messages, and get back JSON matching a schema. Only the provider differs. That
// routing lives here so each endpoint stays a thin validate-then-call handler,
// and so provider behavior is tested in one place instead of three.
//
// The important invariant: the PROMPT does not vary by provider. Otterpace's
// coaching quality and safety rules are the product; the provider only changes
// which model generates the words. A provider that cannot honor the schema is a
// bug to fix here, not a reason to soften the prompt for it.
//
// Keys are used for exactly one request and never stored, logged, or persisted.

export type LlmProvider = "anthropic" | "openai" | "gemini";

const PROVIDERS: readonly LlmProvider[] = ["anthropic", "openai", "gemini"];

export function isLlmProvider(value: unknown): value is LlmProvider {
  return typeof value === "string" && (PROVIDERS as readonly string[]).includes(value);
}

// Model per provider, each overridable via env for cost/latency tuning without a
// redeploy of the app. The user pays on their own key, so the capable tier is
// the right default: this is their call, not ours.
const MODELS: Record<LlmProvider, string> = {
  anthropic: process.env.COACH_MODEL || "claude-opus-4-8",
  openai: process.env.COACH_MODEL_OPENAI || "gpt-5",
  gemini: process.env.COACH_MODEL_GEMINI || "gemini-2.5-pro",
};

export function modelFor(provider: LlmProvider): string {
  return MODELS[provider];
}

/** One conversation turn, in the shape every provider ultimately wants. */
export interface LlmTurn {
  role: "user" | "assistant";
  content: string;
}

export interface LlmRequest {
  system: string;
  messages: LlmTurn[];
  /** JSON Schema the reply must match. */
  schema: Record<string, unknown>;
  /** Schema name — required by OpenAI, ignored elsewhere. */
  schemaName: string;
  maxTokens?: number;
}

/**
 * What a provider returned, already normalized:
 *  - `json`       the model produced schema-shaped JSON (the happy path)
 *  - `refusal`    the model declined; the caller answers in Buddy's voice
 *  - `unusable`   text arrived but wasn't parseable JSON (e.g. truncated).
 *                 Distinct from an error because the user's key WAS billed, so
 *                 the caller degrades gracefully instead of 502-ing.
 *  - `empty`      the model produced no text at all. Kept separate from
 *                 `unusable` on purpose: the model saying something malformed is
 *                 a content problem the user can retry past with a clearer
 *                 question, while saying nothing is an upstream fault the app
 *                 should treat as a failed call.
 */
export type LlmResult =
  | { kind: "json"; value: Record<string, unknown> }
  | { kind: "refusal" }
  | { kind: "unusable" }
  | { kind: "empty" };

/** A provider-side failure, already mapped to the status the app expects. */
export class LlmError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "LlmError";
  }
}

// MARK: - Reading the key + provider off a request

/** Header names, shared with the iOS client's `CoachRequestHeaders`. */
export const PROVIDER_HEADER = "x-ai-provider";
export const KEY_HEADER = "x-ai-key";
export const LEGACY_ANTHROPIC_KEY_HEADER = "x-anthropic-key";

export interface LlmCredentials {
  provider: LlmProvider;
  apiKey: string;
}

/**
 * Pull the provider + key off the request headers, or null when absent/invalid.
 *
 * Accepts the legacy Anthropic-only header so an already-installed app keeps
 * working after this deploys — the app and the backend cannot ship atomically,
 * and dropping the old header would break every user who hasn't updated.
 * An explicit `x-ai-provider` always wins over the legacy inference.
 */
export function credentialsFromHeaders(
  headers: Record<string, unknown>,
): LlmCredentials | null {
  const rawKey = headers[KEY_HEADER] ?? headers[LEGACY_ANTHROPIC_KEY_HEADER];
  if (typeof rawKey !== "string") return null;
  const apiKey = rawKey.trim();
  if (apiKey.length < 8) return null;

  const rawProvider = headers[PROVIDER_HEADER];
  if (rawProvider !== undefined) {
    if (!isLlmProvider(rawProvider)) return null;
    return { provider: rawProvider, apiKey };
  }
  // No provider named: this is an older client, which only ever sent Anthropic.
  return { provider: "anthropic", apiKey };
}

// MARK: - Dispatch

/** Send one structured-output request on the user's key. */
export async function complete(
  { provider, apiKey }: LlmCredentials,
  request: LlmRequest,
): Promise<LlmResult> {
  switch (provider) {
    case "anthropic":
      return completeAnthropic(apiKey, request);
    case "openai":
      return completeOpenAI(apiKey, request);
    case "gemini":
      return completeGemini(apiKey, request);
  }
}

/** Parse a JSON payload into the normalized result, tolerating bad output. */
function parseJsonReply(text: string): LlmResult {
  try {
    const value = JSON.parse(text);
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return { kind: "unusable" };
    }
    return { kind: "json", value: value as Record<string, unknown> };
  } catch {
    return { kind: "unusable" };
  }
}

/** Map any provider's HTTP status onto the status the app already handles. */
function throwForStatus(status: number | undefined, provider: LlmProvider): never {
  const name = provider === "anthropic" ? "Anthropic" : provider === "openai" ? "OpenAI" : "Gemini";
  if (status === 401 || status === 403) {
    throw new LlmError(401, "invalid_key", `That API key was rejected by ${name}.`);
  }
  if (status === 429) {
    throw new LlmError(429, "rate_limited", `Your ${name} account is rate limited. Try again shortly.`);
  }
  throw new LlmError(502, "upstream_error", `${name} could not be reached.`);
}

// MARK: - Anthropic

async function completeAnthropic(apiKey: string, request: LlmRequest): Promise<LlmResult> {
  const client = new Anthropic({ apiKey });
  try {
    const message = await client.messages.create({
      model: MODELS.anthropic,
      max_tokens: request.maxTokens ?? 1024,
      system: request.system,
      output_config: { format: { type: "json_schema", schema: request.schema } },
      messages: request.messages.map((t) => ({ role: t.role, content: t.content })),
    } as never);

    const msg = message as { stop_reason?: string; content?: Array<{ type: string; text?: string }> };
    if (msg.stop_reason === "refusal") return { kind: "refusal" };
    const textBlock = (msg.content ?? []).find((b) => b.type === "text");
    if (!textBlock?.text) return { kind: "empty" };
    return parseJsonReply(textBlock.text);
  } catch (err) {
    if (err instanceof LlmError) throw err;
    throwForStatus((err as { status?: number }).status, "anthropic");
  }
}

// MARK: - OpenAI
//
// Chat Completions with a strict json_schema response format. Reached over plain
// fetch rather than the SDK: it is one request shape, and every extra dependency
// is weight in a serverless bundle that cold-starts on each user's key.

async function completeOpenAI(apiKey: string, request: LlmRequest): Promise<LlmResult> {
  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: MODELS.openai,
        max_completion_tokens: request.maxTokens ?? 1024,
        messages: [
          { role: "system", content: request.system },
          ...request.messages.map((t) => ({ role: t.role, content: t.content })),
        ],
        response_format: {
          type: "json_schema",
          json_schema: { name: request.schemaName, schema: request.schema, strict: true },
        },
      }),
    });
  } catch {
    throw new LlmError(502, "upstream_error", "OpenAI could not be reached.");
  }

  if (!response.ok) throwForStatus(response.status, "openai");

  const body = (await response.json().catch(() => null)) as {
    choices?: Array<{ message?: { content?: string | null; refusal?: string | null } }>;
  } | null;
  const choice = body?.choices?.[0]?.message;
  // A strict-schema refusal comes back in its own field, with content null.
  if (choice?.refusal) return { kind: "refusal" };
  if (typeof choice?.content !== "string" || !choice.content) return { kind: "empty" };
  return parseJsonReply(choice.content);
}

// MARK: - Gemini
//
// generateContent with a response schema. Gemini has no system role: the system
// prompt goes in `systemInstruction`, and its schema dialect is a subset of JSON
// Schema that rejects `additionalProperties`, so the schema is adapted below.

/** Strip keywords Gemini's schema dialect rejects, recursively. */
function toGeminiSchema(schema: unknown): unknown {
  if (Array.isArray(schema)) return schema.map(toGeminiSchema);
  if (!schema || typeof schema !== "object") return schema;
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(schema as Record<string, unknown>)) {
    if (key === "additionalProperties") continue;
    out[key] = toGeminiSchema(value);
  }
  return out;
}

async function completeGemini(apiKey: string, request: LlmRequest): Promise<LlmResult> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODELS.gemini)}:generateContent`;
  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: request.system }] },
        contents: request.messages.map((t) => ({
          // Gemini names the assistant "model"; the user role matches.
          role: t.role === "assistant" ? "model" : "user",
          parts: [{ text: t.content }],
        })),
        generationConfig: {
          maxOutputTokens: request.maxTokens ?? 1024,
          responseMimeType: "application/json",
          responseSchema: toGeminiSchema(request.schema),
        },
      }),
    });
  } catch {
    throw new LlmError(502, "upstream_error", "Gemini could not be reached.");
  }

  if (!response.ok) throwForStatus(response.status, "gemini");

  const body = (await response.json().catch(() => null)) as {
    candidates?: Array<{ finishReason?: string; content?: { parts?: Array<{ text?: string }> } }>;
  } | null;
  const candidate = body?.candidates?.[0];
  // Gemini reports a blocked generation as a finishReason, not an error status.
  if (candidate?.finishReason === "SAFETY" || candidate?.finishReason === "PROHIBITED_CONTENT") {
    return { kind: "refusal" };
  }
  const text = candidate?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
  if (!text) return { kind: "empty" };
  return parseJsonReply(text);
}
