# Stock-Track Owner/Operator Harness — PARITY SIGNOFF (Independent Validation)

**Date:** 2026-07-01
**Validator role:** INDEPENDENT parity validator — did NOT implement the harness; re-ran every gate and
re-read the actual code against `docs/harness/HARNESS_PARITY_MAP.md` §5 acceptance + §6 checklist.
Evidence-over-trust: the chunk docs were treated as claims to verify, not facts.
**Verdict:** **PASS-WITH-NOTES** (every MUST-HAVE implemented + independently confirmed; 5 minor gaps
logged below, none blocking the loop, all in the ADAPT/DEFER band).

> **UPDATE 2026-07-01 — all 5 gaps (G1–G5) RESOLVED by the implementation lane** (surgical fixes; gates
> re-run green). See **§5 Gap resolution**. Post-fix gates: `flutter analyze` 0 · `flutter test` **42/42** ·
> `harness_antileak_scan.sh` **PASS / 40 files** (now covers the publisher) · both `--selftest`s PASS · both
> modes build. Verdict is now **PASS (gaps closed)**; on-device dogfood (Pete) + backend/Storage/ADC
> enablement (Brandon) remain the only outstanding items.

---

## 0. Independent gate results (re-run by the validator, command output)

| Gate | Result |
|---|---|
| `flutter analyze` | **No issues found!** (0 issues) — PASS |
| `flutter test` | **All tests passed! (42/42** post-fix; 40/40 at first validation) — PASS (incl. "entry floats ABOVE a pushed route", the dogfood Works→resolved / Still-broken→reopen mock loop, the reopen-bug fix, and the new G2 merged-badge + G5 canonical-reopen assertions) |
| `bash harness/harness_antileak_scan.sh` | **ANTILEAK RESULT: PASS \| 0 Blueprint literals \| 40 files scanned** (post-G1: now covers `stocktrack_workflow_status.js`; `stocktrack_ship.sh` scan-excluded as a guardrail) |
| `node scripts/stocktrack_chat.js --selftest` | **RESULT: PASS \| selftest 6/6** (BP-abort guard + config pinned to the project + no forbidden literal reachable + storage bucket pinned) |
| `node scripts/stocktrack_workflow_status.js --selftest` | **RESULT: PASS \| selftest 7/7** |
| `flutter build apk --debug` (firebase mode, the default) | **√ Built app-debug.apk** — PASS |
| `flutter build apk --debug` (mock mode — flipped `kHarnessMode`, built, **git-reverted**) | **√ Built app-debug.apk** — PASS; `dev_gate.dart` left clean, working tree clean |

Both harness modes compile. The working tree is clean after validation (`git status` empty; `dev_gate.dart`
back at `firebase` + `kHarnessStorageEnabled=false`).

---

## 1. Generic harness framework (the reusable, app-agnostic modules delivered)

These modules hardcode **no** project id / collection / owner / bucket. Identity reaches them only as
plain values from the config seam, the theme seam, or `main.dart` wiring. A future app reuses them verbatim.

**Reachability / mount (Chunk 1)**
- `lib/features/dev/harness_overlay.dart` — the floating dev entry, mounted at the `MaterialApp(builder:)`
  seam so it floats **above every pushed route** (proven by widget test: "entry floats ABOVE a pushed
  route"). Pan-drag (a `GestureDetector`, not a `Draggable`, because above-Navigator there is no Overlay
  ancestor); a drag clamp that folds in the system nav/gesture inset (`maxY = height − padding.bottom −
  clearance − fabSize`) so it can never park under the nav bar; a `SharedPreferences` **fractional** position
  store restored + re-clamped each build; a merged "needs-me" count badge.
- The §7 composer fix pattern (`resizeToAvoidBottomInset:true` + `body: SafeArea(top:false)`) applied to the
  chat screen, the report-queue screen, and the capture screen — the input always rides above the keyboard
  (open) and clears the nav bar (closed).

