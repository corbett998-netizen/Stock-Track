#!/usr/bin/env node
/**
 * bp_guard.js — the Blueprint-abort SEPARATION guard for the Stock-Track orchestrator.
 *
 * This is the ONE file that legitimately NAMES Blueprint identity literals — because
 * its whole job is to BLOCK them. It is deliberately EXCLUDED from
 * harness/harness_antileak_scan.sh (exactly as Blueprint's own scanner self-excludes
 * its pattern table: "contains the forbidden patterns by definition"). Everything
 * else in scripts/ + lib/features/dev stays IN scan scope.
 *
 * The guard makes cross-writing Blueprint structurally impossible: if any BP literal
 * is reachable from the resolved Stock-Track config, the orchestrator refuses to run.
 *
 * TWO complementary mechanisms (net protection is a strict SUPERSET of the old blocklist):
 *   1. CONFIG-DRIVEN foreign-identity detection (findForeignFirebaseIdentity) — flags any
 *      Firebase/GCP project bucket/domain whose slug is NOT the allowed project. This
 *      generalizes to ANY foreign project (not just Blueprint) with no edits.
 *   2. REFERENCE-LITERAL blocklist (findBpLeak / BP_FORBIDDEN, retained) — the known
 *      reference literals (bare owner UIDs, repo paths, package prefix) an allowlist cannot
 *      safely shape-detect. Kept as a backstop so the guard is never WEAKER than before.
 * EXPECTED_PROJECT_ID is an INDEPENDENT literal pin (deliberately NOT read from config) so a
 * tampered config can never re-point the guard at another project.
 */
'use strict';

// The Blueprint identity literals the Stock-Track orchestrator must NEVER touch.
const BP_FORBIDDEN = [
  'blueprintfitnesssubscriptions', // BP Firebase project id
  '9kc4UuTkrJO9VJ7Pjut9yx528kj1', // BP canonical owner uid
  '1772935920220', // BP legacy uid
  'TeoQTj5ownPsguKG5djqbHqBMOr1', // BP Google-identity uid
  '677287134512', // BP project number / App-Dist id fragment
  'io.bcd', // BP android/ios package prefix
  'blueprint-fitness-app', // BP repo root
];

/** PURE: the first BP literal found in `values`, else null. */
function findBpLeak(values) {
  for (const v of values) {
    const s = String(v == null ? '' : v).toLowerCase();
    for (const bad of BP_FORBIDDEN) {
      if (s.includes(bad.toLowerCase())) return bad;
    }
  }
  return null;
}

// The project this orchestrator IS pinned to. An INDEPENDENT literal backstop (deliberately
// NOT read from config, so a tampered config can never re-point the guard). The static gate
// harness/harness_antileak_scan.sh derives the allowed identity FROM config; this runtime pin
// is the belt-and-suspenders that config self-attestation cannot provide.
const EXPECTED_PROJECT_ID = 'easy-stock-track';

// Firebase/GCP project-scoped identity domain shape. A bucket/domain whose slug differs from
// the allowed project id is a FOREIGN backend. (App-ID shape detection lives in the static
// file scanner, where — unlike resolved config values — no legitimate own App-ID appears.)
const FIREBASE_IDENTITY_RX = /\b([a-z0-9][a-z0-9-]{2,})\.(?:firebasestorage\.app|appspot\.com|firebaseio\.com|firebaseapp\.com|web\.app)\b/i;

/**
 * PURE: the first FOREIGN Firebase/GCP identity token in `values` — a project bucket/domain
 * whose slug != `allowedProjectId` — else null. Config-driven (the allowed id comes from
 * config), so it generalizes to ANY foreign project, not a fixed reference blocklist.
 * Complements findBpLeak, which stays as the known-literal backstop.
 */
function findForeignFirebaseIdentity(values, allowedProjectId) {
  const allowed = String(allowedProjectId == null ? '' : allowedProjectId).toLowerCase();
  for (const v of values) {
    const s = String(v == null ? '' : v);
    const dom = s.match(FIREBASE_IDENTITY_RX);
    if (dom && dom[1].toLowerCase() !== allowed) return dom[0];
  }
  return null;
}

