# Chunk 2 — Logs & Context (the missing diagnostics half)

**Parity map:** `docs/harness/HARNESS_PARITY_MAP.md` §5 Chunk 2 (+ §4 gap #4, #10, #11).
**Date:** 2026-07-01 · **Lane:** Stock-Track harness-parity implementation (Package A).
**Result:** PASS — `flutter analyze` 0 issues · `flutter test` 20/20 · `flutter build apk --debug` OK (both modes) · antileak PASS.

---

## What this chunk proves

Reports now carry real evidence, and "which build / backend / user" is answerable:

- a filed report carries a non-empty `logsInline` (device-log tail), a
  `deviceInfo.platform`, and an `appBuild` string;
- the report detail shows an expandable **DEVICE LOG TAIL** + a build/platform line;
- the command center shows the running app build.

This restores **logs-first, no-guessing** — the single biggest harness power.

---

## Reference PATTERN (abstract, app-agnostic)

- **In-app logger + ring buffer + `snapshot(percent)`.** A master gate + a few
  generic categories + a bounded in-memory ring buffer with a `snapshot(percent)`
  slice, dead-code-eliminated in release. The source of the device logs a report
  carries.
- **`logsInline` on the report + a DEVICE LOG TAIL view.** A report carries the
  recent device-log ring buffer (a byte-clipped inline tail), rendered as an
  expandable tail in the report detail so the operator diagnoses from evidence,
  in-app.
- **Rich report metadata.** `deviceInfo/platform` + build/version stamped on every
  report; the same build shown in the owner context surface. "Which build produced
  this bug / is the owner on the fix?" must be answerable — the dogfood loop depends
  on it.

## Stock-Track IMPLEMENTED behavior (file + what)

| Pattern | File | What |
|---|---|---|
| Logger + ring buffer + snapshot | `lib/core/utils/harness_logger.dart` (**new**) | `HarnessLogger` singleton: `!kReleaseMode` master gate; 3 generic categories (chat/report/system); bounded 600-line ring buffer; `snapshot(percent)`; `inlineTail({maxBytes})` (byte-capped, newline-aligned). |
| Build resolver | `lib/core/utils/harness_app_build.dart` (**new**) | `resolveHarnessAppBuild()` → `"<version> (<build>)"` via `package_info_plus`; degrades to `'unknown'` off-platform (never throws). |
| logsInline + deviceInfo + appBuild on the doc | `report_queue/services/report_repository.dart` | `fileReport` (Firebase + Mock) stamps `logsInline` (`inlineTail()`), `deviceInfo:{platform: defaultTargetPlatform.name}`, `appBuild`. |
| Logger wired into call sites | `chat/controllers/chat_compose_controller.dart` (send), `chat/controllers/chat_message_controller.dart` (receive), `report_repository.dart` (file + poke) | chat send/queued/fail, receive new-msg, report file/filed, poke. |
| Model reads the fields | `report_queue/models/report.dart` | `logsInline`, `deviceInfo` (+ `platform` getter), `appBuild`; tolerant of absence; carried through the mock `_copy`. |
| DEVICE LOG TAIL view | `report_queue/widgets/report_detail.dart` | Expandable "DEVICE LOG TAIL" (scrollable monospace `SelectableText`) + a build/platform meta line; shown only when present. |
| Build on the command center | `harness_home_screen.dart` + `services/harness_providers.dart` | `harnessAppBuildProvider`; status card shows `App build`. |
| Package | `pubspec.yaml` | Added `package_info_plus`. |

## Acceptance results (command output)

```
flutter analyze            → No issues found! (ran in 8.9s)
flutter test               → All tests passed!  (20/20)
  new: HarnessLogger — records/snapshot ordering; snapshot(percent) slice;
       inlineTail byte-cap + newline-boundary; empty-buffer empty-string;
       Report.fromMap reads logsInline / deviceInfo.platform / appBuild.
flutter build apk --debug  → √ Built app-debug.apk   (firebase mode)
flutter build apk --debug  → √ Built app-debug.apk   (mock mode, then reverted)
harness/harness_antileak_scan.sh → ANTILEAK RESULT: PASS | 0 Blueprint literals | 31 files
```

Acceptance bullets (parity map §5 Chunk 2):
- [x] a filed report carries a non-empty `logsInline` (`fileReport` stamps
  `harnessLog.inlineTail()`; the capture path logs before the snapshot so it is
  never empty in real use — unit-proven that inlineTail returns content);
- [x] `deviceInfo.platform` stamped (`defaultTargetPlatform.name`);
- [x] a build string stamped (`resolveHarnessAppBuild()`);
- [x] the report detail shows the log tail (expandable DEVICE LOG TAIL);
- [x] the command center shows the build (`App build` row).

> The end-to-end "non-empty logs on a REAL Firestore doc" is proven on-device/dogfood
> (needs the live backend); the model read + the tail/clip logic are unit-proven and
> the build compiles both modes.

## Anti-leak / separation

- `harness/harness_antileak_scan.sh` → **PASS** (0 Blueprint literals, 31 files).
- Backend access unchanged (ADC/permissions only in the CLI; no key/token added).

## GENERIC vs STOCK-TRACK-SPECIFIC (reuse boundary)

- **GENERIC framework (reusable, no app identity):** `harness_logger.dart` and
  `harness_app_build.dart` are fully app-agnostic — no project id / collection /
  owner value; categories are harness-generic (chat/report/system); the build
  resolver reads whatever host app it is compiled into. The model fields
  (`logsInline`/`deviceInfo`/`appBuild`), the DEVICE LOG TAIL widget, the
  `harnessAppBuildProvider`, and the logger call-site wiring are all generic.
- **STOCK-TRACK-SPECIFIC (wiring/config only):** none introduced in this chunk. The
  report collection name is still resolved via `HarnessConfig.reportsCollection`
  (config), and the Firestore write path is the existing Firebase repository seam
  chosen in `main.dart`. A future 3rd app gets logs-on-reports by reusing these
  files verbatim + its own `project.config.json`.

## Deferred (intentional, per parity map)

- Full-buffer **Storage** upload of logs (fast-follow after the inline tail).
- On-disk log file + operator capture scripts.
- `logPercent` selector in the capture UI (ship full-buffer/tail first).
- `system/workflowContext` in-app dashboard richness.
