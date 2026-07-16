#!/usr/bin/env node
// Submit an Otterpace build for external TestFlight (Beta App) Review.
// Adds the build to the external beta group, then creates the review submission.
// Usage: ASC_KEY_ID=... ASC_ISSUER_ID=... node Scripts/asc-submit-external.mjs [bundleId] [buildNumber] [externalGroupName]
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER_ID = process.env.ASC_ISSUER_ID;
const BUNDLE_ID = process.argv[2] || "com.otterpace.app";
const VERSION = process.argv[3];
const GROUP_NAME = process.argv[4] || "Friends & Family";
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
async function api(path, method = "GET", body = null) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${jwt()}`, ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  return { ok: res.ok, status: res.status, body: text ? JSON.parse(text) : null };
}

const apps = await api(`/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&fields[apps]=name`);
const app = apps.body.data?.[0];
if (!app) { console.error(`no app for ${BUNDLE_ID}`); process.exit(1); }

const builds = await api(`/v1/builds?filter[app]=${app.id}&filter[version]=${encodeURIComponent(VERSION)}&fields[builds]=version,processingState&limit=1`);
const build = builds.body.data?.[0];
if (!build) { console.error(`build ${VERSION} not found`); process.exit(1); }
if (build.attributes.processingState !== "VALID") { console.error(`build ${VERSION} is ${build.attributes.processingState}, not VALID`); process.exit(1); }
console.log(`build ${VERSION}: ${build.id} (${build.attributes.processingState})`);

const groups = await api(`/v1/apps/${app.id}/betaGroups?fields[betaGroups]=name,isInternalGroup&limit=50`);
const group = groups.body.data?.find((g) => g.attributes.name === GROUP_NAME && g.attributes.isInternalGroup === false);
if (!group) { console.error(`external group "${GROUP_NAME}" not found`); process.exit(1); }
console.log(`external group: ${GROUP_NAME} (${group.id})`);

// 1) Add the build to the external group (idempotent — 409/422 if already linked).
const addRes = await api(`/v1/betaGroups/${group.id}/relationships/builds`, "POST", {
  data: [{ type: "builds", id: build.id }],
});
if (addRes.ok) console.log(`added build to "${GROUP_NAME}"`);
else if ([409, 422].includes(addRes.status)) console.log(`build already in "${GROUP_NAME}" (${addRes.status})`);
else { console.error(`add-to-group failed ${addRes.status}: ${JSON.stringify(addRes.body)}`); process.exit(1); }

// 2) Create the Beta App Review submission.
const subRes = await api(`/v1/betaAppReviewSubmissions`, "POST", {
  data: { type: "betaAppReviewSubmissions", relationships: { build: { data: { type: "builds", id: build.id } } } },
});
if (subRes.ok) {
  console.log(`SUBMITTED for external review — betaReviewState=${subRes.body.data?.attributes?.betaReviewState ?? "?"}`);
} else if (subRes.status === 409) {
  console.log(`already submitted for external review (409) — ${JSON.stringify(subRes.body?.errors?.[0]?.detail ?? "")}`);
} else {
  console.error(`submit failed ${subRes.status}: ${JSON.stringify(subRes.body)}`);
  process.exit(1);
}