**Diagnostics (Chunk 2)**
- `lib/core/utils/harness_logger.dart` — release-gated (`!kReleaseMode`) singleton, 3 generic categories
  (chat/report/system), a bounded 600-line ring buffer, `snapshot(percent)`, and `inlineTail(maxBytes)`
  (byte-capped, newline-aligned) — the buffer a report snapshots as `logsInline`.
- `lib/core/utils/harness_app_build.dart` — `resolveHarnessAppBuild()` via `package_info_plus`; degrades to
  `'unknown'` off-platform, never throws.

**Dogfood verify loop (Chunk 3)**
- `lib/features/dev/dogfood/ready_to_test_sheet.dart` — the CONSUMPTION half: reads the generic owner-reports
  stream, filters to `awaitingVerification`, per-item **Works** / **Still broken** through the canonical repo
  writes, honest empty state.
- Model verify fields (`awaitingVerification` / `region` / `verifiedByUser` / `testOnLabel`), the
  `readyToTest` filter bucket, and the canonical `resolvedFields()` / `reopenedFields()` helpers +
  the reopen-bug fix live in the report model / filter / repository.

**Chat operator surface (Chunk 4)**
- `chat/services/chat_export.dart` (pure paste-ready frames: `oneBubble` / `threadBlock` / `fullFrame` /
  `recentFrame` / `contextHeader`, degrades gracefully with no published context),
  `chat/widgets/chat_selection_bar.dart`, `chat_header.dart`, `chat_new_messages_pill.dart` (floating
  `Positioned`, off the `Column` flow), `workflow_dashboard_sheet.dart` (empty-but-honest + a >6h stale
  banner), per-bubble copy + long-press multi-select in `chat_bubble.dart`, and the screen's 3-frame
  autoscroll + last-export cursor.

**Rich capture (Chunk 5)**
- `core/utils/harness_speech.dart` (thin OS `speech_to_text` seam, `ensureAvailable()` never throws),
  `chat/services/chat_upload_service.dart` + `report_capture/services/screenshot_upload_service.dart`
  (Storage-gate seams: local descriptor when Storage off, upload when on, degrade-to-local on failure so a
  report is never lost), `report_queue/widgets/report_image.dart` (remote/local/placeholder render +
  full-screen pinch-zoom gallery), inline chat image + `showChatImageZoom`, the DEVICE LOG TAIL view in
  `report_detail.dart`, mic-to-note + copyable submit report-ID in the capture screen.

**Off-device operator loop (Chunk 6)**
- The CLI command *shapes* in `scripts/stocktrack_chat.js` (`--read`/`--send`/`--build`/`--reports`/`--report`/
  `--logs`/`--resolve`/`--comment`/`--screenshots`/`--dry-run`/`--selftest`), the pure `buildProjection` +
  publisher in `scripts/stocktrack_workflow_status.js`, the `readAgentStatus` seam + pure `agentsEngagedCount`,
  the poke-with-note dialog, the "N engaged" badge. All logic is identity-free; every collection/doc/bucket is
  read from config.
- The config substrate itself: `harness/project.config.json` → `harness/gen_app_config.js` →
  `lib/harness/harness_config.g.dart` (generated `HarnessConfig`), plus `harness/harness_config.js` (the JS
  loader the scripts read). This generator seam is what makes the harness reusable at all.

---

## 2. Stock-Track-specific wiring / config (the reuse boundary)

Everything app-specific is isolated to config + wiring + the host root — swap these and the framework moves
to another app unchanged:

- **`harness/project.config.json`** — the ONE identity file: project name/slug/owner-role (`brandon`),
  Firebase project (`easy-stock-track`) + bucket, collection/doc names (`orchestratorChat`,
  `stockIssueReports`, `system/orchestratorPoke`, `system/workflowContext`, `system/agentStatus`), push
  presentation. Holds NAMES/PATHS/IDS only — never secret values.
- **`lib/harness/harness_config.g.dart`** — generated from the above; the in-app `HarnessConfig` every harness
  widget/service reads. Regenerate, don't hand-edit.
