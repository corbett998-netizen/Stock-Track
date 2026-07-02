# 07 — Security / Anti-Leak Audit (Brandon Handoff)

**Purpose.** Verify the Stock-Track handoff package + repo are safe to hand to a second developer
(Brandon). This is defensive correctness / data-scoping work — findings are framed neutrally as
*separation* and *data hygiene*, not incident drama. No secret VALUES appear in this document
(shared repo → patterns only).

**Audit run:** 2026-07-02 · repo `/mnt/c/dev/Brandons_App` · read-only checks only (no commit, no
build). **Scope caveat:** the other numbered handoff docs are written by parallel lanes and were
still being written during this audit. Only the docs that existed at scan time were scanned (see
Check 5). **The orchestrator MUST re-run the anti-leak scan + this audit's Check 5 after all
handoff docs land, before shipping.**

Legend: **FACT** = verified from command output · **RISK** = uncertain / could break ·
**OWNER-DECISION** = needs Pete/Brandon's call.

---

## RESULTS AT A GLANCE

| # | Check | Result |
|---|-------|--------|
| 1 | Anti-leak scan (`harness_antileak_scan.sh`) | **PASS** |
| 2 | Secret sweep (working tree + git history + `.gitignore`) | **PASS** |
| 3 | Committed client-config identity = Brandon's project | **PASS** |
| 4 | No-key / ADC authentication model | **PASS** |
| 5 | New handoff docs (`docs/brandon_handoff/**`) clean | **PASS (partial — re-run before ship)** |

**SAFE-TO-HAND-OVER: YES** — from a secrets / credentials / reference-app-config standpoint, with
two follow-ups: one OWNER-DECISION (internal `docs/working/` planning notes reference the
reference-app owner's UID) and one mechanical gate (orchestrator re-runs the scan after all parallel
handoff docs land). Neither is a security defect. See the gate section at the end.

---

## Check 1 — Anti-leak scan · **PASS**

**Command:** `bash harness/harness_antileak_scan.sh`

**FACT — result:**
```
ANTILEAK RESULT: PASS | 0 reference-app literals in the Stock-Track harness | 55 files scanned
(exit code 0)
```

**FACT — coverage (`--list`, 55 files):**
- `harness/harness_config.js`, `harness/gen_app_config.js`, `harness/project.config.json`
- `scripts/stocktrack_chat.js`, `scripts/stocktrack_workflow_status.js`
- `firestore.rules`, `storage.rules`
- 48 Dart files under `lib/features/dev/**` + `lib/harness/**` (the in-app harness surfaces).

**FACT — excluded by design (must name reference-app literals to *block* them, so excluding them is
correct):** `harness/harness_antileak_scan.sh` (holds the forbidden-pattern table),
`harness/project.config.schema.json`, `scripts/bp_guard.js` (the abort blocklist),
`scripts/stocktrack_ship.sh` (ship guardrail). The scan also skips comment-only lines so a
doc-comment explaining the separation is not a false hit.

**RISK — coverage gap: `docs/` is OUT of scope.** The scan covers harness code, orchestrator
scripts, rules, and in-app dev surfaces — it does **not** scan `docs/**`. Documentation is where the
reference-app identifiers legitimately appear (guard blocklists, separation notes) *and* where the
one data-hygiene item lives (Check 3 note + gate). The scan being code-focused is reasonable, but the
orchestrator should not read "ANTILEAK PASS" as "docs are clean too" — docs are covered manually in
Checks 3 and 5.

**Fix if failed:** n/a (passed). If it ever fails, the tool prints `file:line [pattern]` and
`class=leaked-bp-literal`; replace each hit with a value read from `harness/project.config.json`.

---

## Check 2 — Secret sweep · **PASS**

No private keys, service-account JSON, keystores, or tokens in the working tree or git history;
`.gitignore` covers all credential types.

**FACT — working tree:** a `find` for `service-account*.json`, `*serviceAccount*.json`, `*.keystore`,
`*.jks`, `key.properties`, `.env`, `.env.*`, `application_default_credentials.json`,
`.firebaserc.local` (excluding `.git/` and `node_modules/`) returned **zero** files.

**FACT — git history (56 commits):** `git log --all --diff-filter=A --name-only` shows **no**
credential-type filename was ever added in any commit. A private-key marker sweep
(`BEGIN … PRIVATE KEY`, `private_key_id`) across all history found **no** secret values — the single
match is a *grep-pattern string* inside `docs/harness/AUDIT_PLAN.md` (an audit example listing what to
search for), not a credential.

