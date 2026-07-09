import { describe, it, expect } from "vitest";
import { generateKeyPairSync } from "node:crypto";
import { buildAps, providerToken } from "../../api/_lib/apns.ts";

// Unit tests for the pure parts of the APNs client: the alert payload shape and
// the ES256 provider-JWT structure. The HTTP/2 delivery (`sendPush`) is device
// glue verified against Apple's sandbox, not here.

describe("buildAps", () => {
  // The payload nests the alert + sound under `aps`, as APNs requires.
  it("builds a title/body alert payload", () => {
    const p = buildAps("Stretch your legs?", "Time to move.") as { aps: { alert: { title: string; body: string }; sound: string } };
    expect(p.aps.alert).toEqual({ title: "Stretch your legs?", body: "Time to move." });
    expect(p.aps.sound).toBe("default");
  });
});

describe("providerToken", () => {
  // The provider token is a three-segment JWT whose header names ES256 + the key id.
  it("produces a signed ES256 JWT with the key id in the header", () => {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const pem = privateKey.export({ type: "pkcs8", format: "pem" }) as string;
    const jwt = providerToken("KEY123", "TEAM456", pem, new Date("2026-07-08T00:00:00Z"));
    const segments = jwt.split(".");
    expect(segments).toHaveLength(3);
    const header = JSON.parse(Buffer.from(segments[0], "base64url").toString());
    expect(header).toEqual({ alg: "ES256", kid: "KEY123" });
    const claims = JSON.parse(Buffer.from(segments[1], "base64url").toString());
    expect(claims.iss).toBe("TEAM456");
    expect(typeof claims.iat).toBe("number");
  });
});
