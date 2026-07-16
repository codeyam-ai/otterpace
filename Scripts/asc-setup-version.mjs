#!/usr/bin/env node
// Set up (NOT submit) a new App Store version: create the version record, carry
// forward metadata from the prior version, set What's New, fill the subtitle, and
// attach a build. Stops short of creating the review submission.
//   Usage: ... node Scripts/asc-setup-version.mjs <newVersion> <buildNumber>
import crypto from "node:crypto"; import fs from "node:fs"; import os from "node:os";
const KEY_ID=process.env.ASC_KEY_ID, ISSUER_ID=process.env.ASC_ISSUER_ID;
const NEW_VERSION=process.argv[2], BUILD_NUMBER=process.argv[3];
const BUNDLE_ID="com.otterpace.app";
if(!KEY_ID||!ISSUER_ID){console.error("set ASC_KEY_ID and ASC_ISSUER_ID");process.exit(1);}
if(!NEW_VERSION){console.error("pass the new version string, e.g. 1.0.1");process.exit(1);}

const SUBTITLE="Your friendly running coach";
const WHATS_NEW="Buddy holds a real conversation now: Ask Buddy remembers what you already said and builds on it, gives calmer, more trusting guidance, and no longer over-flags rest. New: choose from five app themes — from warm and friendly to dark and focused — in onboarding or Settings. Plus fixes and polish.";

const pk=crypto.createPrivateKey(fs.readFileSync(`${os.homedir()}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`));
const b=x=>Buffer.from(x).toString("base64url");
function jwt(){const h=b(JSON.stringify({alg:"ES256",kid:KEY_ID,typ:"JWT"}));const n=Math.floor(Date.now()/1000);const p=b(JSON.stringify({iss:ISSUER_ID,iat:n,exp:n+600,aud:"appstoreconnect-v1"}));const s=crypto.createSign("SHA256");s.update(`${h}.${p}`);return `${h}.${p}.${b(s.sign({key:pk,dsaEncoding:"ieee-p1363"}))}`;}
async function api(path,method="GET",body=null){
  const r=await fetch(`https://api.appstoreconnect.apple.com${path}`,{method,headers:{Authorization:`Bearer ${jwt()}`,...(body?{"Content-Type":"application/json"}:{})},body:body?JSON.stringify(body):undefined});
  const t=await r.text();return {ok:r.ok,status:r.status,j:t?JSON.parse(t):null};
}

// App
const apps=await api(`/v1/apps?filter[bundleId]=${BUNDLE_ID}&fields[apps]=name`);
const app=apps.j.data?.[0]; if(!app){console.error("no app");process.exit(1);}
console.log(`app: ${app.attributes.name} (${app.id})`);

// Prior version's en-US localization (to carry metadata forward)
const priorVers=await api(`/v1/apps/${app.id}/appStoreVersions?include=appStoreVersionLocalizations&fields[appStoreVersions]=versionString,copyright&fields[appStoreVersionLocalizations]=locale,description,keywords,promotionalText,marketingUrl,supportUrl&limit=5`);
let existing=priorVers.j.data?.find(v=>v.attributes.versionString===NEW_VERSION);
const prior=priorVers.j.data?.find(v=>v.attributes.versionString!==NEW_VERSION);
const priorLoc=(priorVers.j.included||[]).find(i=>i.type==="appStoreVersionLocalizations" && i.attributes.locale==="en-US");
const carry=priorLoc?.attributes||{};
const copyright=prior?.attributes?.copyright||"2026 Nadia Eldeib";

// 1) Create the version (or reuse if it already exists)
let versionId;
if(existing){versionId=existing.id;console.log(`version ${NEW_VERSION} already exists (${versionId})`);}
else{
  const create=await api(`/v1/appStoreVersions`,"POST",{data:{type:"appStoreVersions",attributes:{platform:"IOS",versionString:NEW_VERSION,copyright,releaseType:"MANUAL"},relationships:{app:{data:{type:"apps",id:app.id}}}}});
  if(!create.ok){console.error(`create version failed ${create.status}: ${JSON.stringify(create.j)}`);process.exit(1);}
  versionId=create.j.data.id;console.log(`CREATED version ${NEW_VERSION} (${versionId}), releaseType=MANUAL, copyright="${copyright}"`);
}

