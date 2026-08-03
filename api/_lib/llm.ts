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

/**
 * Map any provider's HTTP status onto the status the app already handles.
 *
 * `detail` carries the provider's own error text when we have it. Without it a
 * misconfigured model id and a genuine outage both surfaced as "could not be
 * reached", which is what made a broken OpenAI key impossible to diagnose from
 * the app: the user saw a network-sounding message for a config bug.
 */
function throwForStatus(
  status: number | undefined,
  provider: LlmProvider,
  detail?: ProviderError,
): never {
  const name = provider === "anthropic" ? "Anthropic" : provider === "openai" ? "OpenAI" : "Gemini";
  const suffix = detail?.message ? ` ${detail.message}` : "";
  if (status === 401 || status === 403) {
    throw new LlmError(401, "invalid_key", `That API key was rejected by ${name}.`);
  }

  // Checked BEFORE any status branch, because providers disagree on which status
  // an empty balance deserves: OpenAI says 429, Anthropic says 400. Gating this
  // on 429 alone sent an out-of-credits Anthropic user to the "unknown model"
  // message, which is both wrong and unactionable.
  //
  // 402 (not 429) so the app parses the body instead of routing it to the retry
  // path: "try again shortly" cannot work when the account is dry.
  if (isQuotaExhausted(detail)) {
    throw new LlmError(
      402,
      "insufficient_quota",
      `Your ${name} account is out of credits, so it turned down my request. Add credits at ${billingURL(provider)} and ask me again.`,
    );
  }

  if (status === 429) {
    throw new LlmError(429, "rate_limited", `Your ${name} account is rate limited. Try again shortly.`);
  }
  // 400/404 are OUR bug (unknown model, malformed request), not an outage, and
  // not something the user can retry past. Say so, and pass the provider's
  // reason through so the cause is visible without reproducing locally.
  if (status === 400 || status === 404) {
    throw new LlmError(
      502,
      "model_unavailable",
      `${name} rejected the request: model "${modelFor(provider)}" may be unavailable to this key.${suffix}`,
    );
  }
  throw new LlmError(502, "upstream_error", `${name} could not be reached.${suffix}`);
}

/** A provider's error body, normalized to the bits we route on. */
interface ProviderError {
  message?: string;
  /** Provider's own classifier, e.g. "insufficient_quota". */
  type?: string;
  /** Provider's own code, e.g. "credit_balance_exhausted". */
  code?: string;
}

/** Best-effort extraction of a provider's error from its response body. */
async function errorDetail(response: Response): Promise<ProviderError | undefined> {
  const body = (await response.json().catch(() => null)) as
    | { error?: { message?: string; type?: string; code?: string } | string }
    | null;
  if (!body) return undefined;
  const err = body.error;
  if (typeof err === "string") return { message: err.slice(0, 300) };
  if (!err) return undefined;
  return {
    message: typeof err.message === "string" ? err.message.slice(0, 300) : undefined,
    type: typeof err.type === "string" ? err.type : undefined,
    code: typeof err.code === "string" ? err.code : undefined,
  };
}

/**
 * Whether a 429 is an exhausted balance rather than a burst limit.
 *
 * These are opposite problems wearing the same status code: a burst limit clears
 * on its own in seconds, an empty balance never does. Telling someone with no
 * credits to "try again shortly" is advice that cannot work, so they get routed
 * apart here.
 */
function isQuotaExhausted(detail?: ProviderError): boolean {
  const needles = ["insufficient_quota", "credit_balance_exhausted", "billing_hard_limit_reached"];
  const haystack = `${detail?.type ?? ""} ${detail?.code ?? ""}`.toLowerCase();
  if (needles.some((n) => haystack.includes(n))) return true;
  // Only OpenAI puts this in `type`/`code`. Anthropic reports it as a plain
  // invalid_request_error and Gemini as a quota message, so the prose is the
  // only signal for them.
  const message = (detail?.message ?? "").toLowerCase();
  return [
    "no credits remaining",
    "exceeded your current quota",
    "credit balance is too low",   // Anthropic
    "purchase credits",            // Anthropic's remedy sentence
    "quota exceeded",              // Gemini
  ].some((n) => message.includes(n));
}

/** Where the user actually adds credits, per provider. */
function billingURL(provider: LlmProvider): string {
  switch (provider) {
    case "anthropic": return "console.anthropic.com/settings/billing";
    case "openai":    return "platform.openai.com/settings/organization/billing";
    case "gemini":    return "aistudio.google.com/app/plan_information";
  }
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
    // The SDK surfaces the provider's error body on `.error`; pass it through so
    // an exhausted balance is told apart from a burst limit here too.
    const e = err as { status?: number; error?: { error?: ProviderError } };
    throwForStatus(e.status, "anthropic", e.error?.error);
  }
}

// MARK: - OpenAI
//
// Chat Completions with a strict json_schema response format. Reached over plain
// fetch rather than the SDK: it is one request shape, and every extra dependency
// is weight in a serverless bundle that cold-starts on each user's key.

/**
 * Headroom for the reply itself, on top of whatever the model spends thinking.
 *
 * `max_completion_tokens` is a budget for reasoning tokens AND visible output.
 * On a reasoning model the thinking is invoiced against the same allowance, so a
 * budget sized for a 2-4 sentence answer (1024) can be consumed entirely before
 * a single visible character is emitted — the call then returns `content: ""`
 * with `finish_reason: "length"`, which read as "no text" and surfaced to the
 * user as a connection failure. The reply is small; the thinking is not, so this
 * is sized for the thinking.
 */
const OPENAI_MIN_COMPLETION_TOKENS = 16000;

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
        max_completion_tokens: Math.max(request.maxTokens ?? 1024, OPENAI_MIN_COMPLETION_TOKENS),
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

  if (!response.ok) throwForStatus(response.status, "openai", await errorDetail(response));

  const body = (await response.json().catch(() => null)) as {
    choices?: Array<{
      finish_reason?: string;
      message?: { content?: string | null; refusal?: string | null };
    }>;
  } | null;
  const first = body?.choices?.[0];
  const choice = first?.message;
  // A strict-schema refusal comes back in its own field, with content null.
  if (choice?.refusal) return { kind: "refusal" };
  if (typeof choice?.content !== "string" || !choice.content) {
    // Empty output because the budget ran out is a fixable configuration fault,
    // not an upstream outage — name it so it can't hide behind "no text" again.
    if (first?.finish_reason === "length") {
      throw new LlmError(
        502,
        "token_budget_exhausted",
        `OpenAI used its entire token budget before answering (model "${MODELS.openai}"). Raise max_completion_tokens.`,
      );
    }
    return { kind: "empty" };
  }
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

  if (!response.ok) throwForStatus(response.status, "gemini", await errorDetail(response));

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