/**
 * Abort (process.exit) if any BP literal is reachable from `values`, or if the
 * project isn't pinned to easy-stock-track. `log` defaults to console.error.
 */
function assertStockTrackOnly(values, projectId, exit = process.exit, log = console.error) {
  const leak = findBpLeak(values);
  if (leak) {
    log(`STOCKTRACK-CHAT RESULT: BLOCKED | Blueprint literal '${leak}' reachable from config | class=bp-leak retryable=no`);
    return exit(3);
  }
  const foreign = findForeignFirebaseIdentity(values, EXPECTED_PROJECT_ID);
  if (foreign) {
    log(`STOCKTRACK-CHAT RESULT: BLOCKED | foreign Firebase identity '${foreign}' reachable from config (allowed project '${EXPECTED_PROJECT_ID}') | class=foreign-identity retryable=no`);
    return exit(3);
  }
  if (projectId !== EXPECTED_PROJECT_ID) {
    log(`STOCKTRACK-CHAT RESULT: BLOCKED | firebase.projectId='${projectId}' is not '${EXPECTED_PROJECT_ID}' | class=wrong-project retryable=no`);
    return exit(3);
  }
  return true;
}

/** Unit-test the guard against every forbidden literal (kept HERE so the caller
 *  script never has to name a BP literal). */
function runGuardSelfTest() {
  const cases = [];
  const eq = (name, got, want) => cases.push({ name, ok: got === want, got, want });
  eq('catches BP project id', findBpLeak(['blueprintfitnesssubscriptions']), 'blueprintfitnesssubscriptions');
  eq('catches BP owner uid', findBpLeak(['x', '9kc4UuTkrJO9VJ7Pjut9yx528kj1']), '9kc4UuTkrJO9VJ7Pjut9yx528kj1');
  eq('catches BP app-dist number', findBpLeak(['1:677287134512:android:abc']), '677287134512');
  eq('catches BP package prefix', findBpLeak(['io.bcd.blueprint']), 'io.bcd');
  eq('catches BP repo root', findBpLeak(['/mnt/c/dev/blueprint-fitness-app/x']), 'blueprint-fitness-app');
  eq('passes clean Stock-Track values', findBpLeak(['easy-stock-track', 'orchestratorChat', 'stockIssueReports', 'brandon']), null);
  // config-driven FOREIGN-identity detection — generalizes beyond the fixed blocklist
  eq('foreign: catches a non-reference foreign bucket',
    findForeignFirebaseIdentity(['acme-widgets-prod.firebasestorage.app'], EXPECTED_PROJECT_ID), 'acme-widgets-prod.firebasestorage.app');
  eq('foreign: catches a foreign appspot bucket',
    findForeignFirebaseIdentity(['some-other-proj.appspot.com'], EXPECTED_PROJECT_ID), 'some-other-proj.appspot.com');
  eq('foreign: allows THIS project bucket',
    findForeignFirebaseIdentity(['easy-stock-track.firebasestorage.app', 'orchestratorChat'], EXPECTED_PROJECT_ID), null);
  eq('foreign: allows clean non-domain values',
    findForeignFirebaseIdentity(['easy-stock-track', 'stockIssueReports', 'brandon'], EXPECTED_PROJECT_ID), null);
  let failed = 0;
  for (const c of cases) {
    if (!c.ok) failed++;
    console.log(`${c.ok ? 'PASS' : 'FAIL'}  guard: ${c.name}` + (c.ok ? '' : `  (got ${JSON.stringify(c.got)}, want ${JSON.stringify(c.want)})`));
  }
  return failed;
}

module.exports = { BP_FORBIDDEN, EXPECTED_PROJECT_ID, findBpLeak, findForeignFirebaseIdentity, assertStockTrackOnly, runGuardSelfTest };

if (require.main === module) {
  const failed = runGuardSelfTest();
  console.log(`\n${failed === 0 ? 'BP-GUARD RESULT: PASS' : 'BP-GUARD RESULT: FAIL'} | ${failed} failing`);
  process.exit(failed === 0 ? 0 : 1);
}