// 2) Ensure the en-US version localization has metadata + What's New
const vlocs=await api(`/v1/appStoreVersions/${versionId}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale,description,keywords,whatsNew,promotionalText,marketingUrl,supportUrl`);
let enLoc=vlocs.j.data?.find(l=>l.attributes.locale==="en-US");
const wanted={whatsNew:WHATS_NEW,description:carry.description,keywords:carry.keywords,promotionalText:carry.promotionalText,marketingUrl:carry.marketingUrl,supportUrl:carry.supportUrl};
if(enLoc){
  const patch=await api(`/v1/appStoreVersionLocalizations/${enLoc.id}`,"PATCH",{data:{type:"appStoreVersionLocalizations",id:enLoc.id,attributes:wanted}});
  if(!patch.ok){console.error(`patch loc failed ${patch.status}: ${JSON.stringify(patch.j)}`);process.exit(1);}
  console.log(`updated en-US localization: whatsNew set, metadata carried forward`);
}else{
  const post=await api(`/v1/appStoreVersionLocalizations`,"POST",{data:{type:"appStoreVersionLocalizations",attributes:{locale:"en-US",...wanted},relationships:{appStoreVersion:{data:{type:"appStoreVersions",id:versionId}}}}});
  if(!post.ok){console.error(`create loc failed ${post.status}: ${JSON.stringify(post.j)}`);process.exit(1);}
  console.log(`created en-US localization with metadata + What's New`);
}

// 3) Fill the subtitle on the editable appInfo localization (was omitted at 1.0)
const infos=await api(`/v1/apps/${app.id}/appInfos?include=appInfoLocalizations&fields[appInfoLocalizations]=locale,subtitle&fields[appInfos]=state`);
let subtitleDone=false;
for(const loc of (infos.j.included||[]).filter(i=>i.type==="appInfoLocalizations" && i.attributes.locale==="en-US")){
  const p=await api(`/v1/appInfoLocalizations/${loc.id}`,"PATCH",{data:{type:"appInfoLocalizations",id:loc.id,attributes:{subtitle:SUBTITLE}}});
  if(p.ok){console.log(`subtitle set to "${SUBTITLE}" on appInfoLoc ${loc.id}`);subtitleDone=true;break;}
  else console.log(`  (subtitle not editable on appInfoLoc ${loc.id}: ${p.status})`);
}
if(!subtitleDone) console.log(`WARN: could not set subtitle via API — set it manually on the 1.0.1 version in ASC`);

// 4) Attach the build (setup only — this is not a review submission)
if(BUILD_NUMBER){
  const builds=await api(`/v1/builds?filter[app]=${app.id}&filter[version]=${encodeURIComponent(BUILD_NUMBER)}&fields[builds]=version,processingState&limit=1`);
  const build=builds.j.data?.[0];
  if(!build){console.log(`WARN: build ${BUILD_NUMBER} not found — attach it manually`);}
  else if(build.attributes.processingState!=="VALID"){console.log(`WARN: build ${BUILD_NUMBER} is ${build.attributes.processingState}, not VALID — not attaching`);}
  else{
    const rel=await api(`/v1/appStoreVersions/${versionId}/relationships/build`,"PATCH",{data:{type:"builds",id:build.id}});
    if(rel.ok) console.log(`attached build ${BUILD_NUMBER} (${build.id}) to version ${NEW_VERSION}`);
    else console.log(`WARN: attach build failed ${rel.status}: ${JSON.stringify(rel.j)}`);
  }
}

console.log(`\nDONE — version ${NEW_VERSION} is set up (NOT submitted for review). Review in ASC, then submit when ready.`);
