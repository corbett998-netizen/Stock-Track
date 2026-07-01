#!/usr/bin/env node
/**
 * gen_app_config.js — generate the in-app compile-time harness config (Dart) from project.config.json.
 *
 * Generalized-harness substrate (Stage A). The Flutter app's dev/coordination surfaces (chat sheet,
 * report queue, dashboard/vision sheets) currently hardcode collection/doc names + the owner-role.
 * This generator lifts those build-time constants into a generated Dart file so the app reads project
 * IDENTITY from one source. For the worked-example project the generated file holds that project's
 * *exact* current literals -> identical app behavior (Stage-A invariant).
 *
 * Usage:
 *   node gen_app_config.js            generate lib/harness/harness_config.g.dart from harness/project.config.json
 *   node gen_app_config.js --check    fail (non-zero) if the on-disk generated file is stale vs config
 *   node gen_app_config.js --stdout   print the generated Dart to stdout (no write)
 *   node gen_app_config.js --help
 *
 * NOTE: the output Dart file is GENERATED — do not hand-edit it; change project.config.json + regen.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const cfgLib = require('./harness_config.js');

const OUT_REL = 'lib/harness/harness_config.g.dart';

/** Dart-escape a string literal (single-quoted). */
function dartStr(v) {
  return "'" + String(v).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$') + "'";
}

function buildDart() {
  const cfg = cfgLib.load();
  const g = (p) => cfgLib.get(p, cfg);

  // Map: Dart field -> config dot-path. Only build-time constants the in-app surfaces hardcode today.
  const fields = [
    ['projectName', 'project.name'],
    ['appName', 'app.appName'],
    ['ownerRole', 'project.ownerRole'],
    ['chatRoot', 'collections.chatRoot'],
    ['pokeDoc', 'collections.poke'],
    ['workflowContextDoc', 'collections.workflowContext'],
    ['agentStatusDoc', 'collections.agentStatus'],
    ['visionDoc', 'collections.vision'],
    ['reportsCollection', 'collections.reports'],
    ['pushTitle', 'push.title'],
    ['pushAndroidChannelId', 'push.androidChannelId'],
    ['pushDataRoute', 'push.dataRoute'],
  ];

  const lines = [];
  lines.push('// GENERATED FILE — DO NOT EDIT.');
  lines.push('// Source: harness/project.config.json  ·  Generator: harness/gen_app_config.js');
  lines.push('// Regenerate with: node harness/gen_app_config.js');
  lines.push('//');
  lines.push('// Holds the in-app build-time harness identity (collection/doc names, owner-role, push');
  lines.push('// presentation). For this project the values equal the prior hardcoded literals, so app');
  lines.push('// behavior is unchanged; a different project.config.json yields a different app identity.');
  lines.push('// ignore_for_file: type=lint');
  lines.push('');
  lines.push('/// Compile-time harness configuration generated from project.config.json.');
  lines.push('class HarnessConfig {');
  lines.push('  const HarnessConfig._();');
  lines.push('');
  for (const [field, p] of fields) {
    lines.push(`  /// project.config.json: ${p}`);
    lines.push(`  static const String ${field} = ${dartStr(g(p))};`);
  }
  lines.push('}');
  lines.push('');
  return lines.join('\n');
}

function outPath() {
  const repoRoot = cfgLib.get('paths.repoRoot');
  // Prefer the actual repo containing this generator (robust if repoRoot path differs per machine).
  const localRoot = path.resolve(__dirname, '..');
  const base = fs.existsSync(path.join(localRoot, 'lib')) ? localRoot : repoRoot;
  return path.join(base, OUT_REL);
}

function printHelp() {
  process.stdout.write(
    [
      'gen_app_config.js — generate lib/harness/harness_config.g.dart from project.config.json',
      '',
      'usage:',
      '  node gen_app_config.js            write the generated Dart file',
      '  node gen_app_config.js --check    non-zero if on-disk file is stale vs config',
      '  node gen_app_config.js --stdout   print generated Dart (no write)',
      '  node gen_app_config.js --help',
      '',
    ].join('\n')
  );
}

if (require.main === module) {
  const args = process.argv.slice(2);
  try {
    if (args.includes('--help')) {
      printHelp();
      process.exit(0);
    }
    const dart = buildDart();
    if (args.includes('--stdout')) {
      process.stdout.write(dart);
      process.exit(0);
    }
    const out = outPath();
    if (args.includes('--check')) {
      const cur = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : '';
      if (cur === dart) {
        process.stdout.write(`GEN-APP-CONFIG RESULT: PASS | ${OUT_REL} up to date\n`);
        process.exit(0);
      }
      process.stdout.write(`GEN-APP-CONFIG RESULT: FAIL | ${OUT_REL} is STALE — run: node harness/gen_app_config.js | class=stale-generated retryable=no\n`);
      process.exit(1);
    }
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, dart);
    process.stdout.write(`GEN-APP-CONFIG RESULT: PASS | wrote ${path.relative(path.resolve(__dirname, '..'), out)}\n`);
    process.exit(0);
  } catch (e) {
    process.stderr.write((e && e.message ? e.message : String(e)) + '\n');
    process.stderr.write('GEN-APP-CONFIG RESULT: FAIL | class=generator retryable=no\n');
    process.exit(1);
  }
}

module.exports = { buildDart, outPath };
