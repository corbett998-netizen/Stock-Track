# Chunk 4 — Chat Operator Surface (copy-out, export, dashboard)

**Parity map:** `docs/harness/HARNESS_PARITY_MAP.md` §5 Chunk 4 (+ §4 gap #7 "chat operator surface absent").
**Date:** 2026-07-01 · **Lane:** Stock-Track harness-parity implementation (Package B).
**Result:** PASS — `flutter analyze` 0 issues · `flutter test` 33/33 · `flutter build apk --debug` OK (both modes) · antileak PASS (37 files).

---

## What this chunk proves

The daily "run the build from your phone" controls are present:

- copy a single reply (per-bubble copy icon);
- long-press to multi-select, then bulk **Copy (N)**;
- copy a **paste-ready ChatGPT context** — FULL (workflow state + whole thread) or
  RECENT (only since the last export), plus a raw **Copy conversation**;
- a floating **new-messages pill** that does not shift the composer;
- a read-only **workflow dashboard** (empty-but-honest when nothing is published,
  with a stale banner when old).

## Reference PATTERN (abstract, app-agnostic)

- **Copy-out: per-bubble copy + multi-select bulk copy + copy-a-work-area block** —
  copying orchestrator replies out to paste into an external LLM is the owner's
  single most-used daily lever.
- **ChatGPT-context export (full + recent-since-last-export) as paste-ready frames** —
  hand a curated, paste-ready context to an external model.
- **Workflow dashboard sheet** (read-only "state + evidence + waiting-on-owner", with
  stale/fresh banners) — the operator's at-a-glance control panel; stale must loudly
  read as stale.
- **Floating "new messages" pill + multi-frame autoscroll** — opens pinned to newest,
  never yanks the view while reading history, lands at the true bottom even with
  variable-height/image bubbles.

## Stock-Track IMPLEMENTED behavior (file + what)

| Pattern | File | What |
|---|---|---|
| Paste-ready frames (pure) | `chat/services/chat_export.dart` (**new**) | `oneBubble` / `threadBlock` / `fullFrame` / `recentFrame` / `contextHeader`; takes thread + projectName + ownerRole + build + optional context as plain values; degrades gracefully with no context. |
| Per-bubble copy + selection | `chat/widgets/chat_bubble.dart` | copy icon; long-press enters multi-select, tap toggles; selected highlight + check; plain `Text` (not `SelectableText`) so long-press doesn't fight OS text-handles. |
| Selection AppBar | `chat/widgets/chat_selection_bar.dart` (**new**) | "N selected" + `Copy (N)` + clear. |
| Header command buttons | `chat/widgets/chat_header.dart` (**new**) | Dashboard button + a copy menu (FULL / RECENT / conversation). |
| Floating pill | `chat/widgets/chat_new_messages_pill.dart` (**new**) | floating `Positioned` pill over the list (was an inline `TextButton` consuming layout). |
| Dashboard sheet | `chat/widgets/workflow_dashboard_sheet.dart` (**new**) | reads `workflowContextProvider`; empty-but-honest state; stale banner (>6h). |
| Read seam | `chat/services/chat_repository.dart` | `readWorkflowContext()` on the interface + Firebase (reads `system/workflowContext`, null on absent/offline) + Mock (seeded demo projection). |
| Provider | `services/harness_providers.dart` | `workflowContextProvider`. |
| Screen wiring | `chat/screens/orchestrator_chat_screen.dart` | selection state; selection-vs-normal AppBar swap; floating pill in a `Stack`; **3-frame autoscroll**; export/copy handlers with a `SharedPreferences` last-export cursor for RECENT. |

## Acceptance results (command output)

```
flutter analyze            → No issues found! (ran in 2.0s)
flutter test               → All tests passed!  (33/33)
  new (Chunk 4): ChatExport — oneBubble labels; threadBlock; fullFrame preamble+
  build+context+thread; contextHeader degrades empty; recentFrame after-cursor +
  empty-honest.
flutter build apk --debug  → √ Built app-debug.apk   (firebase mode)
flutter build apk --debug  → √ Built app-debug.apk   (mock mode, then reverted)
harness/harness_antileak_scan.sh → ANTILEAK RESULT: PASS | 0 Blueprint literals | 37 files
```

Acceptance bullets (parity map §5 Chunk 4):
- [x] copy a single reply (per-bubble copy icon → `oneBubble`);
- [x] multi-select and bulk-copy (`Copy (N)` → `threadBlock` of the selection);
- [x] copy a full paste-ready context block (`fullFrame`, degrades with no context);
- [x] the new-messages pill floats without shifting the composer (moved off the
  `Column` into a `Stack` `Positioned`);
- [x] the dashboard opens (empty-but-honest if nothing published; stale banner).

> The copy/export FORMATTERS are unit-proven; the clipboard/gesture/UI wiring is
> compile-proven both modes + is an on-device dogfood check.

## Anti-leak / separation

- `harness/harness_antileak_scan.sh` → **PASS** (0 Blueprint literals, 37 files incl.
  5 new chat files).
- No backend-auth work; the dashboard read is the existing chat repository seam.

## GENERIC vs STOCK-TRACK-SPECIFIC (reuse boundary)

- **GENERIC framework (reusable, no app identity):** `chat_export.dart`,
  `chat_selection_bar.dart`, `chat_header.dart`, `chat_new_messages_pill.dart`,
  `workflow_dashboard_sheet.dart`, the bubble copy/selection support, and the screen
  wiring. Identity flows in as plain values: `HarnessConfig.projectName` /
  `HarnessConfig.ownerRole` (config) are *passed to* the pure formatter — the
  formatter itself hardcodes nothing. Theme via the `HarnessTheme` seam.
- **STOCK-TRACK-SPECIFIC (wiring/config only):** the workflow-context doc path is
  `HarnessConfig.workflowContextDoc` (config); the mock demo projection is demo
  content in the mock repository (wiring layer), not the framework. A future 3rd app
  reuses all five widgets + the formatter verbatim with its own config.

## Deferred (intentional, per parity map)

- Structured two-dimension tagging + per-stream colours (lightweight-first).
- Message-engine self-heal / seen-cursor badge; push overlay / latency carry;
  `PopScope` back-handling.
- Image/file attach in chat + mic → **Chunk 5**.
- The LIVE `system/workflowContext` publisher (operator side) → **Chunk 6**; until
  then firebase mode reads "nothing published" (honest), mock shows a seeded demo.
