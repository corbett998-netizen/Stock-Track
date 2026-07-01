#!/usr/bin/env bash
# =============================================================================
# stocktrack_ship.sh — Stock-Track's OWN build -> Firebase App Distribution ship.
#
# Pinned HARD to Brandon's project (easy-stock-track) + Brandon's Android app id
# + the stocktrack-testers group. Reuses the Blueprint Fitness ship PATTERN only
# (clean build -> monotonic versionCode -> distribute -> one PASS/FAIL line).
# It copies ZERO Blueprint Fitness config: never BP's project, app id, token, or
# tester group. A defensive guard aborts if any BP identifier is ever seen here.
#
# Agent-first output contract: one final RESULT line
#   STOCKTRACK SHIP RESULT: PASS 1.0(N) | <MB>MB | uploaded NEW
#   STOCKTRACK SHIP RESULT: FAIL   | class=<...> | <reason>
#   STOCKTRACK SHIP RESULT: BLOCKED | class=<...> | <what Brandon must do>
#
# WHY powershell.exe for firebase: the WSL `firebase` binary HANGS in this
# environment (interop shim, exit 124). The Windows firebase CLI works, so all
# firebase calls go through powershell.exe. `flutter build` runs fine in WSL.
# =============================================================================
set -uo pipefail

# ---- PINNED IDENTITY (Brandon's own — never Blueprint Fitness) ---------------
PROJECT_ID="easy-stock-track"
APP_ID="1:367897871594:android:08253408e00517c6548393"   # Brandon's Android app id
TESTER_GROUP="stocktrack-testers"
REPO_DIR="/mnt/c/dev/Brandons_App"
REPO_DIR_WIN='C:\dev\Brandons_App'

BUILD_MODE="debug"   # --release once a Stock-Track keystore is wired
VERBOSE=0

usage() {
  cat <<EOF
stocktrack_ship.sh — ship a Stock-Track APK to Firebase App Distribution.

USAGE:
  ./scripts/stocktrack_ship.sh [--release|--debug] [--verbose] [--help]

WHAT IT DOES (in order):
  1. Guardrail: refuse to run if any Blueprint Fitness identifier is present.
  2. Preflight: confirm the authed firebase account can reach '${PROJECT_ID}'.
  3. Build:     flutter build apk (--${BUILD_MODE}) in the Stock-Track repo.
  4. Version:   bump Stock-Track's OWN monotonic versionCode (its own counter).
  5. Distribute: firebase appdistribution:distribute --app ${APP_ID}
                 --project ${PROJECT_ID} --groups ${TESTER_GROUP}
  6. Emit ONE 'STOCKTRACK SHIP RESULT:' line (PASS | FAIL | BLOCKED).

PINNED (never Blueprint Fitness):
  project   = ${PROJECT_ID}
  app id    = ${APP_ID}
  group     = ${TESTER_GROUP}

REQUIRES (Brandon, one-time — see docs/STOCKTRACK_SHIP_RUNBOOK.md):
  - App Distribution ENABLED in the ${PROJECT_ID} Firebase console.
  - A '${TESTER_GROUP}' tester group created (Pete + Brandon added).
  - The uploading account granted access to ${PROJECT_ID} (Brandon's own auth,
    OR Brandon grants Pete's firebase account the App Distribution Admin role).
EOF
}

emit() { echo "STOCKTRACK SHIP RESULT: $1"; }

for arg in "$@"; do
  case "$arg" in
    --release) BUILD_MODE="release" ;;
    --debug)   BUILD_MODE="debug" ;;
    --verbose) VERBOSE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) emit "FAIL   | class=usage | unknown arg '$arg' (see --help)"; exit 2 ;;
  esac
done

cd "$REPO_DIR" || { emit "FAIL   | class=env | cannot cd $REPO_DIR"; exit 2; }

# ---- 1. SEPARATION GUARDRAIL (defense in depth) -----------------------------
if echo "$PROJECT_ID $APP_ID $TESTER_GROUP" | grep -qiE 'blueprint|677287134512|io\.bcd'; then
  emit "FAIL   | class=separation | BLUEPRINT identifier in pinned config — ABORT"
  exit 3
fi

