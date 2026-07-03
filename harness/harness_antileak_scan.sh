#!/usr/bin/env bash
# harness_antileak_scan.sh — SEPARATION GATE for the Stock-Track harness instance.
#
# Mechanical PROOF that this project's ported owner/operator harness carries ZERO foreign
# (reference-app) backend identity. It greps the harness tooling + orchestrator scripts +
# in-app dev/harness surfaces and FAILS on any identifier that does not belong to THIS
# project's own configured identity.
#
# TWO layers — net protection is a strict SUPERSET of the old blocklist-only scan:
#   1. CONFIG-DRIVEN ALLOWLIST (primary, generalized). Reads the ALLOWED project identity
#      from harness/project.config.json (firebase.projectId + firebase.storageBucket) and
#      FLAGS any Firebase/GCP identity-shaped token — a project bucket/domain or a Firebase
#      App-ID — whose slug is NOT the configured project. This generalizes to ANY foreign
#      project with no edits: a new owner just points project.config.json at their project
#      and the gate blocks every other project's identity automatically.
#   2. REFERENCE-LITERAL BLOCKLIST (retained, defense-in-depth). The explicit known
#      reference-app literals (owner UIDs, repo paths, package prefix) that an allowlist
#      cannot safely SHAPE-detect without false positives. Retained as a backstop so the
#      guard is never WEAKER than the prior blocklist-only version.
#
# Usage:
#   bash harness/harness_antileak_scan.sh          scan the default framework file set
#   bash harness/harness_antileak_scan.sh --list   print the file set it would scan
#   bash harness/harness_antileak_scan.sh --help
#
# Output (agent-first contract): one `ANTILEAK RESULT: PASS|FAIL` line; non-zero exit on
# FAIL; on FAIL a `file:line: [label]` list + `class=leaked-foreign-identity retryable=no`.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
cd "$REPO_ROOT" || { echo "ANTILEAK RESULT: FAIL | cannot cd repo root | class=internal retryable=no"; exit 2; }
CONFIG="harness/project.config.json"

# ---- config-driven ALLOWED identity ----------------------------------------------------
# The set of project slugs that ARE this project (project id + storage-bucket slug). Any
# Firebase/GCP identity-shaped token whose slug is not in this set is a FOREIGN leak.
read_allowed_slugs() {
  local out=""
  if command -v node >/dev/null 2>&1; then
    out="$(node -e '
      try {
        const c = require("./harness/harness_config.js");
        const cfg = c.load();
        const s = new Set();
        try { const p = c.get("firebase.projectId", cfg); if (p) s.add(String(p).toLowerCase()); } catch (e) {}
        try { const b = c.get("firebase.storageBucket", cfg); if (b) s.add(String(b).split(".")[0].toLowerCase()); } catch (e) {}
        process.stdout.write([...s].join("\n"));
      } catch (e) { process.exit(9); }
    ' 2>/dev/null)"
  fi
  if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
  # Fallback (no node / read failure): parse the two literal fields directly.
  grep -oE '"projectId"[[:space:]]*:[[:space:]]*"[^"]+"' "$CONFIG" 2>/dev/null \
    | sed -E 's/.*"([^"]+)"$/\1/' | tr 'A-Z' 'a-z'
  grep -oE '"storageBucket"[[:space:]]*:[[:space:]]*"[^"]+"' "$CONFIG" 2>/dev/null \
    | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/' | cut -d. -f1 | tr 'A-Z' 'a-z'
}

# Firebase/GCP project-scoped identity shapes (case-insensitive):
#   <slug>.firebasestorage.app | <slug>.appspot.com | <slug>.firebaseio.com
#   <slug>.firebaseapp.com | <slug>.web.app   → slug compared to the allowed set
#   1:<projectNumber>:(android|ios|web):<hex>  → a Firebase App-ID (no allowed App-ID
#                                                literal belongs in framework files)
DOMAIN_RX='[a-z0-9][a-z0-9-]{2,}\.(firebasestorage\.app|appspot\.com|firebaseio\.com|firebaseapp\.com|web\.app)'
APPID_RX='1:[0-9]{5,}:(android|ios|web):[0-9a-fA-F]+'

# ---- retained REFERENCE-LITERAL blocklist (defense-in-depth): "LABEL::EXTENDED_REGEX" ----
# Shapes an allowlist cannot safely detect (bare owner UIDs, repo paths, package prefix).
PATTERNS=(
  "ref-firebase-project::blueprintfitnesssubscriptions"
  "ref-owner-uid::9kc4UuTkrJO9VJ7Pjut9yx528kj1"
  "ref-owner-uid-legacy::1772935920220"
  "ref-owner-uid-legacy::TeoQTj5ownPsguKG5djqbHqBMOr1"
  "ref-appdist-app-id::1:677287134512"
  "ref-project-number::677287134512"
  "ref-android-package::io\\.bcd\\.blueprint"
  "ref-android-package::io\\.bcd"
  "ref-package-import::package:blueprint_fitness"
  "ref-clean-room::bpcut"
  "ref-repo-root::/mnt/c/dev/blueprint-fitness-app"
  "ref-repo-root-win::C:[/\\]+dev[/\\]+blueprint-fitness-app"
  "ref-logs-dir::C:[/\\]+Users[/\\]+dev[/\\]+LOGS"
  "ref-push-channel::orchestrator_chat_channel"
  "ref-owner-role::[\"']pete[\"']"
  "ref-project-name::Blueprint Fitness"
  "ref-bucket::blueprintfitnesssubscriptions\\.firebasestorage\\.app"
)

