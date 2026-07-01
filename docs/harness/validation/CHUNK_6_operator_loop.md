# Chunk 6 — Off-device Operator Loop + workflowContext Publisher

**Parity map:** `docs/harness/HARNESS_PARITY_MAP.md` §5 Chunk 6 (+ §4 gap #6 operator report CLI, gap #13 dangling `workflowContext`).
**Date:** 2026-07-01 · **Lane:** Stock-Track harness-parity implementation (Package B).
**Result:** PASS (code + pure-logic) — `flutter analyze` 0 issues · `flutter test` 40/40 · `stocktrack_chat.js --selftest` 6/6 · `stocktrack_workflow_status.js --selftest` 7/7 · `flutter build apk --debug` OK (both modes) · antileak PASS (39 files). **LIVE round-trip DEFERRED-on-Brandon** (IAM + ADC).

---

## What this chunk proves (+ what is blocked-on-Brandon)

The orchestrator can now **close what the owner opened** and **publish state** — all
off-device, pinned to easy-stock-track via ADC (never a key/token):

- read/pick/close a report (`--report` / `--logs` / `--resolve` / `--comment`), list
  with status (`--reports`), download Storage screenshots (`--screenshots`);
- a `system/workflowContext` **publisher** (closes the dangling wire the dashboard
  reads);
- a non-destructive `--dry-run` preview on every write;
- in-app: **poke-with-note** dialog + a **"N agents engaged"** header signal.

**The LIVE two-way round-trip** (real reads/writes against easy-stock-track) is
**BLOCKED on Brandon's IAM grant + `gcloud auth application-default login`**. The code
+ `--selftest` + `--dry-run` are complete and credential-free; nothing is faked and no
key is used. When Brandon grants ADC, the loop runs with zero code change.

## Reference PATTERN (abstract, app-agnostic)

- **Operator-side queue CLI** — list/read/pick reports, download screenshots + logs,
  transition status. This is *how reports land for the operator*; the loop can't run
  outside the app without it.
- **Orchestrator-side resolve/comment** so the operator can *close* the loop the owner
  opened — "owner files → orchestrator fixes → owner verifies" must be bidirectional.
- **`workflowContext` publisher** — a minimal `{updatedAt, build, lane, state,
  waitingOnOwner}` projection the in-app dashboard reads (never a dead empty doc).
- **`--dry-run`** non-destructive preview; **poke consumer** — a reader/wake loop over
  `system/orchestratorPoke` (the message IS the poke).
- **Strict separation** — ADC/permissions (not a shared key), explicit projectId pin, a
  runtime BP-abort guard, a mechanical anti-leak scan.

## Stock-Track IMPLEMENTED behavior (file + what)

| Pattern | File | What |
|---|---|---|
| Operator report ops | `scripts/stocktrack_chat.js` | `--report <id>` (full pick), `--logs <id>` (device-log tail), `--resolve <id>` (canonical resolve + poke), `--comment <id> "text"` (arrayUnion + flag), `--screenshots <id> [dir]` (Admin-SDK Storage download; reports local-only when Storage was off). |
| Non-destructive preview | `scripts/stocktrack_chat.js` | `--dry-run` on send/build/resolve/comment — prints payload + target, writes nothing, needs no creds. |
| Poke consumer | `scripts/stocktrack_chat.js` (header doc) | documents the read-poke→`--read` wake loop (cron/Monitor). |
| workflowContext publisher | `scripts/stocktrack_workflow_status.js` (**new**) | `--publish [--build --lane --state --waiting]` → `system/workflowContext` (+ poke); `--read`; `--dry-run`; `--selftest`; ADC + projectId pin + BP-guard. |
| Agent-status seam | `chat/services/chat_repository.dart` | `readAgentStatus()` (Firebase reads `system/agentStatus`; Mock seeds `{engaged:1}`). |
| Providers | `services/harness_providers.dart` | `agentStatusProvider` + pure `agentsEngagedCount()` (reads `engaged` int or `agents` list length). |
| Poke-with-note + engaged badge | `report_queue/screens/report_queue_screen.dart` | poke dialog (optional note → `pokeOrchestrator(note:)`); "N engaged" header chip when >0. |

## Acceptance results (command output)

```
flutter analyze                          → No issues found!
flutter test                             → All tests passed!  (40/40)
  new (Chunk 6): agentsEngagedCount reads engaged int / agents list / null→0.
stocktrack_chat.js --selftest            → RESULT: PASS | selftest 6/6
stocktrack_chat.js --send "…" --dry-run   → DRY-RUN preview → orchestratorChat/<uid>/messages (nothing written)
stocktrack_chat.js --resolve rep --dry-run→ DRY-RUN preview → stockIssueReports/rep {status:fixed,manualResolved,awaitingVerification:false,resolvedBy:orchestrator}
stocktrack_workflow_status.js --selftest → RESULT: PASS | selftest 7/7
stocktrack_workflow_status.js --publish … --dry-run → DRY-RUN preview → system/workflowContext {build,lane,state,waitingOnOwner,updatedAt}
flutter build apk --debug                → √ Built (firebase mode) + √ Built (mock mode, reverted)
harness/harness_antileak_scan.sh         → ANTILEAK RESULT: PASS | 0 Blueprint literals | 39 files
```

Acceptance bullets (parity map §5 Chunk 6):
- [~] orchestrator `--resolve <id>` closes an owner report → owner sees it resolved —
  **code + dry-run proven; LIVE write BLOCKED on Brandon's ADC** (deferred, not faked).
- [x] `--dry-run` previews without writing (credential-free).
- [x] the dashboard reads a published projection (publisher writes it; Chunk-4 reader
  consumes it; mock shows a seeded demo).
- [x] a poke wakes the operator loop — the consumer loop is documented (read
  `orchestratorPoke.pokedAt` → `--read`); the write side ships in the app.

## Anti-leak / separation

- `harness/harness_antileak_scan.sh` → **PASS** (0 Blueprint literals, 39 files incl.
  the new publisher). Both scripts reuse `bp_guard.js` + ADC + an explicit
  `easy-stock-track` projectId pin. **No key/token; ADC-permissions only.**
- `--screenshots` uses the Admin SDK Storage bucket pinned to
  `easy-stock-track.firebasestorage.app` (selftest asserts the pin).

## GENERIC vs STOCK-TRACK-SPECIFIC (reuse boundary)

- **GENERIC framework (reusable):** the CLI command *shapes* (read/pick/resolve/comment/
  screenshots/dry-run), the publisher's pure `buildProjection`, the `readAgentStatus`
  seam + `agentsEngagedCount`, the poke-with-note dialog, the engaged badge. Logic is
  identity-free.
- **STOCK-TRACK-SPECIFIC (config only):** every collection/doc/bucket/projectId is
  resolved from `harness/project.config.json` (`easy-stock-track`, `stockIssueReports`,
  `system/workflowContext`, `system/agentStatus`) — no literal in the logic. The
  BP-abort guard is the ONE file that names BP literals (to block them) and is
  scan-excluded by design. A future 3rd app points the same scripts at its own config.

## Deferred (intentional / blocked-on-owner)

- **LIVE two-way round-trip** (real reads/writes, screenshot download, publish) — BLOCKED
  on Brandon's IAM grant + `gcloud auth application-default login`. Code complete; runs
  unchanged once ADC is granted.
- **LIVE Storage screenshot download** — additionally gated on Storage-enable (Chunk 5).
- FCM push / latency carry — deferred (poke + in-app badge carry the wake for now).
- A long-running poke-consumer daemon — documented as a cron/Monitor recipe rather than
  a shipped daemon (Rung-0 keeps it a recipe).
