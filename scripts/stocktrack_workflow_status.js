#!/usr/bin/env node
/**
 * stocktrack_workflow_status.js — publishes the operator's WORKFLOW PROJECTION to
 * `system/workflowContext` in Brandon's Firebase project (easy-stock-track). The
 * in-app chat dashboard reads this doc (read-only) and shows a stale banner when it
 * ages; when nothing is published the dashboard reads "nothing published yet"
 * (empty-but-honest), so this closes the dangling wire.
 *
 * Same separation contract as stocktrack_chat.js: ADC (NOT a downloaded key), an
 * EXPLICIT projectId pin from harness/project.config.json, and the BP-abort guard —
 * so it is structurally incapable of writing another project's data.
 *
 *   node stocktrack_workflow_status.js --publish [--build "1.0(5)"] [--lane "..."]
 *        [--state "..."] [--waiting "..."]      write the projection (+ bump the poke)
 *   node stocktrack_workflow_status.js --read     print the current projection
 *   node stocktrack_workflow_status.js --dry-run --publish ...   preview, no write
 *   node stocktrack_workflow_status.js --selftest pure-logic checks (guard + payload), no creds
 *
 * LIVE publish is BLOCKED on Brandon's IAM grant + `gcloud auth application-default
 * login` (see docs/FOR_BRANDON_harness_backend.md); the code + --selftest + --dry-run
 * are complete.
 */
'use strict';

const harness = require('../harness/harness_config.js');
const { findBpLeak, assertStockTrackOnly } = require('./bp_guard.js');

const PROJECT_ID = harness.get('firebase.projectId');
const DATABASE_ID = harness.tryGet('firebase.databaseId', '(default)');
const STORAGE_BUCKET = harness.tryGet('firebase.storageBucket', `${PROJECT_ID}.firebasestorage.app`);
const WORKFLOW_DOC = harness.get('collections.workflowContext');
const POKE_DOC = harness.get('collections.poke');
const OWNER_ROLE = harness.get('project.ownerRole');

function assertNoBpLeak() {
  assertStockTrackOnly([PROJECT_ID, STORAGE_BUCKET, WORKFLOW_DOC, POKE_DOC, OWNER_ROLE], PROJECT_ID);
}

let _db = null;
function db() {
  if (_db) return _db;
  assertNoBpLeak();
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
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

/** PURE: build the projection payload from parsed flags (no timestamp). */
function buildProjection({ build, lane, state, waiting }) {
  const p = {};
  if (build) p.build = build;
  if (lane) p.lane = lane;
  if (state) p.state = state;
  if (waiting) p.waitingOnOwner = waiting;
  return p;
}

function parseFlags(args) {
  const after = (flag) => { const i = args.indexOf(flag); return i !== -1 ? args[i + 1] : undefined; };
  return { build: after('--build'), lane: after('--lane'), state: after('--state'), waiting: after('--waiting') };
}

async function cmdPublish(flags, dry) {
  const projection = buildProjection(flags);
  if (Object.keys(projection).length === 0) {
    console.error('STOCKTRACK-WF RESULT: FAIL | nothing to publish — pass at least one of --build/--lane/--state/--waiting | class=usage retryable=no');
    process.exit(1);
  }
  if (dry) {
    console.log(`STOCKTRACK-WF DRY-RUN | would write to: ${WORKFLOW_DOC}`);
    console.log(JSON.stringify({ ...projection, updatedAt: '<serverTimestamp>' }, null, 2));
    console.log('STOCKTRACK-WF RESULT: PASS | dry-run preview only, nothing written | class=dry-run');
    return;
  }
  const admin = require('firebase-admin');
  await db().doc(WORKFLOW_DOC).set(
    { ...projection, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );
  try {
    await db().doc(POKE_DOC).set(
      { pokedAt: admin.firestore.FieldValue.serverTimestamp(), note: 'workflowContext published', by: 'orchestrator' },
    );
  } catch (_) { /* poke is best-effort */ }
  console.log(`STOCKTRACK-WF RESULT: PASS | published ${Object.keys(projection).length} field(s) to ${WORKFLOW_DOC}`);
}

async function cmdRead() {
  const doc = await db().doc(WORKFLOW_DOC).get();
  if (!doc.exists) {
    console.log(`STOCKTRACK-WF RESULT: EMPTY | nothing published at ${WORKFLOW_DOC} yet | class=not-published`);
    return;
  }
  console.log(`STOCKTRACK-WF — ${WORKFLOW_DOC}:`);
  const d = doc.data();
  for (const [k, v] of Object.entries(d)) {
    const val = v && typeof v.toDate === 'function' ? v.toDate().toISOString() : v;
    console.log(`  ${k}: ${val}`);
  }
}

function runSelfTest() {
  const cases = [];
  const eq = (name, got, want) => cases.push({ name, ok: got === want, got, want });

  const { runGuardSelfTest } = require('./bp_guard.js');
  cases.push({ name: 'BP-abort guard unit tests', ok: runGuardSelfTest() === 0 });

  eq('config projectId is easy-stock-track', PROJECT_ID, 'easy-stock-track');
  eq('workflow doc is system/workflowContext', WORKFLOW_DOC, 'system/workflowContext');
  eq('resolved config carries NO BP literal', findBpLeak([PROJECT_ID, STORAGE_BUCKET, WORKFLOW_DOC, POKE_DOC, OWNER_ROLE]), null);

  // Pure projection builder.
  const p = buildProjection({ build: '1.0(5)', lane: 'harness', state: 'green', waiting: 'nothing' });
  eq('projection carries build', p.build, '1.0(5)');
  eq('projection carries waitingOnOwner', p.waitingOnOwner, 'nothing');
  eq('projection omits empty flags', JSON.stringify(buildProjection({})), '{}');

  let failed = 0;
  for (const c of cases) {
    if (!c.ok) failed++;
    console.log(`${c.ok ? 'PASS' : 'FAIL'}  ${c.name}` + (c.ok ? '' : `  (got ${JSON.stringify(c.got)}, want ${JSON.stringify(c.want)})`));
  }
  console.log(`\n${failed === 0 ? 'STOCKTRACK-WF RESULT: PASS' : 'STOCKTRACK-WF RESULT: FAIL'} | selftest ${cases.length - failed}/${cases.length}${failed ? ' | class=selftest retryable=no' : ''}`);
  process.exit(failed === 0 ? 0 : 1);
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help') || args.length === 0) {
    console.log('usage: stocktrack_workflow_status.js --publish [--build x --lane x --state x --waiting x] | --read | [--dry-run] | --selftest');
    process.exit(0);
  }
  if (args.includes('--selftest')) return runSelfTest();
  const dry = args.includes('--dry-run');
  if (args.includes('--publish')) return cmdPublish(parseFlags(args), dry);
  if (args.includes('--read')) return cmdRead();
  console.error('STOCKTRACK-WF RESULT: FAIL | unknown args | class=usage retryable=no');
  process.exit(1);
}

main().catch((e) => {
  const msg = (e && e.message) || String(e);
  if (/Could not load the default credentials|application default credentials/i.test(msg)) {
    console.error('STOCKTRACK-WF RESULT: BLOCKED | no Application Default Credentials — run `gcloud auth application-default login` as the granted ops identity (see docs/FOR_BRANDON_harness_backend.md) | class=adc-missing retryable=yes');
    process.exit(2);
  }
  console.error('STOCKTRACK-WF RESULT: FAIL | ' + msg);
  process.exit(1);
});

module.exports = { buildProjection, assertNoBpLeak };