# ---- default framework file set --------------------------------------------------------
default_framework_files() {
  cat <<EOF
harness/harness_config.js
harness/gen_app_config.js
harness/project.config.json
scripts/stocktrack_chat.js
scripts/stocktrack_workflow_status.js
scripts/bp_guard.js
firestore.rules
storage.rules
EOF
  find lib/features/dev lib/harness -name '*.dart' 2>/dev/null || true
}

# never scan these (identity/generated/pattern tables that must name literals to block them)
is_excluded() {
  case "$1" in
    harness/harness_antileak_scan.sh) return 0 ;;  # contains the forbidden patterns by definition
    harness/project.config.schema.json) return 0 ;;
    scripts/bp_guard.js) return 0 ;;               # the abort blocklist — must name ref literals to forbid them
    scripts/stocktrack_ship.sh) return 0 ;;        # ship GUARDRAIL — names ref literals to ABORT if the wrong project is targeted
    *) return 1 ;;
  esac
}

# Skip comment-only lines so a doc-comment mentioning a foreign name for context is not a
# hit (the scan targets live CODE literals, not prose that explains the separation).
COMMENT_FILTER=':[0-9]+:[[:space:]]*(//|#|\*|///|<!--)'

print_help() {
  cat <<'EOF'
harness_antileak_scan.sh — SEPARATION GATE for the Stock-Track harness instance.

FAILS on any backend identifier that is not THIS project's configured identity.
  Layer 1 (config-driven allowlist): allowed project id/bucket come from
    harness/project.config.json; any foreign Firebase/GCP bucket/domain or App-ID FAILS.
  Layer 2 (retained blocklist): explicit known reference-app literals still FAIL.

usage:
  bash harness/harness_antileak_scan.sh          scan the default framework file set
  bash harness/harness_antileak_scan.sh --list   print the file set it would scan
  bash harness/harness_antileak_scan.sh --help

output: one `ANTILEAK RESULT: PASS|FAIL` line; non-zero exit on FAIL.
EOF
}

MODE="scan"
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --list) MODE="list" ;;
    *) echo "ANTILEAK RESULT: FAIL | unknown arg '$1' | class=usage retryable=no"; exit 2 ;;
  esac
  shift
done

mapfile -t RAW_FILES < <(default_framework_files)
FILES=()
for f in "${RAW_FILES[@]}"; do
  [ -z "$f" ] && continue
  is_excluded "$f" && continue
  [ -f "$f" ] || continue
  FILES+=("$f")
done

if [ "$MODE" = "list" ]; then
  if [ "${#FILES[@]}" -eq 0 ]; then echo "ANTILEAK: (no framework files found)"; exit 0; fi
  printf '%s\n' "${FILES[@]}"
  echo "ANTILEAK: ${#FILES[@]} Stock-Track framework files in scope"
  exit 0
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "ANTILEAK RESULT: FAIL | 0 framework files found to scan (bad path?) | class=internal retryable=no"
  exit 2
fi

mapfile -t ALLOWED < <(read_allowed_slugs | sed '/^[[:space:]]*$/d')
if [ "${#ALLOWED[@]}" -eq 0 ]; then
  echo "ANTILEAK RESULT: FAIL | could not derive allowed project identity from $CONFIG | class=config retryable=no"
  exit 2
fi

HITS=0
HITLIST=""

# ---- Layer 1a — config-driven: foreign Firebase/GCP project buckets/domains -------------
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if printf '%s' "$line" | grep -qE "$COMMENT_FILTER"; then continue; fi
  while IFS= read -r token; do
    [ -z "$token" ] && continue
    slug="$(printf '%s' "$token" | cut -d. -f1 | tr 'A-Z' 'a-z')"
    ok=0
    for a in "${ALLOWED[@]}"; do [ "$slug" = "$a" ] && { ok=1; break; }; done
    if [ "$ok" -eq 0 ]; then
      HITS=$((HITS+1))
      HITLIST+="${line}  [foreign-firebase-identity: ${token}]"$'\n'
    fi
  done < <(printf '%s' "$line" | grep -ioE "$DOMAIN_RX")
done < <(grep -inHE "$DOMAIN_RX" "${FILES[@]}" 2>/dev/null)

# ---- Layer 1b — config-driven: foreign Firebase App-ID shapes ---------------------------
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if printf '%s' "$line" | grep -qE "$COMMENT_FILTER"; then continue; fi
  HITS=$((HITS+1))
  HITLIST+="${line}  [foreign-firebase-app-id]"$'\n'
done < <(grep -inHE "$APPID_RX" "${FILES[@]}" 2>/dev/null)

# ---- Layer 2 — retained reference-literal blocklist (defense-in-depth) ------------------
for entry in "${PATTERNS[@]}"; do
  label="${entry%%::*}"
  rx="${entry#*::}"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if printf '%s' "$line" | grep -qE "$COMMENT_FILTER"; then continue; fi
    HITS=$((HITS+1))
    HITLIST+="${line}  [${label}]"$'\n'
  done < <(grep -nE "$rx" "${FILES[@]}" 2>/dev/null)
done

echo "----------------------------------------------------------------------"
if [ "$HITS" -eq 0 ]; then
  echo "ANTILEAK RESULT: PASS | 0 foreign identifiers in the Stock-Track harness | ${#FILES[@]} files scanned | allowed=[${ALLOWED[*]}]"
  exit 0
else
  printf '%s' "$HITLIST"
  echo "----------------------------------------------------------------------"
  echo "ANTILEAK RESULT: FAIL | $HITS foreign identifier(s) leaked into ${#FILES[@]} Stock-Track framework files | class=leaked-foreign-identity retryable=no"
  echo "  -> replace each with a value read from harness/project.config.json (allowed project: [${ALLOWED[*]}])"
  exit 1
fi