- **`lib/main.dart`** — the wiring seam: chooses the Firebase vs Mock trio (auth/chat/report) from the single
  `kHarnessMode` constant; every harness widget talks only to the abstract interfaces, so the mode is chosen
  here and nowhere else.
- **`lib/app.dart`** — the host root (`StockTrackApp` / `AppShell`) + the shared `navigatorKey` the overlay
  pushes through. Inherently app-specific.
- **`lib/features/dev/harness_theme.dart`** — the one thin theme seam: `HarnessTheme.accent/panel/background`
  resolve to Stock-Track's own palette (`AppColors`). Every ported dev surface reads this, so no reference
  colour constant survives the copy.
- **`lib/features/dev/dev_gate.dart`** — the three app-level switches: `kHarnessEnabled` (`!kReleaseMode`),
  `kHarnessMode` (firebase/mock), `kHarnessStorageEnabled` (attachment uploads).
- **`firestore.rules` / `storage.rules`** — owner-scoped to the anonymous UID (chat + reports keyed to
  `request.auth.uid`; default-deny); the Admin SDK bypasses them. Storage rules cover
  `stockIssueReports/{uid}/**`.
- **`AndroidManifest.xml` / `Info.plist`** — the host app's own mic permission strings.
- **`scripts/stocktrack_ship.sh`** — Stock-Track's own build→App-Distribution ship, pinned to its own
  project/app-id/tester group.

---

## 3. Intentionally deferred (each with reason + impact)

