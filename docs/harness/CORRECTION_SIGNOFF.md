# Stock-Track Owner/Operator Harness — CORRECTION SIGNOFF (Independent Validation)

**Date:** 2026-07-01
**Validator role:** INDEPENDENT UX-parity validator + integration/evidence lead. Did NOT implement the
correction. Re-ran every gate from scratch and re-read the actual code against the OWNER-updated
acceptance criteria (the ones raised after the owner dogfooded the preview and judged it a skeleton).
Evidence-over-trust: the correction docs were treated as claims to verify, not facts.
**Verdict:** **PASS-WITH-NOTES** — every acceptance criterion is met at the level a build + unit + code
read can establish; the residual notes are (a) inherently on-device product-facing checks the owner
still owns per doctrine, and (b) two consciously-surfaced mic owner-decisions. Nothing is falsely
claimed "done" on a unit test.
**Scope:** Stock-Track (`/mnt/c/dev/Brandons_App`) only. This is a reusable-harness PATTERN doc — no
reference-app internals, ids, or paths appear here by design.

---

## 0. Independent gate results (re-run by the validator, command output)

| Gate | Result |
|---|---|
| `flutter analyze` | **No issues found! (0)** — PASS |
| `flutter test` | **All tests passed! — 73/73** — PASS (incl. persistence restart-survival, cluster shape/direct-launch, launcher duplicate/exclusive/self-heal, speech-turn accumulator, honest-mode-banner resolver) |
| `bash harness/harness_antileak_scan.sh` | **ANTILEAK RESULT: PASS \| 0 reference literals \| 47 files scanned** |
| `node harness/gen_app_config.js --check` | **PASS \| generated config up to date** |
| `node scripts/stocktrack_chat.js --selftest` | **RESULT: PASS \| selftest 6/6** (BP-abort guard 6/6 + config pinned + no forbidden literal reachable + bucket pinned) |
| `node scripts/stocktrack_workflow_status.js --selftest` | **RESULT: PASS \| selftest 7/7** |
| `flutter build apk --debug` — firebase (committed default) | **√ Built app-debug.apk** (215 MB) — PASS |
| `flutter build apk --debug` — mock (flipped `kHarnessMode`, built, git-reverted) | **√ Built app-debug.apk** — PASS |

Both harness modes compile. Working tree **clean** after validation (`git status` empty; `dev_gate.dart`
back at `firebase`). The two script selftests run credential-free (no admin module needed), so the
separation guard + config pin are proven without any backend access.

---

## 1. Diagnosis — what the owner dogfood exposed

The owner dogfooded the first preview and correctly called it a **skeleton, not a reusable-harness
proof**. Grounded against the actual code, the real defects were four, in three groups:

1. **OVERLAY (wrong shape).** The floating dev entry was ONE draggable button whose tap pushed a
   separate command-center *page*; reaching any tool was two hops that LEFT the tested screen. That is
   not the reference pattern (tools launch directly over the live screen from a floating cluster).
2. **DATA (nothing survived a restart).** The mock/local path held the ENTIRE owner loop in memory —
   chat, reports, triage, and the derived dogfood/ready-to-test state re-seeded on every launch, so a
   report filed with a `local-…` id (and its verdicts) vanished on the next app open. Reports also
   carried NO device logs, NO build/platform, and NO screen-context, so a filed report was not
   diagnosable on reload.
3. **LABELING (a disconnected channel looked live).** In mock/local mode nothing is written anywhere
   an operator could read, yet the UI presented a fully live-looking chat + poke + a status line that
   hardcoded a backend name — a dogfooder could believe a message reached an operator when it did not.
4. **MIC (single-shot, not the reference contract).** The speech seam did one listen with no re-arm,
   so it ended at the first natural pause and a second utterance would overwrite the first — a
   fidelity gap versus the reference's continuous-dictation contract, not a signed-off adaptation.

---

## 2. Per-area fixes (verified in code, pattern-level)

### A. OVERLAY — floating single-FAB→page → draggable multi-tool CLUSTER
- The single-FAB-to-page model is retired. A **config-driven cluster** is mounted at the
  `MaterialApp.builder` seam (above the Navigator), rendering a grip handle + one bare FAB per tool
  spec. Each button launches its tool **directly over the current screen** — a full tool as a route on
  the shared root navigator, a checklist as a bottom sheet, poke inline — and returns to the same
  screen; there is **no intermediate menu page** in the path (the command center still exists but is
  now an optional button, not THE entry).
- Reusable seams delivered, all app-agnostic: `SingleInstanceLauncher` (duplicate-guard / exclusive
  swap / self-heal / latch-clears-on-complete), `HarnessToolSpec`, `HarnessToolButton` (bare FAB +
  per-tool red count badge, `Semantics` label not `Tooltip`, unique `heroTag`, null-uid disables),
  and `HarnessFabCluster` (long-press-drag + grip pan, fractional position in prefs, re-clamped every
  build to fold in safe-area + bottom-nav clearance). The concrete tool list lives in ONE file
  (`overlay/harness_tools.dart`).
