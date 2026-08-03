import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// The router calls Anthropic through the SDK and OpenAI/Gemini over fetch.
// Mock the SDK here; each fetch-based test stubs global fetch itself.
const createMock = vi.fn();
vi.mock("@anthropic-ai/sdk", () => ({
  default: class {
    messages = { create: createMock };
    constructor(_opts: unknown) {}
  },
}));

import {
  complete,
  credentialsFromHeaders,
  isLlmProvider,
  LlmError,
  modelFor,
  type LlmProvider,
} from "../../api/_lib/llm.ts";

const SCHEMA = {
  type: "object",
  properties: { text: { type: "string" } },
  required: ["text"],
  additionalProperties: false,
};

function request(overrides: Record<string, unknown> = {}) {
  return {
    system: "You are Buddy.",
    messages: [{ role: "user" as const, content: "What should I do today?" }],
    schema: SCHEMA,
    schemaName: "coach_reply",
    ...overrides,
  };
}

/** A fetch stub returning one canned response. */
function stubFetch(body: unknown, init: { ok?: boolean; status?: number } = {}) {
  const fn = vi.fn().mockResolvedValue({
    ok: init.ok ?? true,
    status: init.status ?? 200,
    json: async () => body,
  });
  vi.stubGlobal("fetch", fn);
  return fn;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("credentialsFromHeaders", () => {
  it("reads the provider and key from the current headers", () => {
    expect(
      credentialsFromHeaders({ "x-ai-provider": "openai", "x-ai-key": "sk-openai-123" }),
    ).toEqual({ provider: "openai", apiKey: "sk-openai-123" });
  });

  // An already-installed app sends only the old header and no provider. It must
  // keep working, since app and backend can't deploy atomically.
  it("treats the legacy Anthropic header as an Anthropic request", () => {
    expect(credentialsFromHeaders({ "x-anthropic-key": "sk-ant-legacy" })).toEqual({
      provider: "anthropic",
      apiKey: "sk-ant-legacy",
    });
  });

  // The new app sends both headers for an Anthropic key; the explicit one wins
  // and the two agree, so this is just belt-and-braces.
  it("prefers the explicit provider when both headers are present", () => {
    expect(
      credentialsFromHeaders({
        "x-ai-provider": "anthropic",
        "x-ai-key": "sk-ant-new",
        "x-anthropic-key": "sk-ant-new",
      }),
    ).toEqual({ provider: "anthropic", apiKey: "sk-ant-new" });
  });

  it("rejects a missing, short, or non-string key", () => {
    expect(credentialsFromHeaders({})).toBeNull();
    expect(credentialsFromHeaders({ "x-ai-key": "short" })).toBeNull();
    expect(credentialsFromHeaders({ "x-ai-key": ["sk-array-key"] })).toBeNull();
  });

  // An unknown provider is rejected rather than silently falling back to
  // Anthropic, which would spend the user's key on the wrong service.
  it("rejects an unrecognized provider instead of defaulting", () => {
    expect(credentialsFromHeaders({ "x-ai-provider": "llama", "x-ai-key": "sk-whatever" })).toBeNull();
  });

  it("trims whitespace around the key", () => {
    expect(credentialsFromHeaders({ "x-ai-key": "  sk-padded-key  " })?.apiKey).toBe("sk-padded-key");
  });
});

describe("isLlmProvider / modelFor", () => {
  it("recognizes exactly the three supported providers", () => {
    expect(["anthropic", "openai", "gemini"].every(isLlmProvider)).toBe(true);
    expect(isLlmProvider("llama")).toBe(false);
    expect(isLlmProvider(undefined)).toBe(false);
  });

  it("has a non-empty model for every provider", () => {
    for (const p of ["anthropic", "openai", "gemini"] as LlmProvider[]) {
      expect(modelFor(p).length).toBeGreaterThan(0);
    }
  });
});

describe("complete — Anthropic", () => {
  beforeEach(() => createMock.mockReset());

  it("returns parsed JSON from the text block", async () => {
    createMock.mockResolvedValue({
      stop_reason: "end_turn",
      content: [{ type: "text", text: '{"text":"Easy walk today."}' }],
    });
    const result = await complete({ provider: "anthropic", apiKey: "sk-ant-x" }, request());
    expect(result).toEqual({ kind: "json", value: { text: "Easy walk today." } });
  });

  it("reports a refusal", async () => {
    createMock.mockResolvedValue({ stop_reason: "refusal", content: [] });
    expect(await complete({ provider: "anthropic", apiKey: "sk-ant-x" }, request())).toEqual({
      kind: "refusal",
    });
  });

  // No text at all and unparseable text are different failures: one is an
  // upstream fault, the other is content the user can retry past.
  it("distinguishes an empty reply from an unparseable one", async () => {
    createMock.mockResolvedValue({ stop_reason: "end_turn", content: [] });
    expect(await complete({ provider: "anthropic", apiKey: "sk-ant-x" }, request())).toEqual({
      kind: "empty",
    });

    createMock.mockResolvedValue({
      stop_reason: "end_turn",
      content: [{ type: "text", text: "not json at all" }],
    });
    expect(await complete({ provider: "anthropic", apiKey: "sk-ant-x" }, request())).toEqual({
      kind: "unusable",
    });
  });

  // Anthropic's error-status mapping is covered end-to-end through the handler
  // in coach.test.ts ("maps a 401 to invalid_key" / "maps a 429 to
  // rate_limited"), which exercises this same `throwForStatus` path. Asserting it
  // again by calling `complete` directly added no coverage.
});

describe("complete — OpenAI", () => {
  it("sends the key as a bearer token and a strict json_schema format", async () => {
    const fetchMock = stubFetch({ choices: [{ message: { content: '{"text":"Rest day."}' } }] });
    const result = await complete({ provider: "openai", apiKey: "sk-openai-1" }, request());

    expect(result).toEqual({ kind: "json", value: { text: "Rest day." } });
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.openai.com/v1/chat/completions");
    expect((init.headers as Record<string, string>).authorization).toBe("Bearer sk-openai-1");
    const sent = JSON.parse(init.body as string);
    expect(sent.response_format.json_schema.strict).toBe(true);
    expect(sent.response_format.json_schema.schema).toEqual(SCHEMA);
    // The system prompt must ride as a system message, not be folded into the
    // user turn — coaching quality depends on it staying a system instruction.
    expect(sent.messages[0]).toEqual({ role: "system", content: "You are Buddy." });
  });

  it("reports a strict-schema refusal", async () => {
    stubFetch({ choices: [{ message: { content: null, refusal: "I can't help with that." } }] });
    expect(await complete({ provider: "openai", apiKey: "sk-openai-1" }, request())).toEqual({
      kind: "refusal",
    });
  });

  it("maps 401 and 429 to the statuses the app already handles", async () => {
    stubFetch({}, { ok: false, status: 401 });
    await expect(complete({ provider: "openai", apiKey: "sk-x" }, request())).rejects.toMatchObject({
      status: 401,
      code: "invalid_key",
    });

    stubFetch({}, { ok: false, status: 429 });
    await expect(complete({ provider: "openai", apiKey: "sk-x" }, request())).rejects.toMatchObject({
      status: 429,
      code: "rate_limited",
    });
  });

  it("names OpenAI, not Anthropic, in a rejected-key message", async () => {
    stubFetch({}, { ok: false, status: 401 });
    await expect(complete({ provider: "openai", apiKey: "sk-x" }, request())).rejects.toThrow(/OpenAI/);
  });

  it("turns a network failure into a 502", async () => {
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => {
      throw new Error("ECONNRESET");
    }));
    await expect(complete({ provider: "openai", apiKey: "sk-x" }, request())).rejects.toBeInstanceOf(LlmError);
  });

  // Regression: a connected OpenAI key produced "I couldn't reach Buddy just
  // now. Check your connection and try again." The key was fine and the network
  // was fine — the reply budget was being consumed by reasoning tokens, and the
  // resulting empty completion was indistinguishable from an outage.

  it("gives the reply real headroom beyond the reasoning budget", async () => {
    const fetchMock = stubFetch({ choices: [{ message: { content: '{"text":"Rest day."}' } }] });
    await complete({ provider: "openai", apiKey: "sk-openai-1" }, request());
    const sent = JSON.parse(fetchMock.mock.calls[0][1].body as string);
    // `max_completion_tokens` covers reasoning AND visible output, so a budget
    // sized for a 2-4 sentence answer can be spent before any text is emitted.
    expect(sent.max_completion_tokens).toBeGreaterThanOrEqual(16000);
    expect(sent.max_tokens).toBeUndefined();
  });

  it("reports an exhausted token budget as its own fault, not an outage", async () => {
    stubFetch({ choices: [{ finish_reason: "length", message: { content: "" } }] });
    await expect(
      complete({ provider: "openai", apiKey: "sk-x" }, request()),
    ).rejects.toMatchObject({ status: 502, code: "token_budget_exhausted" });
  });

  it("still reports a plain empty completion as empty", async () => {
    stubFetch({ choices: [{ finish_reason: "stop", message: { content: "" } }] });
    expect(await complete({ provider: "openai", apiKey: "sk-x" }, request())).toEqual({
      kind: "empty",
    });
  });

  it("names an unavailable model instead of claiming the provider is unreachable", async () => {
    stubFetch(
      { error: { message: "The model `gpt-5` does not exist or you do not have access to it." } },
      { ok: false, status: 404 },
    );
    const err = await complete({ provider: "openai", apiKey: "sk-x" }, request()).catch((e) => e);
    expect(err).toMatchObject({ status: 502, code: "model_unavailable" });
    // The provider's own reason must survive, or this is undiagnosable from the app.
    expect(err.message).toMatch(/does not exist or you do not have access/);
    expect(err.message).not.toMatch(/could not be reached/);
  });

  it("passes the provider's reason through on a 400", async () => {
    stubFetch(
      { error: { message: "Unsupported parameter: 'max_tokens'." } },
      { ok: false, status: 400 },
    );
    await expect(
      complete({ provider: "openai", apiKey: "sk-x" }, request()),
    ).rejects.toThrow(/Unsupported parameter/);
  });

  // A genuine outage must still read as one, so the new codes stay meaningful.
  it("still reports a 500 as an unreachable provider", async () => {
    stubFetch({}, { ok: false, status: 500 });
    await expect(
      complete({ provider: "openai", apiKey: "sk-x" }, request()),
    ).rejects.toMatchObject({ code: "upstream_error" });
  });

  // Regression: the actual cause of the reported outage. An account with no
  // credits returns 429 — the same status as a burst limit — and was reported as
  // "rate limited, try again shortly". That advice can never succeed: the balance
  // does not refill on its own. The app then degraded it further into "check your
  // connection", so three layers each pointed further from the real problem.
  //
  // This payload is verbatim what OpenAI returned for the reported failure.
  const NO_CREDITS = {
    error: {
      message:
        "You have no credits remaining. Add credits to continue using the API at https://platform.openai.com/settings/organization/billing/.",
      type: "insufficient_quota",
      param: null,
      code: "credit_balance_exhausted",
    },
  };

  it("tells an exhausted balance apart from a burst rate limit", async () => {
    stubFetch(NO_CREDITS, { ok: false, status: 429 });
    const err = await complete({ provider: "openai", apiKey: "sk-x" }, request()).catch((e) => e);

    expect(err).toMatchObject({ status: 402, code: "insufficient_quota" });
    // 402, not 429: the app routes 429 to a retry path, and retrying is exactly
    // what cannot help here.
    expect(err.status).not.toBe(429);
    expect(err.message).toMatch(/out of credits/i);
    expect(err.message).not.toMatch(/try again shortly/i);
  });

  it("still reports a genuine burst limit as retryable", async () => {
    stubFetch(
      { error: { message: "Rate limit reached for requests", type: "requests", code: "rate_limit_exceeded" } },
      { ok: false, status: 429 },
    );
    await expect(
      complete({ provider: "openai", apiKey: "sk-x" }, request()),
    ).rejects.toMatchObject({ status: 429, code: "rate_limited" });
  });

  it("recognizes an exhausted balance from prose when there is no type or code", async () => {
    stubFetch(
      { error: { message: "You exceeded your current quota, please check your plan and billing details." } },
      { ok: false, status: 429 },
    );
    await expect(
      complete({ provider: "openai", apiKey: "sk-x" }, request()),
    ).rejects.toMatchObject({ status: 402, code: "insufficient_quota" });
  });
});

