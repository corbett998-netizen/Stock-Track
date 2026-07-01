#!/usr/bin/env node
/**
 * stocktrack_chat.js — orchestrator side of the in-app owner↔orchestrator chat for
 * Stock-Track, pinned 100% to Brandon's Firebase project (easy-stock-track).
 *
 * This is the Stock-Track re-instantiation of Blueprint's chat.js. Deliberate
 * DEVIATION from BP's pattern (Pete's security rule — "permissions, never a shared
 * key"): it authenticates via APPLICATION DEFAULT CREDENTIALS (ADC), NOT a
 * downloaded service-account key. Nothing secret is ever committed or emailed.
 *   • Brandon grants an ops identity IAM access on easy-stock-track (roles/datastore.user
 *     + a Storage object role) — see docs/FOR_BRANDON_harness_backend.md.
 *   • That identity runs `gcloud auth application-default login` once.
 *   • This script inits the Admin SDK with applicationDefault() + an EXPLICIT
 *     projectId pin from harness/project.config.json (easy-stock-track).
 *
 * SEPARATION (R1 block): a BP-ABORT GUARD refuses to run if any Blueprint literal
 * is reachable from the resolved config — structurally incapable of touching BP.
 *
 *   node stocktrack_chat.js --read [sinceMillis]   print the owner's messages after sinceMillis + maxMillis cursor
 *   node stocktrack_chat.js --send "reply text"    post an orchestrator reply (+ bump the poke)
 *   node stocktrack_chat.js --build "1.0(N) — …"   post a build message + auto-create a dogfood check-item
 *   node stocktrack_chat.js --reports              list the owner's report queue
 *   node stocktrack_chat.js --uid <uid>            pin the owner UID (else auto-discover the active thread)
 *   node stocktrack_chat.js --selftest             pure-logic checks (BP-guard + config), no Firestore/creds
 *
 * Owner UID: anonymous Auth mints a per-install UID, so it is NOT a fixed literal.
 * The script AUTO-DISCOVERS the active thread (the orchestratorChat doc with the
 * newest message), or takes --uid / STOCKTRACK_OWNER_UID.
 */
'use strict';

const harness = require('../harness/harness_config.js');
// The BP-abort guard's blocklist lives in its OWN module (the one file that names BP
// literals, so it can BLOCK them) — this file itself stays free of any BP literal.
const { findBpLeak, assertStockTrackOnly } = require('./bp_guard.js');

const PROJECT_ID = harness.get('firebase.projectId');
const DATABASE_ID = harness.tryGet('firebase.databaseId', '(default)');
const STORAGE_BUCKET = harness.tryGet('firebase.storageBucket', `${PROJECT_ID}.firebasestorage.app`);
const CHAT_ROOT = harness.get('collections.chatRoot');
const REPORTS_COLLECTION = harness.get('collections.reports');
const POKE_DOC = harness.get('collections.poke');
const OWNER_ROLE = harness.get('project.ownerRole');

// ─── SEPARATION: BP-ABORT GUARD (R1) ────────────────────────────────────────────
// Any Blueprint identity reachable from the resolved config = refuse to run. Makes
// cross-writing BP structurally impossible (blocklist in scripts/bp_guard.js).
function assertNoBpLeak() {
  assertStockTrackOnly(
    [PROJECT_ID, STORAGE_BUCKET, CHAT_ROOT, REPORTS_COLLECTION, POKE_DOC, OWNER_ROLE],
    PROJECT_ID,
  );
}

// ─── Firestore (Admin SDK via ADC — NO key file) ────────────────────────────────
let _db = null;
function db() {
  if (_db) return _db;
  assertNoBpLeak();
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    // ADC: resolves the gcloud application-default credentials of the granted ops
    // identity. NO service-account.json is read. projectId is pinned EXPLICITLY so
    // an ambient default can never redirect the write to another project.
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT_ID,
      storageBucket: STORAGE_BUCKET,
    });
  }
  const { getFirestore } = require('firebase-admin/firestore');
  _db = DATABASE_ID === '(default)' ? admin.firestore() : getFirestore(admin.app(), DATABASE_ID);
  return _db;
}