- **Proof:** widget test asserts N floating buttons over the live shell AND that tapping one opens its
  tool with the menu page absent; launcher unit tests prove duplicate/exclusive/self-heal
  deterministically.

### B. DATA — durable local persistence + report evidence retrievable on reload
- **A generic durable-store seam** (`HarnessLocalStore`: interface + in-memory + SharedPreferences
  impls; synchronous cache-warmed `loadAll` so a repo constructor hydrates without an await). The mock
  chat + report repos now **hydrate from the store, seed-and-persist only on an empty box, and
  write-through on every mutation** through single choke-points, so chat, reports, triage, and the
  DERIVED ready-to-test loop all survive restart with no separate store. `main.dart` opens the durable
  store **only in mock mode**, namespaced from config; the firebase branch is byte-for-byte unchanged
  (server-side durable already).
- **Model round-trips** added (`ChatItem.toMap/fromMap`, `Report.toMap`), lossless — `Report.toMap`
  explicitly writes `createdAtMs` because `fromMap` takes it back from the caller; the dogfood verify
  fields + triage state are all serialized.
- **Report evidence:** a generic `CurrentScreenTracker` + route observer + the app-shell tab feed
  capture "which screen was I on"; `fileReport` (both modes) now stamps the device-log tail,
  build/platform, and screen-context; the report-detail view renders `build … · <platform> · on
  <screen>` + an expandable **device-log tail** — all from persisted fields, so retrievable after a
  restart.
- **Proof:** persistence tests simulate a restart (fresh repo over the same store) AND do a genuine
  SharedPreferences re-read: a sent message, a filed report + its comment, a "Works" verdict, and a
  "Still-broken" reopen all survive; seeds are not re-injected; namespaces are isolated.

### C. LABELING — honest connectivity, config-driven, no hardcoded app noun
- A pure resolver (`resolveHarnessConn` → `localPreview` / `backendOnly` / `live`) + config-driven
  copy drives an amber **mode banner** on the chat body and the command center (and renders **nothing**
  when actually connected). Poke tile + poke snackbar + composer hint + the backend status line are all
  mode-aware and honest; the previously-hardcoded backend name is replaced by a config-interpolated
  label. `orchestratorBridge` ships **"off"** (writes land in the backend, but the UI says an operator
  isn't reading yet); flipping to "live" is a pending owner A/B decision, not silently assumed.
- **Proof:** resolver unit tests assert the committed default maps to `backendOnly` and that copy is
  honest + config-driven for every state; independent read of every surface confirms no UI string
  hardcodes a project name.

### D. MIC — single-shot → continuous-dictation contract (engine choice ADAPT, flagged)
- The seam is rewritten to the reference's load-bearing **continuous** contract: re-arm across natural
  pauses (only an explicit stop or a permanent permission error ends the turn), partial-vs-final with
  each final APPENDED, turn-boundary reset only at start/stop, flush-on-stop + seam-recovery so no
  words are lost, transient-error tolerance, and a fast-fail guard against a runaway restart loop. The
  pure turn-accumulator is extracted and unit-tested (14 cases). Both UI callers were corrected to
  drive the mic UI from the seam's listening intent (not from a single final) and to stop inferring
  "stop" from one utterance.
- Engine choice = the OS speech recognizer (ADAPT); the bundled offline dual-engine is a conscious
  **DON'T-PORT** (heavy standalone package with no reusability signal; the reference's DEFAULT engine
  is itself the OS recognizer). Two owner-decisions are **surfaced, not silently shipped**: (1)
  field-scoped dictation vs the reference's "dictate while navigating to reproduce" (deferred with a
  `TODO(mic)`), and (2) a possible on-device beep-on-re-arm follow-up (mitigated by long
  session/pause windows, to be verified by ear).

---

