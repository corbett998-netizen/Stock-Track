#!/usr/bin/env node
/**
 * harness_config.js — Node loader for the per-project harness config (project.config.json).
 *
 * Generalized-harness substrate (Stage A). Framework scripts read project IDENTITY from here
 * instead of hardcoding Blueprint-Fitness literals. Pure: no Firestore, no network.
 *
 * API (require('./harness_config.js')):
 *   load(configPath?)        -> resolved config object (all ${a.b} interpolated)
 *   get(path, configObj?)    -> value at dot-path (e.g. get('owner.uid')); throws if missing
 *   tryGet(path, dflt)       -> value or default (no throw)
 *   assertRequired([paths])  -> throws loud (non-zero on CLI) if any required key is absent
 *   configPath()             -> absolute path to the resolved project.config.json
 *
 * CLI:
 *   node harness_config.js --get <dot.path>   print one resolved value
 *   node harness_config.js --dump             print the fully-resolved config JSON
 *   node harness_config.js --selftest         pure-function tests (no Firestore)
 *   node harness_config.js --help
 *
 * Output contract: one `HARNESS-CONFIG RESULT: PASS|FAIL` line; non-zero exit on failure.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULT_CONFIG_NAME = 'project.config.json';

/** Locate project.config.json: explicit arg > env HARNESS_CONFIG > sibling of this file > cwd walk-up. */
function resolveConfigPath(explicit) {
  const candidates = [];
  if (explicit) candidates.push(explicit);
  if (process.env.HARNESS_CONFIG) candidates.push(process.env.HARNESS_CONFIG);
  candidates.push(path.join(__dirname, DEFAULT_CONFIG_NAME));
  // walk up from cwd looking for harness/project.config.json
  let dir = process.cwd();
  for (let i = 0; i < 8; i++) {
    candidates.push(path.join(dir, 'harness', DEFAULT_CONFIG_NAME));
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  for (const c of candidates) {
    if (c && fs.existsSync(c)) return path.resolve(c);
  }
  throw new Error(
    `HARNESS-CONFIG: cannot locate ${DEFAULT_CONFIG_NAME} (looked in: ${candidates.filter(Boolean).join(', ')})`
  );
}

/** Read raw JSON, stripping metadata keys (_comment, $schema) at the top level. */
function readRaw(configPath) {
  let txt;
  try {
    txt = fs.readFileSync(configPath, 'utf8');
  } catch (e) {
    throw new Error(`HARNESS-CONFIG: cannot read ${configPath}: ${e.message}`);
  }
  let obj;
  try {
    obj = JSON.parse(txt);
  } catch (e) {
    throw new Error(`HARNESS-CONFIG: invalid JSON in ${configPath}: ${e.message}`);
  }
  delete obj.$schema;
  delete obj._comment;
  return obj;
}

/** Resolve a dot-path against an object; returns undefined (no throw) if absent. */
function rawGet(obj, dotPath) {
  return dotPath.split('.').reduce((acc, k) => (acc == null ? undefined : acc[k]), obj);
}

/** Interpolate all ${a.b} references in every string value, iterating until stable. */
function interpolate(root) {
  const MAX_PASSES = 10;
  const re = /\$\{([a-zA-Z0-9_.]+)\}/g;

  function resolveString(str, pass) {
    return str.replace(re, (m, ref) => {
      const v = rawGet(root, ref);
      if (v === undefined) {
        throw new Error(`HARNESS-CONFIG: interpolation reference '\${${ref}}' not found`);
      }
      if (typeof v !== 'string' && typeof v !== 'number' && typeof v !== 'boolean') {
        throw new Error(`HARNESS-CONFIG: interpolation reference '\${${ref}}' is not a scalar`);
      }
      return String(v);
    });
  }

  function walk(node, pass) {
    if (typeof node === 'string') return resolveString(node, pass);
    if (Array.isArray(node)) return node.map((n) => walk(n, pass));
    if (node && typeof node === 'object') {
      const out = {};
      for (const k of Object.keys(node)) out[k] = walk(node[k], pass);
      return out;
    }
    return node;
  }

  let cur = root;
  for (let pass = 0; pass < MAX_PASSES; pass++) {
    const next = walk(cur, pass);
    if (JSON.stringify(next) === JSON.stringify(cur)) return next;
    cur = next;
  }
  // one final check that no unresolved ${...} remain
  const leftover = JSON.stringify(cur).match(re);
  if (leftover) {
    throw new Error(`HARNESS-CONFIG: unresolved interpolation after ${MAX_PASSES} passes: ${leftover.join(', ')}`);
  }
  return cur;
}

let _cache = null;
let _cachePath = null;

/** Load + resolve the config (cached per path). */
function load(explicitPath) {
  const cp = resolveConfigPath(explicitPath);
  if (_cache && _cachePath === cp) return _cache;
  const raw = readRaw(cp);
  const resolved = interpolate(raw);
  _cache = resolved;
  _cachePath = cp;
  return resolved;
}

/** get('a.b.c') -> value; throws if absent. */
function get(dotPath, configObj) {
  const cfg = configObj || load();
  const v = rawGet(cfg, dotPath);
  if (v === undefined) {
    throw new Error(`HARNESS-CONFIG: required key '${dotPath}' is missing from project.config.json`);
  }
  return v;
}

/** tryGet('a.b', default) -> value or default; never throws on absence. */
function tryGet(dotPath, dflt, configObj) {
  const cfg = configObj || load();
  const v = rawGet(cfg, dotPath);
  return v === undefined ? dflt : v;
}

/** assertRequired(['owner.uid','firebase.projectId',...]) -> throws listing every missing key. */
function assertRequired(paths, configObj) {
  const cfg = configObj || load();
  const missing = paths.filter((p) => rawGet(cfg, p) === undefined);
  if (missing.length) {
    throw new Error(`HARNESS-CONFIG: missing required keys: ${missing.join(', ')}`);
  }
  return true;
}

function configPath(explicitPath) {
  return resolveConfigPath(explicitPath);
}

/** shell-escape a value for single-quoted bash assignment. */
function shEsc(v) {
  return "'" + String(v).replace(/'/g, "'\\''") + "'";
}

/** Emit `export HARNESS_<UPPER_DOTPATH>=...` lines for every scalar leaf (arrays joined by space). */
function emitShExports(configObj) {
  const cfg = configObj || load();
  const lines = [];
  const keyOf = (p) => 'HARNESS_' + p.toUpperCase().replace(/[.]/g, '_').replace(/[^A-Z0-9_]/g, '_');
  function walk(node, prefix) {
    if (node === null || node === undefined) return;
    if (Array.isArray(node)) {
      if (node.every((x) => typeof x !== 'object' || x === null)) {
        lines.push(`export ${keyOf(prefix)}=${shEsc(node.join(' '))}`);
      }
      return;
    }
    if (typeof node === 'object') {
      for (const k of Object.keys(node)) walk(node[k], prefix ? `${prefix}.${k}` : k);
      return;
    }
    lines.push(`export ${keyOf(prefix)}=${shEsc(node)}`);
  }
  walk(cfg, '');
  return lines.join('\n') + '\n';
}

module.exports = { load, get, tryGet, assertRequired, configPath, emitShExports };

// ----------------------------------------------------------------------------
// CLI
// ----------------------------------------------------------------------------
function printHelp() {
  process.stdout.write(
    [
      'harness_config.js — per-project harness config loader (pure; no Firestore)',
      '',
      'usage:',
      '  node harness_config.js --get <dot.path>   print one resolved value',
      '  node harness_config.js --dump             print fully-resolved config JSON',
      '  node harness_config.js --selftest         pure-function tests',
      '  node harness_config.js --help',
      '',
    ].join('\n')
  );
}

function runSelftest() {
  const cases = [];
  const ok = (name, cond) => cases.push({ name, pass: !!cond });
  const throws = (name, fn) => {
    let threw = false;
    try { fn(); } catch (_) { threw = true; }
    cases.push({ name, pass: threw });
  };

  // Generic, project-agnostic tests: assert loader MECHANICS (interpolation, accessors, asserts)
  // derived from whatever config is present — never hardcode this project's identity values
  // (so this loader stays free of any project-specific literal: the anti-leak invariant).
  const cfg = load(path.join(__dirname, DEFAULT_CONFIG_NAME));

  // structural keys exist + are non-empty strings
  ok('project.name is a non-empty string', typeof get('project.name', cfg) === 'string' && get('project.name', cfg).length > 0);
  ok('project.ownerRole is a non-empty string', typeof get('project.ownerRole', cfg) === 'string' && get('project.ownerRole', cfg).length > 0);
  ok('owner.uid is a non-empty string', typeof get('owner.uid', cfg) === 'string' && get('owner.uid', cfg).length > 0);
  ok('firebase.projectId is a non-empty string', typeof get('firebase.projectId', cfg) === 'string' && get('firebase.projectId', cfg).length > 0);

  // interpolation MECHANICS — values derive from other config keys (no hardcoded expectation)
  ok('serviceAccountPath = ${paths.repoRoot}/service-account.json',
     get('firebase.serviceAccountPath', cfg) === get('paths.repoRoot', cfg) + '/service-account.json');
  ok('owner.fcmTokenPath = ${push.tokenCollection}/${owner.uid}/${push.tokenField}',
     get('owner.fcmTokenPath', cfg) === get('push.tokenCollection', cfg) + '/' + get('owner.uid', cfg) + '/' + get('push.tokenField', cfg));
  ok('storage.chatMedia = ${collections.chatRoot}/${owner.uid}/media',
     get('storage.chatMedia', cfg) === get('collections.chatRoot', cfg) + '/' + get('owner.uid', cfg) + '/media');
  ok('storage.localMediaDir = ${paths.logsDir}/chat_media',
     get('storage.localMediaDir', cfg) === get('paths.logsDir', cfg) + '/chat_media');
  ok('no leftover ${ in resolved config', JSON.stringify(cfg).indexOf('${') === -1);

  // accessors
  ok('collections.poke is a non-empty string', typeof get('collections.poke', cfg) === 'string' && get('collections.poke', cfg).length > 0);
  ok('lanes.names is a non-empty array',
     Array.isArray(get('lanes.names', cfg)) && get('lanes.names', cfg).length > 0);
  ok('distribution.testerGroup is a non-empty string', typeof get('distribution.testerGroup', cfg) === 'string' && get('distribution.testerGroup', cfg).length > 0);
  ok('fileSizeGuard.hardStop is numeric', typeof get('fileSizeGuard.hardStop', cfg) === 'number');

  // tryGet + assertRequired
  ok('tryGet present returns the value', tryGet('project.slug', '__DFLT__', cfg) === get('project.slug', cfg));
  ok('tryGet absent returns the default', tryGet('nope.not.here', '__DFLT__', cfg) === '__DFLT__');
  ok('assertRequired all present',
     assertRequired(['owner.uid', 'firebase.projectId', 'collections.chatRoot'], cfg) === true);

  // throwing paths
  throws('get missing throws', () => get('does.not.exist', cfg));
  throws('assertRequired missing throws', () => assertRequired(['owner.uid', 'totally.absent'], cfg));

  const passed = cases.filter((c) => c.pass).length;
  const total = cases.length;
  for (const c of cases) process.stdout.write(`${c.pass ? 'PASS' : 'FAIL'}  ${c.name}\n`);
  process.stdout.write('\n');
  if (passed === total) {
    process.stdout.write(`HARNESS-CONFIG RESULT: PASS | selftest ${passed}/${total}\n`);
    process.exit(0);
  } else {
    process.stdout.write(`HARNESS-CONFIG RESULT: FAIL | selftest ${passed}/${total} | class=config-loader retryable=no\n`);
    process.exit(1);
  }
}

if (require.main === module) {
  const args = process.argv.slice(2);
  try {
    if (args.includes('--help') || args.length === 0) {
      printHelp();
      process.exit(0);
    } else if (args.includes('--selftest')) {
      runSelftest();
    } else if (args.includes('--get')) {
      const p = args[args.indexOf('--get') + 1];
      if (!p) { process.stderr.write('HARNESS-CONFIG RESULT: FAIL | --get needs a dot.path\n'); process.exit(2); }
      process.stdout.write(String(get(p)) + '\n');
    } else if (args.includes('--dump')) {
      process.stdout.write(JSON.stringify(load(), null, 2) + '\n');
    } else if (args.includes('--export-sh')) {
      process.stdout.write(emitShExports());
    } else {
      printHelp();
      process.exit(2);
    }
  } catch (e) {
    process.stderr.write((e && e.message ? e.message : String(e)) + '\n');
    process.stderr.write('HARNESS-CONFIG RESULT: FAIL | class=config-loader retryable=no\n');
    process.exit(1);
  }
}
