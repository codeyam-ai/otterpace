import { describe, it, expect, vi, beforeEach } from "vitest";

const createMock = vi.fn();
vi.mock("@anthropic-ai/sdk", () => ({
  default: class {
    messages = { create: createMock };
    constructor(_opts: unknown) {}
  },
}));

import handler from "../../api/race-search.ts";

interface MockRes {
  statusCode: number;
  body: unknown;
  status: (c: number) => MockRes;
  json: (b: unknown) => MockRes;
}

function makeRes(): MockRes {
  return {
    statusCode: 0,
    body: undefined as unknown,
    status(c: number) { this.statusCode = c; return this; },
    json(b: unknown) { this.body = b; return this; },
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function call(req: any) {
  const res = makeRes();
  if (req.method === "POST") {
    req.headers = { "content-type": "application/json", ...(req.headers ?? {}) };
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return { res, done: handler(req as any, res as any) };
}

function textReply(json: string) {
  return { stop_reason: "end_turn", content: [{ type: "text", text: json }] };
}

beforeEach(() => {
  createMock.mockReset();
});

describe("race-search handler", () => {
  it("rejects non-POST with 405", async () => {
    const { res, done } = call({ method: "GET", headers: {}, body: {} });
    await done;
    expect(res.statusCode).toBe(405);
  });

  it("requires an api key", async () => {
    const { res, done } = call({ method: "POST", headers: {}, body: { query: "cascade" } });
    await done;
    expect(res.statusCode).toBe(400);
    expect((res.body as { error: string }).error).toBe("missing_key");
  });

  it("requires a query", async () => {
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { query: "  " } });
    await done;
    expect(res.statusCode).toBe(400);
    expect((res.body as { error: string }).error).toBe("missing_query");
    expect(createMock).not.toHaveBeenCalled();
  });

  it("returns candidate races on success", async () => {
    createMock.mockResolvedValue(textReply(JSON.stringify({
      results: [
        { name: "Cascade Marathon", date: "2026-09-06", distanceMiles: 26.2, unit: "miles", location: "Seattle, WA", sourceUrl: "https://x/cascade" },
        { name: "Cascade Half", date: "2026-09-06", distanceMiles: 13.1, unit: "miles", location: "Seattle, WA" },
      ],
    })));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { query: "cascade" } });
    await done;
    expect(res.statusCode).toBe(200);
    const body = res.body as { results: { name: string }[] };
    expect(body.results).toHaveLength(2);
    expect(body.results[0].name).toBe("Cascade Marathon");
  });

  it("caps the result list at 5", async () => {
    const many = Array.from({ length: 12 }, (_, i) => ({ name: `Race ${i}` }));
    createMock.mockResolvedValue(textReply(JSON.stringify({ results: many })));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { query: "race" } });
    await done;
    expect(res.statusCode).toBe(200);
    expect((res.body as { results: unknown[] }).results).toHaveLength(5);
  });

  it("degrades to an empty list on malformed model JSON", async () => {
    createMock.mockResolvedValue(textReply("not json"));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { query: "cascade" } });
    await done;
    expect(res.statusCode).toBe(200);
    expect((res.body as { results: unknown[] }).results).toEqual([]);
  });

  it("maps a 429 from Anthropic to rate_limited", async () => {
    createMock.mockRejectedValue(Object.assign(new Error("slow down"), { status: 429 }));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { query: "cascade" } });
    await done;
    expect(res.statusCode).toBe(429);
  });

  it("413s on an over-long query", async () => {
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { query: "x".repeat(300) } });
    await done;
    expect(res.statusCode).toBe(413);
    expect(createMock).not.toHaveBeenCalled();
  });
});
