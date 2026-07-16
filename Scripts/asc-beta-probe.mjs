#!/usr/bin/env node
// Read-only probe of TestFlight external-review prerequisites for a build.
// Usage: ASC_KEY_ID=... ASC_ISSUER_ID=... node Scripts/asc-beta-probe.mjs [bundleId] [buildNumber]
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER_ID = process.env.ASC_ISSUER_ID;
const BUNDLE_ID = process.argv[2] || "com.otterpace.app";
const VERSION = process.argv[3] || null;
if (!KEY_ID || !ISSUER_ID) { console.error("set ASC_KEY_ID and ASC_ISSUER_ID"); process.exit(1); }

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
async function api(path) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, { headers: { Authorization: `Bearer ${jwt()}` } });
  if (!res.ok) throw new Error(`ASC ${res.status} on ${path}: ${(await res.text()).slice(0, 400)}`);
  return res.json();
}

const apps = await api(`/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&fields[apps]=name`);
const app = apps.data?.[0];
if (!app) { console.error(`no app for ${BUNDLE_ID}`); process.exit(1); }
console.log(`app: ${app.attributes.name} (${app.id})`);

// Beta App Review contact detail (must exist to submit)
try {
  const detail = await api(`/v1/apps/${app.id}/betaAppReviewDetail`);
  const d = detail.data?.attributes ?? {};
  console.log(`betaAppReviewDetail: contactEmail=${d.contactEmail ?? "—"} contactFirst=${d.contactFirstName ?? "—"} demoRequired=${d.demoAccountRequired}`);
} catch (e) { console.log(`betaAppReviewDetail: MISSING (${e.message})`); }

// External beta groups
const groups = await api(`/v1/apps/${app.id}/betaGroups?fields[betaGroups]=name,isInternalGroup,hasAccessToAllBuilds&limit=50`);
const external = (groups.data ?? []).filter((g) => g.attributes.isInternalGroup === false);
console.log(`external groups: ${external.map((g) => `${g.attributes.name}(${g.id})`).join(", ") || "NONE"}`);

// The build + its current review submission + export compliance
let path = `/v1/builds?filter[app]=${app.id}&fields[builds]=version,processingState,usesNonExemptEncryption,betaAppReviewSubmission&include=betaGroups,betaAppReviewSubmission&fields[betaGroups]=name&fields[betaAppReviewSubmissions]=betaReviewState&limit=5&sort=-uploadedDate`;
if (VERSION) path += `&filter[version]=${encodeURIComponent(VERSION)}`;
const builds = await api(path);
for (const b of builds.data ?? []) {
  const a = b.attributes;
  const subId = b.relationships?.betaAppReviewSubmission?.data?.id;
  const grpIds = (b.relationships?.betaGroups?.data ?? []).map((g) => g.id);
  console.log(`build ${a.version}: id=${b.id} state=${a.processingState} nonExemptEncryption=${a.usesNonExemptEncryption} groups=[${grpIds.join(",") || "—"}] reviewSub=${subId ?? "none"}`);
}
