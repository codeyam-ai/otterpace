#!/usr/bin/env node
// Submit an App Store version for App Store Review (the irreversible step).
// Uses the current reviewSubmissions flow: create submission -> add the version
// as an item -> mark submitted. Usage: ... node Scripts/asc-submit-appstore.mjs <versionString>
import crypto from "node:crypto"; import fs from "node:fs"; import os from "node:os";
const KEY_ID=process.env.ASC_KEY_ID, ISSUER_ID=process.env.ASC_ISSUER_ID;
const VERSION=process.argv[2]||"1.0.1"; const BUNDLE_ID="com.otterpace.app";
if(!KEY_ID||!ISSUER_ID){console.error("set ASC_KEY_ID and ASC_ISSUER_ID");process.exit(1);}
const pk=crypto.createPrivateKey(fs.readFileSync(`${os.homedir()}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`));
const b=x=>Buffer.from(x).toString("base64url");
function jwt(){const h=b(JSON.stringify({alg:"ES256",kid:KEY_ID,typ:"JWT"}));const n=Math.floor(Date.now()/1000);const p=b(JSON.stringify({iss:ISSUER_ID,iat:n,exp:n+600,aud:"appstoreconnect-v1"}));const s=crypto.createSign("SHA256");s.update(`${h}.${p}`);return `${h}.${p}.${b(s.sign({key:pk,dsaEncoding:"ieee-p1363"}))}`;}
async function api(path,method="GET",body=null){const r=await fetch(`https://api.appstoreconnect.apple.com${path}`,{method,headers:{Authorization:`Bearer ${jwt()}`,...(body?{"Content-Type":"application/json"}:{})},body:body?JSON.stringify(body):undefined});const t=await r.text();return {ok:r.ok,status:r.status,j:t?JSON.parse(t):null};}

const apps=await api(`/v1/apps?filter[bundleId]=${BUNDLE_ID}&fields[apps]=name`);
const app=apps.j.data?.[0]; if(!app){console.error("no app");process.exit(1);}

const vers=await api(`/v1/apps/${app.id}/appStoreVersions?filter[versionString]=${encodeURIComponent(VERSION)}&fields[appStoreVersions]=versionString,appVersionState&limit=1`);
const version=vers.j.data?.[0]; if(!version){console.error(`version ${VERSION} not found`);process.exit(1);}
console.log(`version ${VERSION}: ${version.attributes.appVersionState} (${version.id})`);

// Reuse an open review submission if one exists, else create one.
const existing=await api(`/v1/reviewSubmissions?filter[app]=${app.id}&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_PROGRESS,UNRESOLVED_ISSUES&fields[reviewSubmissions]=state,platform&limit=5`);
let subId=existing.j.data?.[0]?.id;
if(subId) console.log(`reusing open reviewSubmission ${subId} (${existing.j.data[0].attributes.state})`);
else{
  const create=await api(`/v1/reviewSubmissions`,"POST",{data:{type:"reviewSubmissions",attributes:{platform:"IOS"},relationships:{app:{data:{type:"apps",id:app.id}}}}});
  if(!create.ok){console.error(`create submission failed ${create.status}: ${JSON.stringify(create.j)}`);process.exit(1);}
  subId=create.j.data.id; console.log(`created reviewSubmission ${subId}`);
}

// Add the version as an item (ignore if already present).
const item=await api(`/v1/reviewSubmissionItems`,"POST",{data:{type:"reviewSubmissionItems",relationships:{reviewSubmission:{data:{type:"reviewSubmissions",id:subId}},appStoreVersion:{data:{type:"appStoreVersions",id:version.id}}}}});
if(item.ok) console.log(`added version ${VERSION} as a review item`);
else if([409,422].includes(item.status)) console.log(`version item already present (${item.status})`);
else{console.error(`add item failed ${item.status}: ${JSON.stringify(item.j)}`);process.exit(1);}

// Mark the submission as submitted (this is the actual submit).
const submit=await api(`/v1/reviewSubmissions/${subId}`,"PATCH",{data:{type:"reviewSubmissions",id:subId,attributes:{submitted:true}}});
if(!submit.ok){console.error(`SUBMIT failed ${submit.status}: ${JSON.stringify(submit.j)}`);process.exit(1);}
console.log(`SUBMITTED for App Store Review — reviewSubmission state=${submit.j.data?.attributes?.state}`);