# ---- 2. PREFLIGHT: authed account can reach Brandon's project? --------------
# READ-ONLY. If the account can't see ${PROJECT_ID}, the upload is BLOCKED on
# Brandon (his App Distribution enable + tester group + granting upload access).
PROJECTS="$(powershell.exe -NoProfile -Command "firebase projects:list" 2>/dev/null | tr -d '\r')"
if echo "$PROJECTS" | grep -qi "blueprintfitnesssubscriptions" && ! echo "$PROJECTS" | grep -qi "$PROJECT_ID"; then
  emit "BLOCKED | class=auth | authed firebase account cannot see '${PROJECT_ID}' (sees only BP). Brandon must enable App Distribution + create '${TESTER_GROUP}' + grant the uploader access to ${PROJECT_ID}, OR provide his own auth/CI token. See docs/STOCKTRACK_SHIP_RUNBOOK.md."
  exit 10
fi
if ! echo "$PROJECTS" | grep -qi "$PROJECT_ID"; then
  emit "BLOCKED | class=auth | '${PROJECT_ID}' not visible to the authed firebase account — run 'firebase login' as an account with access, or have Brandon grant access. See docs/STOCKTRACK_SHIP_RUNBOOK.md."
  exit 10
fi

# ---- 3. MONOTONIC versionCode (Stock-Track's OWN counter) -------------------
COUNTER_FILE="$REPO_DIR/scripts/.stocktrack_versioncode"
PUBSPEC_VC="$(grep -oE '^version:\s*[0-9.]+\+[0-9]+' pubspec.yaml | grep -oE '\+[0-9]+$' | tr -d '+')"
[ -z "$PUBSPEC_VC" ] && PUBSPEC_VC=1
LAST_VC=0
[ -f "$COUNTER_FILE" ] && LAST_VC="$(cat "$COUNTER_FILE" 2>/dev/null | tr -dc '0-9')"
[ -z "$LAST_VC" ] && LAST_VC=0
# next = max(pubspec, lastCounter) + 1  (never downgrade a tester's phone)
NEXT_VC=$(( (PUBSPEC_VC > LAST_VC ? PUBSPEC_VC : LAST_VC) + 1 ))
VERSION_NAME="$(grep -oE '^version:\s*[0-9.]+' pubspec.yaml | grep -oE '[0-9.]+')"

# ---- 4. RELEASE NOTES from last commit --------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
SHA="$(git rev-parse --short HEAD 2>/dev/null)"
SUBJECT="$(git log -1 --pretty=%s 2>/dev/null)"
NOTES="[${BRANCH} @ ${SHA}] ${SUBJECT}"

# ---- 5. BUILD (WSL flutter is fine) -----------------------------------------
[ "$VERBOSE" = "1" ] && echo "Building ${BUILD_MODE} APK, versionCode ${NEXT_VC} (${VERSION_NAME})..."
BUILD_LOG="$(mktemp)"
if ! flutter build apk --"$BUILD_MODE" --build-number="$NEXT_VC" >"$BUILD_LOG" 2>&1; then
  echo "--- build tail ---"; tail -20 "$BUILD_LOG"
  emit "FAIL   | class=build | flutter build apk --${BUILD_MODE} failed (see log above)"
  exit 4
fi
APK="build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"
if [ ! -f "$APK" ]; then
  emit "FAIL   | class=build | expected APK not found: $APK"
  exit 4
fi
APK_MB="$(du -m "$APK" | cut -f1)"
APK_WIN="${REPO_DIR_WIN}\\build\\app\\outputs\\flutter-apk\\app-${BUILD_MODE}.apk"

# ---- 6. DISTRIBUTE via the Windows firebase CLI (pinned to Brandon) ---------
DIST_LOG="$(mktemp)"
powershell.exe -NoProfile -Command \
  "firebase appdistribution:distribute '${APK_WIN}' --app '${APP_ID}' --project '${PROJECT_ID}' --groups '${TESTER_GROUP}' --release-notes '${NOTES}'" \
  >"$DIST_LOG" 2>&1
DIST_RC=$?
[ "$VERBOSE" = "1" ] && { echo "--- distribute output ---"; cat "$DIST_LOG" | tr -d '\r'; }

if [ "$DIST_RC" -ne 0 ]; then
  REASON="$(grep -iE 'error|permission|not found|denied' "$DIST_LOG" | tr -d '\r' | head -1)"
  emit "BLOCKED | class=upload | appdistribution:distribute failed (rc=${DIST_RC}): ${REASON:-see verbose}. Likely App Distribution not enabled / '${TESTER_GROUP}' missing / no upload access on ${PROJECT_ID}. See docs/STOCKTRACK_SHIP_RUNBOOK.md."
  exit 11
fi

# success — persist the counter so the next ship is monotonic
echo "$NEXT_VC" > "$COUNTER_FILE"
emit "PASS ${VERSION_NAME}(${NEXT_VC}) | ${APK_MB}MB | uploaded NEW"
exit 0
