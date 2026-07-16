#!/usr/bin/env node
// Read-only dump of the app's version + info localization metadata, to plan a new version.
import crypto from "node:crypto"; import fs from "node:fs"; import os from "node:os";
const KEY_ID=process.env.ASC_KEY_ID, ISSUER_ID=process.env.ASC_ISSUER_ID;
const pk=crypto.createPrivateKey(fs.readFileSync(`${os.homedir()}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`));
const b=x=>Buffer.from(x).toString("base64url");
function jwt(){const h=b(JSON.stringify({alg:"ES256",kid:KEY_ID,typ:"JWT"}));const n=Math.floor(Date.now()/1000);const p=b(JSON.stringify({iss:ISSUER_ID,iat:n,exp:n+600,aud:"appstoreconnect-v1"}));const s=crypto.createSign("SHA256");s.update(`${h}.${p}`);return `${h}.${p}.${b(s.sign({key:pk,dsaEncoding:"ieee-p1363"}))}`;}
async function api(p){const r=await fetch(`https://api.appstoreconnect.apple.com${p}`,{headers:{Authorization:`Bearer ${jwt()}`}});return {ok:r.ok,status:r.status,j:await r.json()};}

const apps=await api(`/v1/apps?filter[bundleId]=com.otterpace.app&fields[apps]=name,primaryLocale`);
const app=apps.j.data[0];
console.log(`app ${app.attributes.name} (${app.id}) primaryLocale=${app.attributes.primaryLocale}`);

// App-level info (name/subtitle/privacy live here, version-independent)
const infos=await api(`/v1/apps/${app.id}/appInfos?include=appInfoLocalizations&fields[appInfoLocalizations]=locale,name,subtitle,privacyPolicyUrl&fields[appInfos]=appStoreState,state`);
for(const info of infos.j.data){
  console.log(`\nappInfo ${info.id} state=${info.attributes.appStoreState||info.attributes.state}`);
}
for(const loc of (infos.j.included||[]).filter(i=>i.type==="appInfoLocalizations")){
  const a=loc.attributes; console.log(`  appInfoLoc ${loc.id} [${a.locale}] name="${a.name}" subtitle="${a.subtitle??"—"}" privacy="${a.privacyPolicyUrl??"—"}"`);
}

// Versions + their localizations
const vers=await api(`/v1/apps/${app.id}/appStoreVersions?include=appStoreVersionLocalizations&fields[appStoreVersions]=versionString,appStoreState,copyright&fields[appStoreVersionLocalizations]=locale,description,keywords,whatsNew,promotionalText,marketingUrl,supportUrl&limit=3&sort=-versionString`);
for(const v of vers.j.data){
  console.log(`\nversion ${v.attributes.versionString} state=${v.attributes.appStoreState} copyright="${v.attributes.copyright}" id=${v.id}`);
  const locIds=new Set((v.relationships?.appStoreVersionLocalizations?.data||[]).map(d=>d.id));
  for(const loc of (vers.j.included||[]).filter(i=>i.type==="appStoreVersionLocalizations" && locIds.has(i.id))){
    const a=loc.attributes;
    console.log(`  [${a.locale}] loc-id=${loc.id}`);
    console.log(`    keywords="${a.keywords??"—"}"`);
    console.log(`    promo="${(a.promotionalText??"—").slice(0,80)}"`);
    console.log(`    whatsNew="${(a.whatsNew??"—").slice(0,80)}"`);
    console.log(`    supportUrl="${a.supportUrl??"—"}" marketingUrl="${a.marketingUrl??"—"}"`);
    console.log(`    description(len=${(a.description??"").length})="${(a.description??"—").slice(0,60)}..."`);
  }
}