const messages = (uid) => db().collection(CHAT_ROOT).doc(uid).collection('messages');

/** Auto-discover the active owner thread: the orchestratorChat doc whose newest
 *  message is the most recent. Returns the uid, or null if none. */
async function discoverUid() {
  const explicit = process.env.STOCKTRACK_OWNER_UID;
  if (explicit) return explicit;
  const threads = await db().collection(CHAT_ROOT).listDocuments();
  let best = null;
  let bestMs = -1;
  for (const t of threads) {
    const snap = await t.collection('messages').orderBy('createdAt', 'desc').limit(1).get();
    if (snap.empty) continue;
    const ms = snap.docs[0].data().createdAt?.toMillis?.() || 0;
    if (ms > bestMs) { bestMs = ms; best = t.id; }
  }
  return best;
}

async function resolveUid(argUid) {
  if (argUid) return argUid;
  const uid = await discoverUid();
  if (!uid) {
    console.error('STOCKTRACK-CHAT RESULT: EMPTY | no owner thread found in orchestratorChat (owner must open the app + send once, or Firestore/Anonymous-Auth not enabled yet)');
    process.exit(0);
  }
  return uid;
}

async function bumpPoke(uid, note) {
  try {
    const admin = require('firebase-admin');
    await db().doc(POKE_DOC).set({
      pokedAt: admin.firestore.FieldValue.serverTimestamp(),
      note: String(note).slice(0, 120),
      by: 'orchestrator',
    });
  } catch (e) { /* best-effort — never fail the reply on a poke hiccup */ }
}

async function cmdRead(sinceMs, uid) {
  const snap = await messages(uid).orderBy('createdAt').get();
  let maxMs = 0;
  const out = [];
  snap.forEach((d) => {
    const m = d.data();
    const ms = m.createdAt?.toMillis?.() || 0;
    if (ms > maxMs) maxMs = ms;
    if (m.role === OWNER_ROLE && ms > sinceMs) {
      out.push(`${new Date(ms).toISOString()}  [${m.via || 'text'}]  ${m.text}`);
    }
  });
  console.log(`STOCKTRACK-CHAT (thread ${uid}) — OWNER MESSAGES (oldest→newest):`);
  out.forEach((l) => console.log('  ' + l));
  if (!out.length) console.log('  (none new)');
  console.log('maxMillis=' + maxMs);
}

async function cmdSend(text, uid) {
  const admin = require('firebase-admin');
  await messages(uid).add({
    role: 'orchestrator',
    text,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    via: 'text',
  });
  await bumpPoke(uid, `orch reply: ${text}`);
  console.log(`STOCKTRACK-CHAT RESULT: PASS | sent orchestrator reply to thread ${uid}`);
}

