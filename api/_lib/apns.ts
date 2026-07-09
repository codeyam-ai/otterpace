// Minimal APNs provider client for the movement nudge.
//
// Token-based auth (a .p8 signing key + key id + team id), so no cert rotation.
// The payload builder and the provider-JWT claims are pure and unit-tested; the
// actual HTTP/2 delivery is env-credentialed glue verified against Apple's
// sandbox, not in CI. Credentials come from env (set in Vercel):
//
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_AUTH_KEY (.p8 contents, PEM),
//   APNS_BUNDLE_ID (the apns-topic), APNS_HOST
//     (api.push.apple.com | api.sandbox.push.apple.com).

import { createSign } from "node:crypto";
import http2 from "node:http2";
import { env } from "./strava.js";

/** The `aps` alert payload — mirrors `ReminderCopy.inactivity*` on the client. */
export function buildAps(title: string, body: string): Record<string, unknown> {
  return {
    aps: {
      alert: { title, body },
      sound: "default",
    },
  };
}

/** base64url of a Buffer/string, no padding — the JWT segment encoding. */
function b64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

/**
 * Build + ES256-sign the APNs provider JWT. Apple accepts a token for up to an
 * hour; callers cache within that window. Pure given (keyId, teamId, key, now)
 * so the header/claims shape is testable; only the signature needs a real key.
 */
export function providerToken(keyId: string, teamId: string, authKey: string, now: Date): string {
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64url(JSON.stringify({ iss: teamId, iat: Math.floor(now.getTime() / 1000) }));
  const signingInput = `${header}.${claims}`;
  const signer = createSign("SHA256");
  signer.update(signingInput);
  const signature = signer.sign({ key: authKey, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${b64url(signature)}`;
}

export interface ApnsResult {
  token: string;
  ok: boolean;
  status?: number;
  /** APNs `reason` (e.g. "BadDeviceToken", "Unregistered") for pruning. */
  reason?: string;
}

/**
 * Deliver one alert to a device token over HTTP/2. Best-effort: resolves with a
 * result rather than throwing, so one bad token never sinks a batch. A 410 /
 * "Unregistered" tells the caller to prune the token.
 */
export function sendPush(deviceToken: string, payload: Record<string, unknown>, providerJwt: string): Promise<ApnsResult> {
  const host = env("APNS_HOST");
  const topic = env("APNS_BUNDLE_ID");
  return new Promise((resolve) => {
    const client = http2.connect(`https://${host}`);
    client.on("error", () => resolve({ token: deviceToken, ok: false }));
    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${providerJwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "content-type": "application/json",
    });
    let status = 0;
    let bodyText = "";
    req.on("response", (headers) => {
      status = Number(headers[":status"]) || 0;
    });
    req.setEncoding("utf8");
    req.on("data", (chunk) => (bodyText += chunk));
    req.on("end", () => {
      client.close();
      let reason: string | undefined;
      try {
        reason = bodyText ? (JSON.parse(bodyText).reason as string) : undefined;
      } catch {
        reason = undefined;
      }
      resolve({ token: deviceToken, ok: status >= 200 && status < 300, status, reason });
    });
    req.on("error", () => {
      client.close();
      resolve({ token: deviceToken, ok: false });
    });
    req.end(JSON.stringify(payload));
  });
}
