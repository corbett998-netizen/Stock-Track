# Reusable-Harness Readiness — INDEPENDENT AUDIT PLAN

**Date:** 2026-07-01 · **Status:** planning doc (the audit itself is NOT yet run) ·
**For:** a fresh, independent reviewer with **no prior context** on this work.

> **What this is.** A runnable plan a fresh reviewer executes to decide two things:
> (1) is the Stock-Track owner/operator harness **actually ready** to hand to a second
> developer, and (2) is the app-agnostic product extraction (the "Appharness" planning
> repo, adjacent) **genuinely reusable / app-agnostic**. This is the PLAN — it is not the
> audit, and it changes no code.
>
> **What this is NOT.** Not an implementation task, not a spec, not a green-light. Running
> this plan produces a signed verdict + evidence; nothing here authorizes a handoff.
>
> **Patterns-only.** This doc lives in a shared repo and is written to be publishable: it
> names no secrets and no reference-app private identifiers. Where a reference-app identity
> literal matters, the plan tells the reviewer to run the mechanical scan rather than to
> paste the literal.

---

## 0. Governing doctrine for this audit (read first — it changes how you score)

These are non-negotiable scoring rules. Apply them to every area below.

1. **Evidence over claims. "Done" is not done.** Every prior signoff doc in
   `docs/harness/**` is a **claim to verify**, not a fact. Re-run every gate yourself from a
   clean tree and record the command output. Do not copy a number out of a signoff doc.
   (Concrete landmine: the existing signoffs quote different passing-test counts —
   `42/42`, `68/68`, `73/73` — at different dates. Re-derive the *current* number; treat
   the drift as a claim-hygiene finding to reconcile, not as three facts.)
2. **A green unit/widget/build test is NOT proof of user-facing behavior.** Anything a
   real person experiences on a phone (input clears the nav bar, a push arrives, mic
   dictation re-arms across a pause, an image renders, the live chat loop closes) is proven
   **only on-device**, never by `flutter test` or `flutter build`. Score those items
   `UNPROVEN` until there is an on-device artifact, however green the suite is.
3. **The backend loop is proven against the OWNER's own throwaway test cloud, BEFORE the
   second developer** — never "it will work once Brandon enables it." A shape proven by
   `--dry-run`/`--selftest` is a *claim*; a real Firestore write→read→delete round-trip and
   a real `--build → phone → Works` cycle on the owner's test project is the *fact*.
4. **Separate FACTS / CLAIMS / RISKS / OWNER-DECISIONS** in your report (template in §11).
   Never blend them. Report only verified, command-output facts as facts.
5. **Two subjects, two maturities.** Stock-Track has running code + an on-device build;
   audit it by *executing*. Appharness is **planning-stage, no framework code yet**; audit
   it by *design review* — score its areas `DESIGN-ONLY` and judge whether the design, if
   built, satisfies the bar (do not fail Appharness for "no code" — that is its declared
   status; fail it only for a design gap that would leak identity, lock a backend, or hide a
   severed loop).

**Actor legend (who must run each check):**

| Code | Actor | Can prove | Cannot prove |
|---|---|---|---|
| **R** | Independent AI reviewer (fresh) | code reads, greps, `flutter analyze/test`, the `*.sh`/`--selftest`/`--dry-run` gates, git-history sweep, doc-audit | on-device behavior; anything needing real ADC/creds |
| **O** | Owner-operator at a terminal, ADC-authed to the **owner's own test cloud** | real CLI reads/writes, the live round-trip, rules deploy | on-phone rendering / taps |
| **P** | Owner (Pete) on the **phone** with the dogfood build | every product-facing on-device proof | — |

R does the bulk. O + P are required for the items doctrine #2/#3 mark as on-device — and
those are exactly the items the GO/NO-GO gate (§10) will not waive.

**Prerequisites before you start (R):**
- Clean working tree: `git -C /mnt/c/dev/Brandons_App status` is empty (validation must
  leave it empty too — a dirty tree after a gate run is itself a finding).