**Deferred by design (ADAPT/DEFER/DON'T-PORT per the map — a conscious scope call, not a miss):**
- **Drag ergonomics** (long-press-to-drag, grip, haptic, scale) — DEFER. Impact: cosmetic; the puck already
  drags + persists + clamps.
- **Message-engine self-heal / seen-cursor badge / push overlay / latency carry / `PopScope`** — DEFER; the
  listener + foreground poll + poke cover Rung-0. Impact: none for the first proof.
- **Structured two-dimension tagging / per-stream colours / lane registry / region-sharded queue / multi-agent
  dashboard** — DON'T-PORT (single-lane app). Impact: none; would add surface with nothing to coordinate.
- **Bundled offline dual speech engine + A/B toggle** — DON'T-PORT; the OS speech seam proves "talk to your
  phone." Impact: none for reuse signal.
- **Draft minimize/resume, log-percent selector, parent/child sub-reports, count line, misread flag,
  clarification block, AI-curation fields, jump-to-report, workflow grouping / accept-all in the sheet** —
  DEFER (second layer atop an already-provable loop).
- **FCM push on `--build`** — DEFER; the poke + in-app badge carry the wake for now.
- **Full-buffer log Storage upload / on-disk log files** — DEFER; the inline tail restores logs-first.

**Blocked-on-Brandon (code complete + credential-free; runs unchanged once granted):**
- **Live two-way backend round-trip** (real Firestore reads/writes from the operator CLI) — needs Brandon's
  IAM grant + `gcloud auth application-default login` (ADC, never a key). Impact: `--dry-run` + `--selftest`
  prove the shapes today; the live loop needs the grant.
- **Live Firestore + Anonymous Auth** in the project — the in-app `Backend not enabled yet` state is the
  actionable placeholder until Brandon turns them on.
- **Live Storage** — deliberately OFF; `kHarnessStorageEnabled=false`. Report screenshots + chat images are
  fully functional in mock mode (local render) and degrade gracefully in firebase mode. Impact: **one flag
  flip once Brandon enables Storage** — plus (see gap G4) adding the `orchestratorChat/{uid}/media/**` rule to
  `storage.rules`, which is not yet present.
- **Live Storage screenshot download** (`--screenshots`) — additionally gated on Storage-enable.

**Owed on-device (Pete's dogfood — device behaviour a build/unit test cannot assert):**
- Keyboard/nav-bar **pixel** clearance; live **mic** dictation (permission + engine); local **image** render;
  a **non-empty `logsInline` on a REAL Firestore doc**; the full **`--build` → phone → Works closes it**
  round trip; overall product feel. Code + both-mode builds are green; these are the honest on-device checks.

---

## 4. Anti-leak / separation proof (command output)

```
$ bash harness/harness_antileak_scan.sh
ANTILEAK RESULT: PASS | 0 Blueprint literals in the Stock-Track harness | 40 files scanned

$ node scripts/stocktrack_chat.js --selftest
PASS  BP-abort guard unit tests
PASS  config projectId is easy-stock-track
PASS  config reports collection is stockIssueReports
PASS  config owner role is brandon
PASS  resolved config carries NO BP literal
PASS  storage bucket pinned to easy-stock-track
STOCKTRACK-CHAT RESULT: PASS | selftest 6/6
```

**Independent (validator-run) BP-literal grep across `harness/`, `scripts/`, `lib/`** (denylist: the
reference project id / owner UIDs / project number / package prefix / repo root / push channel / project
name), excluding the two guard files that must name literals to block them:

- **Zero actual crossover in any framework module.** The only hits anywhere are in `scripts/stocktrack_ship.sh`
  — and they are the ship script's own **separation guardrail** (a `grep` that refuses to run if a reference
  identifier is present) plus its explanatory comments. That is the same allowed pattern as `scripts/bp_guard.js`
  (the one file that legitimately names the forbidden literals in order to abort on them, and is scan-excluded
  by design).
- Runtime defence-in-depth is real: `bp_guard.js` aborts (`exit 3`) if any forbidden literal is reachable from
  the resolved config OR the project id isn't the pinned one; both operator scripts call it before any Admin-SDK
  init and authenticate via ADC with an **explicit projectId pin** — never a committed key/token.
- The reuse boundary holds: generic modules read identity only from `HarnessConfig` / `project.config.json` /
  the theme seam / `main.dart`. Confirmed by reading each module (Section 1) — no project id, collection, owner,
  or bucket literal in framework code.

---

## PARITY SIGNOFF — verdict

**(a) Every MUST-HAVE from the map implemented?** — **YES**, independently confirmed in code:
overlay-above-Navigator (widget-test proven); keyboard/nav-safe composer (§7 applied to all three input
surfaces); dev gate + command center + poke; live two-way text + offline queue; copy-out (per-bubble +
multi-select + paste-ready context); note + screenshots; **device logs on the report** (`logsInline` +
`deviceInfo.platform` + `appBuild` stamped, DEVICE LOG TAIL view); operator-side queue CLI
(read/pick/logs/resolve/comment/screenshots); tolerant read model; filter buckets incl. `readyToTest`;
recommend-then-act strip; **correct reopen path** (dropdown + toggle + sheet all clear `manualResolved`);
comments; full-screen screenshot zoom; canonical resolved/reopened helper; `--build` check-item
(`awaitingVerification`+`backfilled`); **in-app Ready-to-test surface**; Works/Still-broken canonical writes;
model reads `awaitingVerification`; command center counts it separately; logger + ring buffer; backend-mode +
UID + build surface; `--read`/`--send`/`--build`; poke; strict separation + config substrate.

**(b) Every ADAPTED item consciously adapted (not accidentally missing)?** — **YES.** Position persistence,
nav clamp, floating pill + 3-frame autoscroll, image/mic via the OS/Storage seams, ChatGPT export + copy-area
(degrades gracefully), dashboard sheet, wont-fix label, poke-with-note, agents-engaged badge,
`--resolve`/`--comment`, `workflowContext` publisher, `--dry-run` — all present and re-seamed to config, not
copied from multi-lane infra.

**(c) Every DEFERRED item has a reason + impact?** — **YES** (Section 3), split into deferred-by-design,
blocked-on-Brandon, and owed-on-device-dogfood.

**(d) No major owner/operator workflow power lost?** — **NO power lost.** All five verbs (reach, converse,
capture-with-evidence, triage, verify) are present and, where a live backend isn't required, proven. The port
is a faithful re-instantiation, not a skeleton — the exact "skeleton" complaints (input behind the nav bar, no
copy-out/export/dashboard, no logs on reports, severed dogfood loop, no mic/image) are all closed.

**(e) Operable-from-the-phone in the same practical way?** — **YES, with the standard Rung-0 caveats.**
*Proven internally* (code + 40/40 tests + both-mode builds + credential-free selftests/dry-runs): every UI
surface, the data-layer semantics of the whole loop, the copy/export formatters, the Storage-gate seams, and
the operator CLI shapes. *Owed on-device* (Pete's dogfood): pixel-level keyboard clearance, live mic, local
image render, non-empty logs on a real doc, and the `--build`→phone→Works round trip. *Blocked-on-Brandon*:
enabling Firestore/Anonymous-Auth + Storage + granting ADC/IAM — after which the live loop runs with **zero
code change**.

### Gaps the validator found (implementer missed) — all MINOR, none blocking

- **G1 — anti-leak scan coverage gap (recommend fix).** `harness/harness_antileak_scan.sh`'s file set includes
  `scripts/stocktrack_chat.js` but **omits `scripts/stocktrack_workflow_status.js`** (the new Chunk-6 publisher)
  and `scripts/stocktrack_ship.sh`. The scan PASSES, but it does not cover the newest operator script. The
  validator independently grepped `stocktrack_workflow_status.js` — it is **clean** (config + guard only). *Fix:*
  add `stocktrack_workflow_status.js` to `default_framework_files`, and either scan `stocktrack_ship.sh` or add
  it to `is_excluded()` with the same documented rationale as `bp_guard.js`. Harness-first: the mechanical gate
  should cover every operator script so a future edit can't leak un-scanned.
  **→ RESOLVED:** `stocktrack_workflow_status.js` added to `default_framework_files` (now scanned + clean);
  `stocktrack_ship.sh` added to `is_excluded()` (it names reference literals as a ship-abort guardrail, same as
  `bp_guard.js`). Scan re-run: **PASS / 40 files**.
- **G2 — floating-entry badge omits ready-to-test.** `_HarnessEntryBadge` counts open reports only
  (`status!=fixed/wont_fix && !manualResolved`); dogfood check-items (`status:'fixed'` + `awaitingVerification`)
  are excluded, so they don't surface on the puck badge, though the §6 checklist says the badge merges "open
  reports / ready-to-test items / unread chat." Chunk 1 deferred this and Chunk 3 didn't circle back. The
  command-center **tile** does show the ready-to-test count, so the signal isn't lost — only the glanceable puck
  badge is incomplete. *Fix (cheap):* fold `awaitingVerification` (and later chat-unread) into the badge count.
  **→ RESOLVED:** extracted a pure `harnessEntryBadgeCount(reports)` (= open + ready-to-test, no overlap) into
  `harness_providers.dart`; the puck badge now uses it. Unit-tested (`harnessEntryBadgeCount` merges 2 open + 1
  ready → 3; zero when nothing needs the owner).
- **G3 — screenshot Storage path is a hardcoded literal.** `screenshot_upload_service.dart` builds
  `'stockIssueReports/$uid/…'` as a literal rather than from `HarnessConfig.reportsCollection` (the chat upload
  path correctly uses `HarnessConfig.chatRoot`). It's Stock-Track's own name (no crossover, scan-clean), but a
  future 3rd app reusing the file verbatim would write screenshots under `stockIssueReports` regardless of its
  config — a small deviation from the doc's "paths from `HarnessConfig.reportsCollection`" claim.
  **→ RESOLVED:** `screenshot_upload_service.dart` now builds the path from `HarnessConfig.reportsCollection`
  (matches the chat upload path). No framework module hardcodes an app-specific collection name.
- **G4 — chat-media Storage rule not present.** `storage.rules` scopes `stockIssueReports/{uid}/**` but has **no**
  rule for `orchestratorChat/{uid}/media/**` (the parity map's Chunk-5 touch-list named both). Consistent with
  Storage being off + chat-image being a fast-follow, but it means enabling Storage + flipping the flag alone
  won't make chat image upload work — the media rule must be added too. Belongs on the "what enabling Storage
  requires" checklist.
  **→ RESOLVED:** added an owner-scoped `match /orchestratorChat/{uid}/media/{fileName}` rule
  (`request.auth.uid == uid`) to `storage.rules`, committed READY (Storage stays off until Brandon enables it).
  Enabling Storage + flipping `kHarnessStorageEnabled` is now sufficient for chat-image upload — no default-deny.
- **G5 — claim-precision nit (not a defect).** The Chunk-3 doc says the canonical `reopenedFields()` helper is
  used by "the toggle, the dropdown, and the sheet." The toggle (`setManualResolved`) and the sheet
  (`markStillBroken`) do route through the canonical helpers; the **dropdown** (`updateStatus`) uses a lighter
  inline write (`{status, manualResolved:false}`) that deliberately does NOT flag the orchestrator. The reopen
  bug IS fixed on all paths — the claim is just slightly broader than the code.
  **→ RESOLVED:** `updateStatus` (Firebase + Mock) now routes the reopen (non-resolved) branch through the
  canonical `reopenedFields()` field-set (keeping the owner's chosen status), so the dropdown, the toggle, and
  the sheet all share ONE reopen definition — the claim now matches the code. Unit-tested (dropdown reopen now
  clears the tick + `verifiedByUser` and flags the orchestrator).

**None of G1–G5 blocks the loop or fails a MUST-HAVE.** They are refinements in the ADAPT/DEFER band plus one
harness-hygiene fix (G1) worth doing before the next reuse.

---

## 5. Gap resolution (G1–G5 closed by the implementation lane, 2026-07-01)

All five gaps fixed surgically, guardrails held, gates re-run green.

| Gap | Fix (file) | Proof |
|---|---|---|
| **G1** scan coverage | `harness/harness_antileak_scan.sh` — add `stocktrack_workflow_status.js` to the set; exclude `stocktrack_ship.sh` (ship guardrail) | `--list` shows the publisher in scope; scan **PASS / 40 files** |
| **G2** merged badge | `harness_providers.dart` (`harnessEntryBadgeCount`) + `harness_overlay.dart` badge | unit test: 2 open + 1 ready → 3; 0 when idle |
| **G3** reuse-boundary | `screenshot_upload_service.dart` → path from `HarnessConfig.reportsCollection` | analyze clean; matches chat upload path |
| **G4** Storage prep | `storage.rules` → owner-scoped `orchestratorChat/{uid}/media/**` rule | committed ready (Storage still off) |
| **G5** canonical reopen | `report_repository.dart` `updateStatus` (Firebase + Mock) → `reopenedFields()` | unit test: dropdown reopen clears tick + verify flags + flags orch |

**Post-fix gate results:** `flutter analyze` **0 issues** · `flutter test` **42/42** · `harness_antileak_scan.sh`
**PASS / 40 files** · `stocktrack_chat.js --selftest` **6/6** · `stocktrack_workflow_status.js --selftest`
**7/7** · `flutter build apk --debug` **√ both firebase + mock** (mode flipped, built, reverted clean).

**Behaviour note (G5):** routing the dropdown reopen through `reopenedFields()` means picking a non-resolved
status now also flags the orchestrator + clears `verifiedByUser`/`awaitingVerification` (canonical reopen
semantics) — a small, intentional consistency improvement over the previous tick-only clear; reopen still works.

**FINAL: PASS-WITH-NOTES.** The Stock-Track owner/operator harness is a faithful, config-driven,
provably-separated re-instantiation of the reference harness. Every MUST-HAVE is implemented and independently
verified; every adapt/defer is conscious and reasoned; separation is clean and tool-checked. The remaining work
is the expected on-device dogfood (Pete) + backend/Storage/ADC enablement (Brandon), after which the live loop
runs unchanged — plus the five minor refinements above.