**FACT — secret-shaped-string sweep (tracked tree, excluding the by-design client configs + lock
files):** patterns `AIza…`, `-----BEGIN`, `"private_key"`, `xox[baprs]-`, `ghp_…`, FCM `…:APA91`,
`sk-…` → **zero** hits. The `token` / `password` / `secret` hits that do exist are all *instructional
prose* in the Brandon-facing docs teaching the no-key model (e.g. "no key, token, or password is ever
shared"), not literals.

**FACT — `.gitignore` credential coverage (complete):** `service-account*.json`,
`*serviceAccount*.json`, `.env`, `.env.*`, `key.properties`, `*.keystore`, `*.jks`,
`application_default_credentials.json`, `.firebaserc.local`, `firebase-debug.log`. It explicitly
comments that `google-services.json` / `GoogleService-Info.plist` are **client** configs committed on
purpose (see Check 3), so they are intentionally *not* ignored.

**Fix if failed:** n/a (passed).

---

## Check 3 — Committed client-config identity = Brandon's project · **PASS**

The committed default Android client config points to the SECOND developer's own project — not the
owner's test project, and not the reference app.

**FACT — `android/app/google-services.json` (tracked; identifiers only, no secret value printed):**
- `project_id` = `easy-stock-track`
- `project_number` = `367897871594`
- `storage_bucket` = `easy-stock-track.firebasestorage.app`
- `package_name` = `com.stocktrack.app`

**FACT — `ios/Runner/GoogleService-Info.plist` (tracked):** same project (`easy-stock-track`, project
number `367897871594`, bucket `easy-stock-track.firebasestorage.app`, bundle `com.stocktrack.app`).

**FACT — ownership:** `docs/DECISIONS.md` records that **Brandon created his OWN Firebase project
`easy-stock-track`** and registered `com.stocktrack.app`. This matches
`harness/project.config.json → firebase.projectId = "easy-stock-track"`. So the committed client
config is Brandon's own project, not a separate owner test-project presented as his.

**FACT — the client config is not an admin secret.** `google-services.json` carries a public Firebase
client API key (an identifier restricted by Firebase Security Rules + app registration), not an admin
credential. `docs/brandon_handoff/02_FIREBASE_SETUP.md` states this correctly (the app's
"connection config … meant to ship inside the app", and "not an admin secret"). Committing it is
the intended Firebase pattern.

**FACT — no reference-app project id in any client config.** `<reference-app-project-id>` /
`<reference-app-project-number>` appear in **no** `google-services.json` / plist.

**FACT — where reference-app identifiers *do* appear committed (all by design, not a leak):**
1. `scripts/bp_guard.js` and `harness/harness_antileak_scan.sh` — the abort blocklist / pattern table.
   These *must* name the reference-app literals in order to block them; both are excluded from the
   anti-leak scan for exactly this reason. This is the defense, not a leak.
2. `docs/**` planning + decision notes that describe the separation ("project = easy-stock-track, NOT
   <reference-app-project-id>"). Prose, not live config.

**OWNER-DECISION (data hygiene, neutral — not a security hole):** the reference-app owner's real UID
(`<reference-app-owner-uid>`, legacy `<reference-app-legacy-uid>`) is committed in exactly **two
internal working-plan docs** — `docs/working/JUN30_stocktrack_harness_plan.md` and
`docs/working/JUN30_stocktrack_harness_port_PLAN.md` — always in the context "never use the
reference-app UID, use Brandon's." It appears in **no** Brandon-facing doc (`BRANDON_*`,
`FOR_BRANDON_*`, `docs/handoff/`, `docs/brandon_handoff/`). Because the whole repo ships to Brandon,
these internal notes carry the reference-app owner's UID into Brandon's copy. This is **not** a
security defect — the UID is an anonymous-auth per-install identifier (not a credential), and
`firestore.rules` (Check 4) default-denies cross-user reads, so possessing the string grants no
access. It is owner-private data that Brandon does not need. **Decision for Pete:** either (a) include
`docs/working/` planning notes in Brandon's package as-is, or (b) prune `docs/working/` (and internal
`docs/harness/` audit plans) from Brandon's handoff copy. Recommend (b) — Brandon's package is
`docs/brandon_handoff/**` + the `FOR_BRANDON_*` / `BRANDON_*` guides; the internal planning archive
adds no value for him and carries the reference-app owner's UID.

**Fix if failed:** n/a (passed). If a client config ever pointed at the wrong project, replace it with
Brandon's downloaded `google-services.json` and re-run this check + Check 1.

---

## Check 4 — No-key / ADC authentication model · **PASS**

The repo commits **no** credentials; the orchestrator scripts authenticate via Application Default
Credentials (ADC).