- Toolchain present: `flutter --version`, `node --version`, `bash`.
- Read, in order: `docs/harness/HANDOVER_STATE.md`, `HARNESS_PARITY_MAP.md`,
  `PARITY_SIGNOFF.md`, `CORRECTION_SIGNOFF.md`, `PUSH_NOTIFICATIONS.md`,
  `validation/MIC_PARITY.md`, then the Appharness `docs/` set. Read them as claims.

---

## AREA 1 — Stock-Track harness READINESS before the second developer

**Goal:** is every harness surface working **end-to-end**, with evidence, not claims? The
five owner verbs — reach, converse, capture-with-evidence, triage, verify — must each close.

### Questions the auditor must answer
- Does a dev build actually mount the floating cluster **above every route**, and is the
  harness **structurally absent** in a release build?
- Does the two-way chat loop **close on a real backend** — owner sends from the phone →
  operator `--read` sees it → `--send` reply lands in-app?
- Does a filed report carry **real device logs + screenshot + build/platform/screen** on a
  **real Firestore doc** (not just a mock/local doc), retrievable by the operator?
- Does the dogfood loop close: `--build` → item appears in "Ready to test" on the phone →
  **Works** resolves it → **Still broken** reopens it?
- Does push deliver (background/foreground/terminated) and deep-link into chat?
- Does mic dictation re-arm across a natural pause and populate the report draft, on-device?

