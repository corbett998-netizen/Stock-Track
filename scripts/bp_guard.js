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
  if (projectId !== 'easy-stock-track') {
    log(`STOCKTRACK-CHAT RESULT: BLOCKED | firebase.projectId='${projectId}' is not 'easy-stock-track' | class=wrong-project retryable=no`);
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
  let failed = 0;
  for (const c of cases) {
    if (!c.ok) failed++;
    console.log(`${c.ok ? 'PASS' : 'FAIL'}  guard: ${c.name}` + (c.ok ? '' : `  (got ${JSON.stringify(c.got)}, want ${JSON.stringify(c.want)})`));
  }
  return failed;
}

module.exports = { BP_FORBIDDEN, findBpLeak, assertStockTrackOnly, runGuardSelfTest };

if (require.main === module) {
  const failed = runGuardSelfTest();
  console.log(`\n${failed === 0 ? 'BP-GUARD RESULT: PASS' : 'BP-GUARD RESULT: FAIL'} | ${failed} failing`);
  process.exit(failed === 0 ? 0 : 1);
}
