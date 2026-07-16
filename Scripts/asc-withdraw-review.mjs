#!/usr/bin/env node
// Withdraw a build's pending Beta App Review submission (only valid while it is
// still Waiting for Review). Usage: ... node Scripts/asc-withdraw-review.mjs [bundleId] [buildNumber]
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER_ID = process.env.ASC_ISSUER_ID;
const BUNDLE_ID = process.argv[2] || "com.otterpace.app";
const VERSION = process.argv[3];
if (!KEY_ID || !ISSUER_ID) { console.error("set ASC_KEY_ID and ASC_ISSUER_ID"); process.exit(1); }
if (!VERSION) { console.error("pass the build number"); process.exit(1); }

const privateKey = crypto.createPrivateKey(fs.readFileSync(`${os.homedir()}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`));
const b64url = (b) => Buffer.from(b).toString("base64url");
function jwt() {
  const header = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID, typ: "JWT" }));
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }));
  const signer = crypto.createSign("SHA256");
  signer.update(`${header}.${payload}`);
  return `${header}.${payload}.${b64url(signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }))}`;
}
async function api(path, method = "GET") {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, { method, headers: { Authorization: `Bearer ${jwt()}` } });
  const text = await res.text();
  return { ok: res.ok, status: res.status, body: text ? JSON.parse(text) : null };
}

const apps = await api(`/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&fields[apps]=name`);
const app = apps.body.data?.[0];
if (!app) { console.error(`no app for ${BUNDLE_ID}`); process.exit(1); }

const builds = await api(`/v1/builds?filter[app]=${app.id}&filter[version]=${encodeURIComponent(VERSION)}&include=betaAppReviewSubmission&fields[betaAppReviewSubmissions]=betaReviewState&limit=1`);
const build = builds.body.data?.[0];
if (!build) { console.error(`build ${VERSION} not found`); process.exit(1); }
const subId = build.relationships?.betaAppReviewSubmission?.data?.id;
if (!subId) { console.log(`build ${VERSION} has no review submission — nothing to withdraw`); process.exit(0); }
const state = builds.body.included?.find((i) => i.id === subId)?.attributes?.betaReviewState;
console.log(`build ${VERSION} review submission ${subId} state=${state}`);

const del = await api(`/v1/betaAppReviewSubmissions/${subId}`, "DELETE");
if (del.ok) console.log(`WITHDRAWN build ${VERSION} from beta review`);
else { console.error(`withdraw failed ${del.status}: ${JSON.stringify(del.body)}`); process.exit(1); }