## 3. Per-criterion PASS/FAIL (against the OWNER-updated acceptance criteria)

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Floating dev tools = a TRUE multi-tool overlay directly on the screen (not one button → separate page) | **PASS** | Cluster of grip + 6 tool buttons at the builder seam above the Navigator; each launches its tool directly (route/sheet/inline), no intermediate menu page; single-FAB→page model retired. Widget test proves shape + direct-launch. *On-device drag feel/persist owed to owner dogfood.* |
| 2 | Chat persists across restart (local) | **PASS** | `MockChatRepository` hydrates from `SharedPrefsHarnessLocalStore`, write-through on send; test "sent message survives a restart; seeds not duplicated" + genuine prefs re-read. |
| 3 | Reports persist across restart (local) | **PASS** | `MockReportRepository` hydrates + write-through via one choke-point; `Report.toMap` lossless; test "filed report + comment survive restart; seeds not re-injected". |
| 4 | Queue + dogfood-checklist state persist across restart (local) | **PASS** | Ready-to-test is DERIVED from persisted `awaitingVerification`; all triage/dogfood transitions funnel through the persisted `_replace`; tests prove queue + checklist survive. |
| 5 | App clearly states local-only vs live-connected | **PASS** | `HarnessModeBanner` + `resolveHarnessConn` on chat + command center; honest, config-driven copy; hidden only when truly live; no hardcoded app noun. Resolver unit-tested. |
| 6 | Orchestrator chat either reaches an operator OR the UI clearly says it cannot yet | **PASS** | `orchestratorBridge='off'` → banner "saved … isn't reading yet"; mock → "stays on this device"; poke tile disabled/honest in local preview. No false "live" claim. (Live two-way is the deferred owner A/B + backend-enable.) |
| 7 | Mic matches the reference standard, or the OS-seam adaptation is consciously flagged for owner approval | **PASS-WITH-NOTES** | Continuous-dictation contract implemented (14 unit tests on the accumulator); engine=OS seam is a flagged ADAPT with DON'T-PORT justified; 2 owner-decisions surfaced. *Actual on-device dictation + beep check owed to owner dogfood — a unit test is not product-facing proof for voice.* |
| 8 | `local-…`-style reports investigated + logs/persistence fixed | **PASS** | Root cause = mock/local path was pure in-memory (any `local-<micros>` report + verdicts vanished on restart) and stamped no logs. Fixed: durable write-through + `logsInline`/build/platform/screen stamped at file. Proven by persistence tests. |
| 9 | Report logs/build/platform/context retrievable on reload | **PASS** | `logsInline`/`deviceInfo`/`appBuild`/`region` serialized + hydrated; `report_detail` renders the meta line + expandable device-log tail from persisted fields. |
| 10 | Ready-to-test / Works / Still-broken survive restart | **PASS** | Derived from persisted fields; `markVerifiedWorks`/`markStillBroken` persist; tests prove Works→resolved and Still-broken→reopen both survive a simulated restart. |
| 11 | Anti-leak / separation clean | **PASS** | Anti-leak scan PASS (0 reference literals, 47 files); independent grep confirms every reference mention in `lib/` is a doc-comment/port-note, zero live identifiers; both script selftests carry a 6-check abort-guard, PASS; runtime guard aborts on any forbidden literal. |
| 12 | Stays generic-harness-first (app-specific isolated to config/wiring) | **PASS** | Framework modules name no project id/collection/owner; identity flows from generated config / theme seam / `main.dart`. App-specific isolated to the one tool-list file, the app-shell tab labels, `project.config.json`, and `main.dart` wiring. |

**No criterion is FAIL.**

---

## 4. Deferred / owed (each with reason — not a miss)

**Owner-decision flags surfaced by the mic correction (need an owner call, correctly not built blind):**
- **Field-scoped continuous dictation vs "dictate while navigating to reproduce."** This ships
  field-scoped continuous capture (closes the real single-shot gap on the report + chat inputs). The
  reference's headline navigate-while-dictating needs a model-sink draft + a global mic + a live
  transcript chip — a scoped follow-up (`TODO(mic)`), not a silent weaker substitute.
- **Beep-on-re-arm.** Minimised by long session/pause windows; if audible on-device, the minimal fix
  is a session-scoped native stream-mute — to be verified by ear, flagged not pre-built.

**Deferred by design (conscious ADAPT/DON'T-PORT):**
- Bundled offline dual speech engine + A/B toggle — DON'T-PORT (heavy package, no reusability signal;
  the OS seam reaches the reference's default engine).
- The "live bridge" enablement (`orchestratorBridge` → "live") — a pending owner A/B decision; the
  honest "off" state is the correct default until an operator loop is actually reading.

**Blocked on backend enablement (code complete + credential-free; runs unchanged once granted):**
- The live two-way operator round-trip (real backend reads/writes from the CLI) needs the owner-side
  IAM grant + ADC login (never a committed key). `--dry-run` + both `--selftest`s prove the shapes
  today. Storage (chat images / report screenshot upload) is deliberately off behind one flag.

**Owed on-device (owner dogfood — device behaviour a build/unit test cannot assert, per doctrine):**
- Multiple buttons visibly floating over the tested screen + drag/persist across a real restart +
  rotation; pixel keyboard/nav-bar clearance on the input surfaces; live mic dictation of two
  utterances with a pause (both land, mic stays "listening", tap-off keeps the last words) + the mic
  permission-deny path; local image render; overall product feel. Code + both-mode builds are green;
  these are the honest on-device confirmations.

---

## 5. Verdict

**PASS-WITH-NOTES.** The correction is a faithful, config-driven, provably-separated fix of every
skeleton complaint the owner raised: the floating tools are now a true draggable multi-tool cluster
that launches each tool over the live screen; chat, reports, the queue, and the whole dogfood loop
survive an app restart on the local path; reports carry logs/build/platform/screen-context that are
readable on reload; the channel is honestly labeled local-vs-connected and never fakes a live
operator; and the mic is raised to the continuous-dictation contract with the OS-seam adaptation
consciously flagged. Every acceptance criterion is met at the code + gate level, separation is
tool-checked clean, and both modes build. The only residual items are the inherently on-device
product-facing checks the owner owns by doctrine and the two surfaced mic owner-decisions — none of
which is a false "done" and none of which blocks the harness-reuse proof.
