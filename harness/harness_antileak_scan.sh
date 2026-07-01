#!/usr/bin/env bash
# harness_antileak_scan.sh — SEPARATION GATE for the Stock-Track harness instance.
#
# This is the mechanical PROOF that Stock-Track's ported owner/operator harness carries
# ZERO Blueprint-Fitness identity. It greps Stock-Track's harness tooling + orchestrator
# scripts + in-app dev/harness surfaces for any Blueprint literal (project id, owner UID,
# app id, bucket, clean-room, BP push channel, "Blueprint Fitness"). ANY hit = FAIL:
# a BP identifier in the Stock-Track port means the copy dragged Blueprint across and it
# must be replaced with a value read from harness/project.config.json (easy-stock-track).
#
# Mirror of Blueprint's own harness_antileak_scan.sh, but with the TARGET inverted:
# BP scans ITS tree for leaked generic literals; Stock-Track scans ITS tree for leaked
# BLUEPRINT literals. Same discipline — separation is CHECKED BY A TOOL, not asserted.
#
# Usage:
#   bash harness/harness_antileak_scan.sh          scan the default Stock-Track file set
#   bash harness/harness_antileak_scan.sh --list   print the file set it would scan
#   bash harness/harness_antileak_scan.sh --help
#
# Output (agent-first contract): one `ANTILEAK RESULT: PASS|FAIL` line; non-zero exit on
# FAIL; on FAIL a `file:line: [pattern]` list + `class=leaked-bp-literal retryable=no`.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
cd "$REPO_ROOT" || { echo "ANTILEAK RESULT: FAIL | cannot cd repo root | class=internal retryable=no"; exit 2; }

# ---- forbidden BLUEPRINT patterns: "LABEL::EXTENDED_REGEX" -----------------------------
PATTERNS=(
  "bp-firebase-project::blueprintfitnesssubscriptions"
  "bp-owner-uid::9kc4UuTkrJO9VJ7Pjut9yx528kj1"
  "bp-owner-uid-legacy::1772935920220"
  "bp-owner-uid-legacy::TeoQTj5ownPsguKG5djqbHqBMOr1"
  "bp-appdist-app-id::1:677287134512"
  "bp-project-number::677287134512"
  "bp-android-package::io\\.bcd\\.blueprint"
  "bp-android-package::io\\.bcd"
  "bp-package-import::package:blueprint_fitness"
  "bp-clean-room::bpcut"
  "bp-repo-root::/mnt/c/dev/blueprint-fitness-app"
  "bp-repo-root-win::C:[/\\]+dev[/\\]+blueprint-fitness-app"
  "bp-logs-dir::C:[/\\]+Users[/\\]+dev[/\\]+LOGS"
  "bp-push-channel::orchestrator_chat_channel"
  "bp-owner-role::[\"']pete[\"']"
  "bp-project-name::Blueprint Fitness"
  "bp-bucket::blueprintfitnesssubscriptions\\.firebasestorage\\.app"
)

# ---- default Stock-Track framework file set --------------------------------------------
default_framework_files() {
  cat <<EOF
harness/harness_config.js
harness/gen_app_config.js
harness/project.config.json
scripts/stocktrack_chat.js
scripts/bp_guard.js
firestore.rules
storage.rules
EOF
  find lib/features/dev lib/harness -name '*.dart' 2>/dev/null || true
}

# never scan these (identity/generated/pattern tables that must name BP literals to block them)
is_excluded() {
  case "$1" in
    harness/harness_antileak_scan.sh) return 0 ;;  # contains the forbidden patterns by definition
    harness/project.config.schema.json) return 0 ;;
    scripts/bp_guard.js) return 0 ;;               # the BP-abort blocklist — must name BP literals to forbid them
    *) return 1 ;;
  esac
}

# Skip comment-only lines so a doc-comment mentioning "Blueprint" for context is not a hit
# (the scan targets live CODE literals, not prose that explains the separation).
COMMENT_FILTER=':[0-9]+:[[:space:]]*(//|#|\*|///|<!--)'

print_help() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

HITS=0
HITLIST=""
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
  echo "ANTILEAK RESULT: PASS | 0 Blueprint literals in the Stock-Track harness | ${#FILES[@]} files scanned"
  exit 0
else
  printf '%s' "$HITLIST"
  echo "----------------------------------------------------------------------"
  echo "ANTILEAK RESULT: FAIL | $HITS Blueprint literals leaked into ${#FILES[@]} Stock-Track framework files | class=leaked-bp-literal retryable=no"
  echo "  -> replace each with a value read from harness/project.config.json (easy-stock-track)"
  exit 1
fi
