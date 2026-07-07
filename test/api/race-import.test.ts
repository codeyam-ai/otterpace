import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// The handler constructs `new Anthropic({apiKey}).messages.create(...)` and does a
// server-side `fetch` of the race URL. Mock both so no real network/model call runs.
const createMock = vi.fn();
vi.mock("@anthropic-ai/sdk", () => ({
  default: class {
    messages = { create: createMock };
    constructor(_opts: unknown) {}
  },
}));

import handler from "../../api/race-import.ts";

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

function mockPage(html: string, ok = true) {
  vi.stubGlobal("fetch", vi.fn(async () => ({
    ok,
    arrayBuffer: async () => new TextEncoder().encode(html).buffer,
  })));
}

beforeEach(() => {
  createMock.mockReset();
});
afterEach(() => {
  vi.unstubAllGlobals();
});

describe("race-import handler", () => {
  it("rejects non-POST with 405", async () => {
    const { res, done } = call({ method: "GET", headers: {}, body: {} });
    await done;
    expect(res.statusCode).toBe(405);
  });

  it("requires an api key", async () => {
    const { res, done } = call({ method: "POST", headers: {}, body: { url: "https://x.com" } });
    await done;
    expect(res.statusCode).toBe(400);
    expect((res.body as { error: string }).error).toBe("missing_key");
  });

  it("requires a url", async () => {
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { url: "  " } });
    await done;
    expect(res.statusCode).toBe(400);
    expect((res.body as { error: string }).error).toBe("missing_url");
    expect(createMock).not.toHaveBeenCalled();
  });

  it("rejects a non-http(s) scheme", async () => {
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { url: "ftp://x.com/r" } });
    await done;
    expect(res.statusCode).toBe(400);
    expect((res.body as { error: string }).error).toBe("invalid_url");
    expect(createMock).not.toHaveBeenCalled();
  });

  // SSRF guard: a private / loopback / metadata host is refused before any fetch.
  it.each([
    "http://localhost/race",
    "http://127.0.0.1/race",
    "http://10.0.0.5/race",
    "http://192.168.1.1/race",
    "http://169.254.169.254/latest/meta-data",
    "http://172.16.0.1/race",
  ])("blocks the internal host %s", async (url) => {
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { url } });
    await done;
    expect(res.statusCode).toBe(400);
    expect((res.body as { error: string }).error).toBe("invalid_url");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("extracts a structured race from a public page", async () => {
    mockPage("<html><title>Cascade Marathon</title><body>Sept 6, 2026 in Seattle, WA. 26.2 miles.</body></html>");
    createMock.mockResolvedValue(textReply(JSON.stringify({
      race: { name: "Cascade Marathon", date: "2026-09-06", distanceMiles: 26.2, unit: "miles", location: "Seattle, WA" },
      confidence: 0.9,
      missingFields: [],
    })));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { url: "https://races.example.com/cascade" } });
    await done;
    expect(res.statusCode).toBe(200);
    const body = res.body as { race: { name: string }; confidence: number; missingFields: string[] };
    expect(body.race.name).toBe("Cascade Marathon");
    expect(body.confidence).toBe(0.9);
    expect(body.missingFields).toEqual([]);
  });

  it("422s when the page can't be fetched", async () => {
    mockPage("", false);
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { url: "https://races.example.com/missing" } });
    await done;
    expect(res.statusCode).toBe(422);
    expect((res.body as { error: string }).error).toBe("fetch_failed");
    expect(createMock).not.toHaveBeenCalled();
  });

  it("maps a 401 from Anthropic to invalid_key", async () => {
    mockPage("<html><body>Some race page with enough text.</body></html>");
    createMock.mockRejectedValue(Object.assign(new Error("unauthorized"), { status: 401 }));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { url: "https://races.example.com/r" } });
    await done;
    expect(res.statusCode).toBe(401);
    expect((res.body as { error: string }).error).toBe("invalid_key");
  });

  it("degrades to an empty race on malformed model JSON", async () => {
    mockPage("<html><body>Race details here, plenty of text.</body></html>");
    createMock.mockResolvedValue(textReply("not json"));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { url: "https://races.example.com/r" } });
    await done;
    expect(res.statusCode).toBe(200);
    expect((res.body as { missingFields: string[] }).missingFields.length).toBeGreaterThan(0);
  });

  it("never logs the Anthropic API key", async () => {
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const SECRET = "sk-ant-super-secret-key";
    mockPage("<html><body>Race page text.</body></html>");
    createMock.mockRejectedValue(Object.assign(new Error("boom"), { status: 500 }));
    const { done } = call({ method: "POST", headers: { "x-anthropic-key": SECRET }, body: { url: "https://races.example.com/r" } });
    await done;
    const logged = [...errSpy.mock.calls, ...logSpy.mock.calls].flat().join(" ");
    expect(logged).not.toContain(SECRET);
    errSpy.mockRestore();
    logSpy.mockRestore();
  });
});