describe("complete — Gemini", () => {
  it("sends the system prompt as systemInstruction and maps assistant to model", async () => {
    const fetchMock = stubFetch({
      candidates: [{ content: { parts: [{ text: '{"text":"Nice easy miles."}' }] } }],
    });
    const result = await complete(
      { provider: "gemini", apiKey: "AIza-1" },
      request({
        messages: [
          { role: "user", content: "Can I run?" },
          { role: "assistant", content: "How do the legs feel?" },
          { role: "user", content: "Good." },
        ],
      }),
    );

    expect(result).toEqual({ kind: "json", value: { text: "Nice easy miles." } });
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toContain("generativelanguage.googleapis.com");
    expect((init.headers as Record<string, string>)["x-goog-api-key"]).toBe("AIza-1");
    const sent = JSON.parse(init.body as string);
    expect(sent.systemInstruction.parts[0].text).toBe("You are Buddy.");
    expect(sent.contents.map((c: { role: string }) => c.role)).toEqual(["user", "model", "user"]);
  });

  // Gemini's schema dialect rejects additionalProperties, so it has to be
  // stripped recursively or every structured call 400s.
  it("strips additionalProperties from the response schema, at every depth", async () => {
    const fetchMock = stubFetch({ candidates: [{ content: { parts: [{ text: "{}" }] } }] });
    await complete(
      { provider: "gemini", apiKey: "AIza-1" },
      request({
        schema: {
          type: "object",
          additionalProperties: false,
          properties: {
            race: { type: "object", additionalProperties: false, properties: { name: { type: "string" } } },
          },
        },
      }),
    );
    const sent = JSON.parse(fetchMock.mock.calls[0][1].body as string);
    expect(JSON.stringify(sent.generationConfig.responseSchema)).not.toContain("additionalProperties");
    // Stripping must not damage the rest of the schema.
    expect(sent.generationConfig.responseSchema.properties.race.properties.name).toEqual({ type: "string" });
  });

  // A blocked generation arrives as a finishReason on a 200, not an error status.
  it("treats a safety-blocked candidate as a refusal", async () => {
    stubFetch({ candidates: [{ finishReason: "SAFETY", content: { parts: [] } }] });
    expect(await complete({ provider: "gemini", apiKey: "AIza-1" }, request())).toEqual({
      kind: "refusal",
    });
  });

  it("reports an empty candidate as empty", async () => {
    stubFetch({ candidates: [{ content: { parts: [] } }] });
    expect(await complete({ provider: "gemini", apiKey: "AIza-1" }, request())).toEqual({ kind: "empty" });
  });

  it("names Gemini in a rejected-key message", async () => {
    stubFetch({}, { ok: false, status: 403 });
    await expect(complete({ provider: "gemini", apiKey: "AIza-1" }, request())).rejects.toThrow(/Gemini/);
  });
});