async function cmdBuild(msg, uid) {
  const admin = require('firebase-admin');
  await messages(uid).add({
    role: 'orchestrator',
    text: msg,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    via: 'text',
  });
  await db().collection(REPORTS_COLLECTION).add({
    userId: uid,
    note: msg,
    title: msg.split('\n')[0].slice(0, 80),
    recommendedFix: msg,
    area: 'build',
    status: 'fixed',
    awaitingVerification: true,
    // backfilled: this is an operator-announced check-item, not an owner-filed bug —
    // lets the in-app queue distinguish build items from real reports.
    backfilled: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await bumpPoke(uid, `build: ${msg}`);
  console.log(`STOCKTRACK-CHAT RESULT: PASS | build message + dogfood check-item created in thread ${uid}`);
}

async function cmdReports(uid) {
  const snap = await db().collection(REPORTS_COLLECTION).where('userId', '==', uid).get();
  const rows = [];
  snap.forEach((d) => {
    const r = d.data();
    rows.push({ ms: r.createdAt?.toMillis?.() || 0, line: `${d.id}  [${r.status || 'new'}]  ${(r.note || '').split('\n')[0].slice(0, 100)}` });
  });
  rows.sort((a, b) => b.ms - a.ms);
  console.log(`STOCKTRACK-CHAT (thread ${uid}) — REPORT QUEUE (newest→oldest):`);
  rows.forEach((r) => console.log('  ' + r.line));
  if (!rows.length) console.log('  (none)');
}

function runSelfTest() {
  const cases = [];
  const eq = (name, got, want) => cases.push({ name, ok: got === want, got, want });

  // The BP-abort guard is unit-tested in its own module (which self-excludes from
  // the anti-leak scan). Run it here so `--selftest` covers separation too.
  const { runGuardSelfTest } = require('./bp_guard.js');
  const guardFailed = runGuardSelfTest();
  cases.push({ name: 'BP-abort guard unit tests', ok: guardFailed === 0, got: guardFailed, want: 0 });

  // The live config resolves to Stock-Track (not Blueprint), with zero BP literal.
  eq('config projectId is easy-stock-track', PROJECT_ID, 'easy-stock-track');
  eq('config reports collection is stockIssueReports', REPORTS_COLLECTION, 'stockIssueReports');
  eq('config owner role is brandon', OWNER_ROLE, 'brandon');
  eq('resolved config carries NO BP literal',
    findBpLeak([PROJECT_ID, STORAGE_BUCKET, CHAT_ROOT, REPORTS_COLLECTION, POKE_DOC, OWNER_ROLE]), null);

  let failed = 0;
  for (const c of cases) {
    if (!c.ok) failed++;
    console.log(`${c.ok ? 'PASS' : 'FAIL'}  ${c.name}` + (c.ok ? '' : `  (got ${JSON.stringify(c.got)}, want ${JSON.stringify(c.want)})`));
  }
  console.log(`\n${failed === 0 ? 'STOCKTRACK-CHAT RESULT: PASS' : 'STOCKTRACK-CHAT RESULT: FAIL'} | selftest ${cases.length - failed}/${cases.length}${failed ? ' | class=selftest retryable=no' : ''}`);
  process.exit(failed === 0 ? 0 : 1);
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help') || args.length === 0) {
    console.log('usage: stocktrack_chat.js --read [sinceMillis] | --send "text" | --build "1.0(N) — desc" | --reports | --uid <uid> | --selftest');
    process.exit(0);
  }
  if (args.includes('--selftest')) return runSelfTest();

  const ui = args.indexOf('--uid');
  const argUid = ui !== -1 ? (args[ui + 1] || null) : null;

  if (args.includes('--read')) {
    const since = Number(args[args.indexOf('--read') + 1]) || 0;
    return cmdRead(since, await resolveUid(argUid));
  }
  const si = args.indexOf('--send');
  if (si !== -1 && args[si + 1]) return cmdSend(args[si + 1], await resolveUid(argUid));
  const bi = args.indexOf('--build');
  if (bi !== -1 && args[bi + 1]) return cmdBuild(args[bi + 1], await resolveUid(argUid));
  if (args.includes('--reports')) return cmdReports(await resolveUid(argUid));

  console.error('STOCKTRACK-CHAT RESULT: FAIL | unknown args | class=usage retryable=no');
  process.exit(1);
}

main().catch((e) => {
  const msg = (e && e.message) || String(e);
  // Missing ADC is the expected pre-grant state — name it as an actionable setup step.
  if (/Could not load the default credentials|application default credentials/i.test(msg)) {
    console.error('STOCKTRACK-CHAT RESULT: BLOCKED | no Application Default Credentials — run `gcloud auth application-default login` as the granted ops identity (see docs/FOR_BRANDON_harness_backend.md) | class=adc-missing retryable=yes');
    process.exit(2);
  }
  console.error('STOCKTRACK-CHAT RESULT: FAIL | ' + msg);
  process.exit(1);
});

module.exports = { assertNoBpLeak };