### Evidence / artifacts to collect
- **R (code + gates, from a clean tree):**
  - `cd /mnt/c/dev/Brandons_App && flutter analyze` → record the issue count.
  - `flutter test` → record the **actual** pass count (reconcile against doctrine #0).
  - `flutter build apk --debug` in the committed (firebase) mode → record `√ Built`.
  - Flip `kHarnessMode` to mock in `lib/features/dev/dev_gate.dart`, build, **revert**,
    confirm `git status` clean → record both-mode build.
  - Confirm the release-gate: grep that the cluster/entry is behind `!kReleaseMode`
    (`dev_gate.dart` `kHarnessEnabled`); read `lib/app.dart` / `main.dart` to confirm the
    overlay mounts at the `MaterialApp(builder:)` seam (above the Navigator), and that the
    widget test "entry floats ABOVE a pushed route" exists and passes.
  - `node scripts/stocktrack_chat.js --selftest` (expect a `RESULT: PASS | selftest N/N`
    line) and `node scripts/stocktrack_chat.js --help`.
- **O (real backend round-trip on the owner's test cloud, ADC only):**
  - With the owner's test project pinned and ADC logged in:
    `node scripts/stocktrack_chat.js --read` then `--send "audit ping"` then `--read` again;
    capture the message ids + the `pokedAt` bump.
  - File a report on-device, then `--reports`, `--report <id>`, `--logs <id>`,
    `--screenshots <id> <dir>` → confirm a **non-empty `logsInline`**, a `deviceInfo.platform`,
    an `appBuild`, and a downloadable screenshot on the **real** doc.
  - `--build "1.0(N) — audit"` → confirm the check-item is created with
    `awaitingVerification:true, backfilled:true`.
  - `--resolve <id>` and `--comment <id> "audit"` → confirm the owner sees the change in-app.
- **P (on the phone — the product-facing proofs doctrine #2 requires):**
  - Keyboard open → composer sits directly above it; keyboard closed → composer clears the
    nav/gesture bar (screenshot each). Repeat for report-capture + report-queue screens.
  - The floating entry is visible after pushing a full-screen route; drag it, restart the
    app, confirm position persisted and it cannot park under the nav bar (screenshots).
  - The `--build` item appears under "Ready to test"; tap **Works** → it resolves; file a
    second, tap **Still broken** → it reopens (flagged, leaves the ready list).
  - Push: follow `PUSH_NOTIFICATIONS.md` §"On-device validation" steps 3–6 (background,
    foreground-other-screen, terminated) → each delivers + deep-links + shows the message
    with no duplicate bubble.
  - Mic (per `MIC_PARITY.md` §6): from the cluster mic on a real screen, speak two sentences
    with a >2s pause → both land in order, mic stays "listening", "File a report" is
    pre-filled with "Reporting on: <that screen>"; deny-permission path is a clean message,
    not a crash.

### PASS / FAIL bar
- **PASS** requires: analyze 0, both modes build, selftests green (R) **AND** the live
  chat round-trip + the real-doc report-with-logs + the `--build→Works/Still-broken` cycle
  demonstrated on the owner's test cloud/phone (O+P), **AND** push delivering in all three
  regimes **AND** mic re-arm proven on-device.
- **FAIL / UNPROVEN** if any product-facing verb is evidenced only by a passing test or a
  `--dry-run` (that is `UNPROVEN`, not PASS). A severed verb (e.g. reports carry no logs on
  a real doc) is a hard FAIL for readiness.

### Who
R runs all code/gate checks. **O + P are mandatory** for the live loop, push, and mic —
these cannot be delegated to the AI reviewer and cannot be waived.

---

## AREA 2 — Appharness REUSABILITY (generic-core vs app-config separation holds)

**Goal:** is the core genuinely app-agnostic — behavior in framework code, identity only in
config/wiring? (Appharness = design-stage; Stock-Track = the one built instance that either
demonstrates the separation or doesn't.)

### Questions
- In the built instance (Stock-Track), does **every** framework module read identity from
  the generated config / theme seam / `main.dart` wiring, and hardcode **no** project id,
  collection, bucket, owner, or screen?
- Is the reuse boundary a **short, explicit list** (config + wiring + host root + theme +
  the one tool-list file), or is app-specificity smeared through the framework?
- Does the Appharness architecture (harness-core package vs starter vs examples vs operator
  vs config pipeline) actually keep identity out of core **by construction**?
- Is reusability proven by **re-instantiation**, or only asserted? (Stock-Track is the
  second instance of the reference pattern — does its existence + a clean scan constitute
  the proof, and what's still unproven?)

### Evidence / artifacts
- **R:** `bash harness/harness_antileak_scan.sh` (expect `ANTILEAK RESULT: PASS | 0 …
  literals | N files`) and `--list` to see the exact scope. Then independently read each
  file the scan covers under `lib/features/dev`, `lib/harness`, and the operator scripts,
  and confirm by eye that identity enters only via `HarnessConfig` / `project.config.json` /
  theme / `main.dart` (PARITY_SIGNOFF §1–§2 is the claim; verify it).
- **R:** grep the framework Dart for any app noun the scan doesn't pattern-match (screen
  names, "stock", "brandon", collection literals) that should have come from config — the
  scan catches the *reference* app's literals; you must also confirm no *this-app* literal is
  baked where config belongs. (G3 in PARITY_SIGNOFF was exactly this class — a hardcoded
  `stockIssueReports` path; confirm it and any siblings now read `HarnessConfig`.)
- **R:** for Appharness, read `ARCHITECTURE.md` §2–§5 + `PLANNING_RESPONSE.md` §7 and score
  whether the *design* forces the split (interface-only data access, generated config as the
  only identity path, voice as its own package, no domain nouns in core).

### PASS / FAIL bar
- **PASS:** scan PASS **and** an independent read confirms zero identity literals in
  framework modules (both the reference app's *and* this app's), and the reuse boundary is a
  short enumerable list. Appharness design PASS if the separation is structural, not
  aspirational.
- **FAIL:** any framework module hardcodes an app-specific name where config should feed it;
  or the "boundary" is actually diffuse; or the Appharness design leaves a path for identity
  into core.

### Who
R (fully). This area needs no device.

---

## AREA 3 — Private LEAK RISK (nothing private goes public / to the second dev)

**Goal:** no reference-app or this-app private identifier, and **no secret**, is present in
what would be handed over or open-sourced.

### Questions
- Does the built instance contain **any** reference-app identity literal (project id, owner
  UID, package prefix, bucket, push channel, repo root, project name)?
- Is any **secret** (key, token, service-account, `.env`) tracked now, or **anywhere in git
  history**?
- Does the anti-leak scan **cover every** framework + operator script (no un-scanned new
  file), and are its exclusions the legitimate guard/blocklist files only?
- Do the Appharness docs refer to prior apps **only abstractly**, with no real
  app/product/owner name in code *or* prose?

### Evidence / artifacts
- **R:** `bash harness/harness_antileak_scan.sh` → PASS with 0 literals. Then verify
  **coverage**, not just the pass: `--list` must include every operator script
  (`stocktrack_chat.js`, `stocktrack_workflow_status.js`) and every `lib/features/dev` +
  `lib/harness` Dart file; confirm the only `is_excluded()` entries are the scan itself, the
  schema, `bp_guard.js`, and the ship guardrail (each names literals *to block them* — read
  `scripts/bp_guard.js` to confirm that's its sole purpose). A new operator script that
  slipped the scope list is a finding (this was gap G1).
- **R:** history sweep — `git -C /mnt/c/dev/Brandons_App log --all -p | grep -nEi
  '(service-account|BEGIN PRIVATE KEY|application_default_credentials|\.env|api[_-]?key|token)'`
  and inspect any hit. Confirm `.gitignore` blocks `*service-account*.json`,
  `*google-services.json` (client config is not a secret but confirm intent),
  `application_default_credentials.json`, `.env*`, `*.key`. Confirm no
  `service-account.json` is tracked (the config *path* to one is fine; the file must not be).
- **R:** confirm the runtime guard is real: `node scripts/bp_guard.js` self-test PASS, and
  read that both operator scripts call it before any Admin-SDK init.
- **R (Appharness):** grep the whole `Appharness/` tree for any real app/product/owner name;
  read `ANTI_LEAK_CHECKLIST.md` + `PUBLIC_RELEASE_CHECKLIST.md` Gate 1 and confirm the design
  makes public release a non-event (both scan directions).

### PASS / FAIL bar
- **PASS:** scan PASS **with full coverage**; guard self-test PASS and wired before init;
  **zero** secret in tree or history; `.gitignore` proven; Appharness docs carry no real
  private identifier.
- **FAIL:** any reference/foreign literal in framework code; any secret ever committed
  (history counts — if dirty, the remedy is publish-from-clean-history, which is itself a
  blocking finding); any un-scanned operator/framework file; any real name in Appharness.

### Who
R (fully). No device needed. This area is a hard gate for both handoff and any public step.

---

## AREA 4 — App-agnostic DESIGN (identity lives only in config/wiring, never framework)

**Goal:** confirm the *mechanism* that keeps identity out of framework code is real and
enforced, not merely followed by hand this once.

### Questions
- Is the config pipeline (`project.config.json` → schema → loader → codegen →
  `harness_config.g.dart`) the **single** path identity takes into code, and is the
  generated file **generated, not hand-edited**?
- Does `--check` catch generated-config drift? Does the loader `--selftest` prove
  interpolation resolves with no leftover `${…}`?
- Is the backend chosen at **exactly one** seam (`main.dart` mode constant), with every
  harness widget on the abstract interfaces?
- Would a **rebrand** (edit config + regenerate + swap theme) actually move the whole app,
  with the scan proving no old identity remains?

### Evidence / artifacts
- **R:** `node harness/gen_app_config.js --check` → expect `PASS | generated config up to
  date`. Then make a throwaway edit to a name in `harness/project.config.json`, re-run
  `--check` → it must report **drift/FAIL** (proves the check has teeth), then `git checkout`
  the config and regenerate to clean. Record both outputs. (Do not commit the throwaway.)
- **R:** read `harness/gen_app_config.js` + `lib/harness/harness_config.g.dart` header to
  confirm the generated file declares itself generated; grep that harness widgets read
  `HarnessConfig.*` rather than literals.
- **R:** read `main.dart` — confirm the Firebase-vs-Mock trio is selected in one place and
  the interfaces are the only data surface (cross-check `BACKEND_ADAPTERS.md` three-interface
  contract for Appharness).
- **R:** `node scripts/stocktrack_workflow_status.js --selftest` (expect `PASS | selftest
  N/N`) as a second config-consuming script that must resolve identity purely from config.

### PASS / FAIL bar
- **PASS:** `--check` passes clean AND fails on injected drift; loader/status selftests
  green; one backend seam; generated config is generated. Appharness design PASS if the
  four-stage pipeline + one-seam rule is specified as the only identity path.
- **FAIL:** `--check` can't detect drift (toothless), a hand-editable generated file, more
  than one backend seam, or any harness widget bypassing the interfaces.

### Who
R (fully).

---

## AREA 5 — Firebase / NO-KEY model + backend-adapter seam

**Goal:** backend access is **permission/ADC only** with no committed credential, and the
backend is a **replaceable adapter**, not hardcoded Firebase.

### Questions
- Do the operator scripts authenticate via **ADC (`applicationDefault()`) + an explicit
  project-id pin from config** — never a key file, never a token literal?
- Is a wrong-project write **structurally impossible** (pin + guard abort), and does the app
  show an actionable "backend not ready" instead of silently cross-talking?
- Is the in-app data layer behind **abstract interfaces** (auth/chat/report + local store),
  so swapping backends touches only root wiring — i.e. is "Appharness = Firebase" false in
  the code?
- Does the mock adapter run the **full** harness with **zero** backend, durably across a
  restart?

### Evidence / artifacts
- **R:** read both operator scripts' init path — confirm `applicationDefault()` + a
  `projectId` read from config, and that `bp_guard.assertStockTrackOnly(...)` runs first
  (`exit 3` on a foreign literal or wrong project). Prove the abort fires: run any write
  command with **no ADC present** → expect the honest
  `BLOCKED | no Application Default Credentials …` line and a non-zero exit (a false-green
  here is a critical finding).
- **R:** grep the whole repo for a committed key/token/service-account (overlaps Area 3);
  confirm `firebase.serviceAccountPath` in config is a **path string only** and the file is
  absent/gitignored.
- **R:** confirm the interface seam in code — the three repositories have Firebase **and**
  Mock implementations chosen in `main.dart`; harness widgets import interfaces, not
  `cloud_firestore`. Cross-check against `BACKEND_ADAPTERS.md` (the contract) +
  `SECURITY_MODEL.md` (the no-key model) for Appharness.
- **R:** build + run mock mode; confirm (via the persistence tests **and**, ideally, a mock
  on-device or emulator run) that a filed report + a Works/Still-broken verdict survive a
  restart.
- **O:** prove the *positive* ADC path once — a Firestore write→read→delete round-trip on
  the owner's test cloud (HANDOVER_STATE claims this is already done; re-demonstrate it) and
  a `firebase deploy --only firestore:rules` from the repo (rules deployed programmatically,
  not console-pasted, per SECURITY_MODEL).
- **P (recommended):** deliberately misconfigure the client to a non-existent project on a
  throwaway build → confirm the app shows the actionable "backend not ready" state, not a
  crash or silent cross-talk.

### PASS / FAIL bar
- **PASS:** ADC-only proven (positive round-trip by O; negative "no ADC → BLOCKED non-zero"
  by R); guard aborts on wrong project/foreign literal; no committed secret; the three-
  interface seam is real and mock runs the full harness durably. Appharness design PASS if
  the contract is backend-neutral and the no-key model is specified as enforced (not just
  documented).
- **FAIL:** any key/token in the loop; a script that proceeds without ADC (false-green); a
  harness widget calling Firestore directly; mock mode that can't run the full loop or loses
  state on restart.

### Who
R for code + negative-path + mock durability; **O** for the real ADC round-trip + rules
deploy; P optional for the misconfig state.

---

## AREA 6 — DOCS completeness (a new owner/dev could stand this up)

**Goal:** could someone with only the repo — no tribal knowledge — enable the backend, run
the operator loop, ship a build, and dogfood it?

### Questions
- Do the second-developer docs (`docs/FOR_BRANDON_harness_backend.md`,
  `docs/BRANDON_FIREBASE_SETUP.md`, `docs/FOR_BRANDON_enable_tester_pipeline.md`) give an
  **exact, ordered** path: enable Firestore/Anonymous-Auth/Storage, grant the ADC/IAM role,
  `gcloud auth application-default login`, deploy rules, run the operator loop, ship?
- Is the **permissions-not-keys** security block **up front**, with the exact minimal IAM
  role named (not "some role")?
- Does the push transfer doc let a new project wire FCM end-to-end from config + the named
  native edits?
- For Appharness: do the three-audience docs (non-coder owner / AI agent / developer) each
  let their reader do their job from the repo alone?

### Evidence / artifacts
- **R (cold-read test — the core method here):** read each Brandon doc as if you know
  nothing, and produce a literal step list. Every step must be executable without a
  guess. Flag each place you'd have to **ask a human** — each is a doc gap. Confirm the
  security block leads and names the exact role(s).
- **R:** cross-check the docs against reality — every command/script/flag a doc names must
  exist (`--help` on each script; `--selftest`; the ship runbook `STOCKTRACK_SHIP_RUNBOOK.md`
  vs `scripts/stocktrack_ship.sh`). A doc that references a missing script/flag is a finding.
- **R:** confirm `PUSH_NOTIFICATIONS.md` "Transfer to a new project" is complete (config
  block, dependency, manifest + channel edits, rule deploy, on-device checklist).
- **R (Appharness):** read `PUBLIC_RELEASE_CHECKLIST.md` Gate 2 + `PLANNING_RESPONSE.md`
  §10 audit-box; score each audience doc for standalone sufficiency.
- **P (highest-value, if available):** a non-technical owner attempts the enable-backend
  path from the docs alone; every point they get stuck is a blocking doc gap
  (`PUBLIC_RELEASE_CHECKLIST` Gate 2 requires this walk).

### PASS / FAIL bar
- **PASS:** a competent reader (and, ideally, a non-coder for the owner path) can go
  repo → enabled backend → running loop → shipped dogfood build with **no** undocumented
  step and no missing script/flag; security-first framing present with the exact role named.
- **FAIL:** any load-bearing step missing/ambiguous; a referenced script/flag absent; the
  key-vs-permission model unclear; an audience doc that can't stand alone.

### Who
R for the cold-read + cross-check (most of it). P for the non-coder walk (the strongest
evidence; required before any public step, recommended before Brandon).

---

## AREA 7 — Third-app test (build a THIRD app without messy copy-paste)

**Goal:** the strongest reusability proof — could someone stand up a *third*, unrelated app
without hand-editing framework files? Stock-Track proved reuse **once** (a second
instantiation); this asks whether the mechanism generalizes, or whether reuse still means a
bespoke port each time.

### Questions
- What is the **literal instantiation procedure** — how many files does a third app edit,
  and are they all config/wiring (not framework)?
- Does re-pointing `project.config.json` + regenerating + swapping the theme + the one
  tool-list + `main.dart` wiring actually produce a running harness for a new identity —
  with the scan proving no prior identity remains?
- Is the reuse mechanism **package-shaped** (a dependency you add) or **copy-shaped** (a
  tree you fork and edit)? Appharness §Q1–Q2 recommends package-shaped; is the current
  Stock-Track instance already close, or would a third app inherit a full copy?

### Evidence / artifacts
- **R (dry instantiation walkthrough — no new app needed):** enumerate, from
  `PARITY_SIGNOFF.md §2` + the code, the **exact** file set a new app must touch:
  `harness/project.config.json`, `lib/harness/harness_config.g.dart` (generated),
  `lib/main.dart`, `lib/app.dart`, `lib/features/dev/harness_theme.dart`,
  `dev_gate.dart`, the one tool-list file, `firestore.rules`/`storage.rules`, the native
  manifest/channel, the ship script. Confirm **none** of these is a framework module and
  the list is short + enumerable. Any framework file that would need a hand-edit for a new
  app is a FAIL for this area.
- **R (optional, strongest):** perform a **throwaway rebrand** in a scratch copy — change the
  config identity to a neutral placeholder, `gen_app_config.js`, run the anti-leak scan in
  **cross-project direction** (scan for the *old* identity) → it must come back clean;
  `flutter analyze` still 0. Discard the scratch copy. This demonstrates the rebrand
  mechanism end-to-end without shipping a third app.
- **R (Appharness):** score whether the planned repo shape (`harness_core/` package +
  `starter_flutter_app/` + `examples/` + `create-appharness` template, `PLANNING_RESPONSE`
  §Q1/audit-box) makes the third app a `clone-starter` / `add-dependency` operation rather
  than a fork-and-edit.

### PASS / FAIL bar
- **PASS:** the third-app procedure is a short, all-config/wiring file list with a
  regenerate + scan that mechanically proves the old identity is gone; the reuse path is
  (or is credibly designed to become) package/template-shaped, not a bespoke re-port.
- **FAIL:** instantiation requires editing framework modules; the file list is long/diffuse;
  or the only demonstrated reuse is a hand-adapted copy with no generalizing mechanism.

### Who
R (fully). The throwaway rebrand is the highest-value optional evidence.

---

## AREA 8 — Pre-PUBLIC-release fixes (what must be fixed before any open-source)

**Goal:** distinct from the Brandon handoff — enumerate what must be true before **any**
public/open-source step. (Handing to one trusted second developer is a lower bar than
publishing to the world.)

### Questions
- Are all Appharness `PUBLIC_RELEASE_CHECKLIST.md` gates (0 real / 1 no-identity /
  2 three-audience / 3 legal / 4 safe-defaults / 5 independent-audit) satisfiable, and which
  are open?
- Is a fresh clone **safe-by-default** (mock mode, no keys, no risk to a stranger)?
- Is there **any** secret in **git history** (not just the tree)?
- Are third-party licenses (the voice engine incl. the bundled offline model, Flutter/
  Firebase SDKs, Node deps) compatible + acknowledged, and is a license chosen?
- Does every operator/audit script meet the agent-first output contract (`--help`, one
  `RESULT:` line, non-zero on real failure, **no false-green**)?

### Evidence / artifacts
- **R:** walk `PUBLIC_RELEASE_CHECKLIST.md` Gate-by-Gate and mark each
  green/open/owner-decision. For Gate 1, re-use Area 3's history sweep. For Gate 4, confirm a
  fresh clone defaults to mock (`kHarnessMode`) and needs no account/key to run the full
  harness. For Gate 5, note this very audit is that independent pass.
- **R (output-contract sweep):** run each script with `--help` and with a **forced bad arg**
  → confirm a single `RESULT:` line and a **non-zero** exit (prove no false-green:
  `node scripts/stocktrack_chat.js --bogus; echo "exit=$?"` must be non-zero;
  `bash harness/harness_antileak_scan.sh --bogus; echo "exit=$?"` must be non-zero).
- **R (licensing):** enumerate the voice engine + offline-model license, `sherpa_onnx`,
  Firebase/Flutter SDK, and Node deps; flag any incompatibility and whether a project license
  is chosen (owner-decision).
- **R:** confirm the offline-speech-model distribution story (downloaded-on-first-use vs
  bundled asset per `MIC_PARITY.md §6`) is licensing-clean and documented.

### PASS / FAIL bar
- **PASS (for public):** all six gates green or explicitly an owner-decision; clean history;
  safe-by-default mock; licenses compatible + a license chosen; every script passes the
  output contract with a proven non-zero on failure.
- **NOT-YET (expected):** Appharness has no framework code yet, so Gate 0 is open **by
  design** — record the open gates as a pre-public backlog, not a Brandon-handoff blocker.
- **FAIL:** a secret in history; an unsafe default (a fresh clone that can touch a real
  backend / needs a key); a false-green script; an incompatible/unlicensed dependency.

### Who
R (fully). Feeds the pre-public backlog; most items here are **not** required for the
Brandon handoff (§10 keeps them separate).

---

## 9. Cross-cutting checks (do once, they touch several areas)

- **Clean-tree invariant:** after every gate that flips a flag (mock build, `--check` drift
  test, throwaway rebrand), confirm `git status` returns to empty. A gate that leaves the
  tree dirty is a finding.
- **Claim reconciliation:** for each signoff doc, pick 3 quantified claims (test counts,
  files scanned, "N/N selftest") and re-derive them live. Log every mismatch.
- **Dry-run vs real:** every place a doc says "proven", classify it as *unit/build* (claim),
  *dry-run/selftest* (claim), or *live/on-device* (fact). The GO/NO-GO only counts facts.

---

## 10. GO / NO-GO GATE — to the SECOND DEVELOPER

> Handing to one trusted second developer is a **lower** bar than public release (§8), but
> **higher** than "the tests pass." The bar is: **every owner verb is proven to close with
> real evidence on the owner's own cloud/phone, and nothing private or unsafe travels.**
> On-device/live proofs (doctrine #2/#3) are **NOT waivable** by any amount of green tests.

**MUST be GREEN before anything goes to the second developer (the minimal proof set):**

| # | Gate | Proof required | Actor | Area |
|---|---|---|---|---|
| G1 | **Separation is clean** | anti-leak scan PASS **with full coverage** (every operator + `lib/features/dev`/`lib/harness` file in `--list`); `bp_guard` self-test PASS and wired before init | R | 3,5 |
| G2 | **No secret anywhere** | tree **and** full git-history sweep clean; `.gitignore` proven; no service-account/key/token committed ever | R | 3,8 |
| G3 | **No-key backend access is real** | positive ADC round-trip (write→read→delete) on the owner's test cloud; **negative** path proven (no ADC → `BLOCKED`, non-zero exit, no false-green) | O + R | 5 |
| G4 | **The chat loop closes live** | owner sends from the phone → operator `--read` sees it → `--send` reply lands in-app, on the owner's test cloud | O + P | 1 |
| G5 | **Reports carry real evidence** | a report filed on-device produces a **real** Firestore doc with non-empty `logsInline` + screenshot + build/platform/screen, retrievable via `--report`/`--logs`/`--screenshots` | O + P | 1 |
| G6 | **The dogfood loop closes** | `--build` → item in "Ready to test" on the phone → **Works** resolves → **Still broken** reopens | O + P | 1 |
| G7 | **Reachability + input usable on-device** | floating entry above every route + persists across restart; composer clears keyboard **and** nav bar on all three input screens | P | 1 |
| G8 | **Standable-up from the docs** | R cold-read yields a complete, no-guess enable→run→ship path; security-first, exact IAM role named | R (P for the non-coder walk) | 6 |

**SHOULD be green (strongly recommended; a documented owner-decision may accept a gap):**
- Push delivering in all three regimes + deep-link (Area 1 / `PUSH_NOTIFICATIONS.md`).
- Mic continuous re-arm + report-draft populate + deny-path, on-device (Area 1 / `MIC_PARITY.md`).
- Third-app instantiation is a short config/wiring-only file list, scan-proven (Area 7).
- Generated-config `--check` fails on injected drift (Area 4).

**NOT required for the Brandon handoff (pre-PUBLIC backlog — Area 8):** Appharness
framework code existing (planning-stage by design); a chosen OSS license; the three-audience
public docs; chat image/file sharing (fast-follow, Storage-gated).

**Decision rule:**
- **GO** only if **G1–G8 are all GREEN with facts** (not claims) recorded in the §11 report,
  and every SHOULD-gap is an explicit written owner-decision.
- **NO-GO** if any of G1–G8 is FAIL or only `UNPROVEN` (evidenced solely by unit/build/
  dry-run). "The suite is green" does **not** convert an UNPROVEN on-device gate to GO.
- **CONDITIONAL-GO** is allowed only for the SHOULD list, and only with a named owner
  decision and a tracked follow-up — never for G1–G8.

---

## 11. Reporting template (how the auditor must report — doctrine #4)

Produce one signoff (e.g. `docs/harness/AUDIT_SIGNOFF.md`) with these sections, each item
tagged and traceable to a command output or an on-device artifact:

- **FACTS** — verified, with the exact command + its output line (or the on-device
  screenshot/observation + who observed it, O or P). Nothing here may rest on a signoff-doc
  claim.
- **CLAIMS** — asserted in the prior docs but **not** re-verified live (e.g. anything proven
  only by a passing test or `--dry-run`). Each carries what would upgrade it to a fact.
- **RISKS** — what could break / is uncertain / is un-covered (e.g. an un-scanned new file, a
  license question, a history hit needing inspection).
- **OWNER-DECISIONS** — the SHOULD-gaps, the license choice, repo-shape-at-publish, whether
  to accept a CONDITIONAL-GO on any SHOULD item — surfaced for the owner's call, not decided
  by the auditor.
- **VERDICT** — per §10: `GO` / `NO-GO` / `CONDITIONAL-GO (SHOULD-items: …)` for the Brandon
  handoff, plus a separate `PRE-PUBLIC BACKLOG` list from Area 8. State the passing-test
  count you re-derived and the anti-leak file count you observed, as facts.

> Independence is mechanical, not a self-claim: the reviewer must not have implemented the
> harness, must re-run every gate from a clean tree, and must treat every prior doc as a
> claim. A verdict with no re-run command output is itself a NO-GO.