**FACT — both orchestrator scripts init the Admin SDK with ADC and pin the project explicitly:**
`scripts/stocktrack_chat.js` and `scripts/stocktrack_workflow_status.js` call
```
admin.initializeApp({
  credential: admin.credential.applicationDefault(),   // ADC — gcloud application-default
  projectId: PROJECT_ID,                                // pinned to easy-stock-track
  storageBucket: STORAGE_BUCKET,
});
```
and run `assertNoBpLeak()` **before** init (the `bp_guard.js` abort). Pinning `projectId` means an
ambient default identity can never redirect a write to another project.

**FACT — no service-account file is read at runtime.** No script contains `readFileSync`/`require` of
a service-account JSON. When ADC is absent both scripts emit a clean
`… RESULT: BLOCKED | no Application Default Credentials — run 'gcloud auth application-default login' …
class=adc-missing retryable=yes` and point to `docs/FOR_BRANDON_harness_backend.md` (now a
supersede pointer to the canonical `docs/brandon_handoff/02_FIREBASE_SETUP.md`, Part G).

**FACT (minor, correctness note — no security impact):** `harness/project.config.json` declares
`firebase.serviceAccountPath = ${paths.repoRoot}/service-account.json`, and `harness_config.js`
*validates* that this field equals that path. But the path is **declared-only** — nothing reads it at
runtime (ADC is the sole auth path), the file does not exist, and `service-account*.json` is
gitignored. It is a vestigial config field. **Fix (optional, low priority):** drop or clearly comment
`firebase.serviceAccountPath` as "not used — ADC only" so a future reader doesn't try to populate it.

**Fix if failed:** n/a (passed).

---

## Check 5 — New handoff docs scan · **PASS (partial — re-run before ship)**

Scan `docs/brandon_handoff/**` for accidental reference-app identifiers, real secrets, or
owner-private data (real UIDs; the owner's test-project id presented as Brandon's).

**FACT — files present at scan time:** `00_START_HERE.md`, `03_ORCHESTRATOR_ZELLIJ_WORKFLOW.md`
(this file, `07_…`, was being written). The remaining numbered docs (`01`, `02`, `04`, `05`, `06`,
…) were **not yet present** — parallel lanes are still authoring them.

**FACT — result on the docs that exist:** a scan for the reference-app identifiers (its project id,
project number, owner UIDs, package prefix, and build-tooling names) plus generic secret shapes
(`AIza…` API keys, `-----BEGIN` private-key headers, `private_key`) returned **zero** hits. No
reference-app identifiers, no real UIDs, no secrets in the handoff docs.

**RISK / mechanical gate:** because parallel lanes were still writing during this pass, the
orchestrator must re-run — before shipping the package to Brandon — both:
1. `bash harness/harness_antileak_scan.sh` (code path), and
2. a doc-scan over the *complete* `docs/brandon_handoff/**` set for the same reference-app
   identifiers + secret shapes. The reference-app blocklist is held in the guard/scanner
   (`harness/harness_antileak_scan.sh`), not restated here, so this doc carries none of those
   literals itself. Expected clean output = zero hits.

**Fix if failed:** if a later handoff doc names a reference-app identifier or a real UID, rewrite that
line to reference Brandon's own project/UID (or remove it); never paste a secret value into a doc.

---

## SAFE-TO-HAND-OVER GATE

**SAFE-TO-HAND-OVER: YES**

**Basis (all FACT):**
- Anti-leak scan PASS — 0 reference-app literals across 55 harness/script/rules/dev-surface files.
- No secrets in the working tree or in 56 commits of history; `.gitignore` covers every credential type.
- Committed client config (`google-services.json` + iOS plist) points to Brandon's own project
  `easy-stock-track` — not the owner's test project, not the reference app.
- No-key model verified: orchestrator authenticates via ADC with `projectId` pinned + a
  reference-app-abort guard; no service-account file is read or committed.
- Handoff docs scanned so far carry no reference-app ids, real UIDs, or secrets.

**Conditions attached to the YES (neither is a security defect):**
1. **OWNER-DECISION** — decide whether internal `docs/working/` (and `docs/harness/`) planning notes,
   which reference the reference-app owner's UID, ship in Brandon's package or are pruned. Recommend
   pruning to `docs/brandon_handoff/**` + `FOR_BRANDON_*` / `BRANDON_*` for Brandon's copy. (Not a
   credential; anonymous-auth UID; read-scoped by default-deny rules — pure data hygiene.)
2. **MECHANICAL GATE** — the orchestrator re-runs `harness_antileak_scan.sh` + the Check-5 doc-scan
   over the *complete* handoff-doc set once all parallel lanes finish, immediately before shipping.

**Optional polish (low priority):** annotate/remove the unused `firebase.serviceAccountPath` config
field (Check 4) to keep the "ADC only, no committed key" story unambiguous.
