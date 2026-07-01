# Chunk 3 — Close the Dogfood Verify Loop

**Parity map:** `docs/harness/HARNESS_PARITY_MAP.md` §5 Chunk 3 (+ §4 CRITICAL gaps #2, #5; §4 gap #3 reopen bug).
**Date:** 2026-07-01 · **Lane:** Stock-Track harness-parity implementation (Package A).
**Result:** PASS — `flutter analyze` 0 issues · `flutter test` 27/27 · `stocktrack_chat.js --selftest` 5/5 · `flutter build apk --debug` OK (both modes) · antileak PASS (32 files).

---

## What this chunk proves

The owner-verify loop ("ship → owner tests on his phone → Works/Still-broken") now
closes on-device — the half that was severed at the data layer:

- an operator "announce build" check-item now surfaces in-app under **Ready to test**;
- **Works** resolves it (leaves the list, reads resolved, stamps verified-by-user);
- **Still broken** reopens it (status `new`, flags the orchestrator, stays a live
  check-item);
- a **Resolved-then-dropdown-reopen** now actually reopens (the §4 reopen bug fix);
- the queue + the sheet write through **one canonical resolved/reopened field-set**,
  so the two live surfaces can't drift.

---

## Reference PATTERN (abstract, app-agnostic)

- **Operator "announce a build"** atomically posts a build message, auto-creates a
  check-item (`status:fixed, awaitingVerification:true, backfilled:true`), and
  signals the device. Every shipped thing-to-check becomes a verify item.
- **In-app "Ready to test" surface** — a count-badged entry → a checklist listing
  each check-item with the screen to test on, and per-item **Works** / **Still
  broken**. Without a consumption surface the check-items are dead writes and the
  "owner tests from his phone" premise fails.
- **Works → canonical resolved write** (clears `awaitingVerification`, stamps
  verified-by-user). **Still broken → reopen write** (status `new`, flag, keep
  `awaitingVerification`). It's a *gate*, not an accept-only rubber stamp.
- **One canonical resolved/reopened field-set** shared by the queue and the dogfood
  surface, so two live surfaces over the same docs never drift.
- **Correct reopen path** that clears the manual-resolved flag, so the owner can
  override the agent (including reopening).

## Stock-Track IMPLEMENTED behavior (file + what)

| Pattern | File | What |
|---|---|---|
| Model reads verify fields | `report_queue/models/report.dart` | reads `awaitingVerification`, `region`, `verifiedByUser`; adds a `testOnLabel` (region → area fallback); carried through the mock `_copy`. |
| Canonical resolved/reopened helpers | `report_queue/services/report_repository.dart` | `resolvedFields({verifiedByUser})` + `reopenedFields({keepAwaitingVerification})` — ONE definition each, used by the toggle, the dropdown, and the sheet. |
| Works / Still-broken routing | `report_repository.dart` | `markVerifiedWorks` → `resolvedFields(verifiedByUser:true)`; `markStillBroken` → `reopenedFields(keepAwaitingVerification:true)`; both in the interface + Firebase + Mock impls. |
| Reopen bug fix | `report_repository.dart` (Firebase + Mock `updateStatus`) | a non-resolved dropdown status now also writes `manualResolved:false`, so `effectiveStatus` no longer stays `'fixed'`. |
| Ready-to-test filter bucket | `report_queue/models/report_filter.dart` | new `readyToTest` (`awaitingVerification==true`); `resolved` now excludes still-awaiting items. |
| Command-center count + tile | `harness_home_screen.dart` | counts `awaitingVerification` **separately** (check-items are status `fixed`, excluded from open-count); a "Ready to test" tile with an `N` badge opens the sheet. |
| Ready-to-test sheet | `dev/dogfood/ready_to_test_sheet.dart` (**new**) | checklist bottom sheet: per-item title + "Test on: `<region>`" + build + **Works** / **Still broken**; live-driven, per-item busy state, honest empty state. |
| Build check-item flag | `scripts/stocktrack_chat.js` | `cmdBuild` adds `backfilled:true`. |
| Mock seed | `report_repository.dart` | seeds one `awaitingVerification` check-item so the surface is usable in mock mode. |

## Acceptance results (command output)

```
flutter analyze                 → No issues found! (ran in 3.3s)
flutter test                    → All tests passed!  (27/27)
  new (Chunk 3): readyToTest filter; model reads awaitingVerification/region/
  verifiedByUser + testOnLabel; Mock loop — seeds a check-item, Works→resolved,
  Still-broken→reopen, and the Resolved-then-dropdown-reopen bug fix.
stocktrack_chat.js --selftest   → STOCKTRACK-CHAT RESULT: PASS | selftest 5/5
flutter build apk --debug       → √ Built app-debug.apk  (firebase mode)
flutter build apk --debug       → √ Built app-debug.apk  (mock mode, then reverted)
harness/harness_antileak_scan.sh → ANTILEAK RESULT: PASS | 0 Blueprint literals | 32 files
```

Acceptance bullets (parity map §5 Chunk 3):
- [x] `--build` makes an item appear under "Ready to test" (`backfilled:true` +
  `awaitingVerification:true` written by `cmdBuild`; model reads it; home counts it;
  sheet lists it — **mock-loop unit-proven**; live `--build` is an on-device dogfood step);
- [x] **Works** removes it and it reads resolved in the queue (unit-proven);
- [x] **Still broken** reopens it (status `new`, flagged) and it leaves the ready list (unit-proven);
- [x] Resolved-then-dropdown-reopen now actually reopens (unit-proven).

> The full off-device→on-device round trip (`stocktrack_chat.js --build` writing to
> live Firestore → item on the phone → Works closes it → operator sees it resolved)
> is the on-device/dogfood proof; the data-layer semantics + both modes' builds are
> proven here.

## Anti-leak / separation

- `harness/harness_antileak_scan.sh` → **PASS** (0 Blueprint literals, 32 files incl.
  the new sheet).
- `scripts/stocktrack_chat.js` change is client-metadata only (`backfilled:true`);
  **no backend auth work** — still ADC/permissions, no key/token.

## GENERIC vs STOCK-TRACK-SPECIFIC (reuse boundary)

- **GENERIC framework (reusable, no app identity):** `ready_to_test_sheet.dart` (reads
  the generic owner-reports stream + the repository's canonical writes; theme via the
  `HarnessTheme` seam), the `readyToTest` filter, the model verify-fields, the
  canonical `resolvedFields`/`reopenedFields` helpers, and the reopen-bug fix. None
  hardcode a project id / collection / owner value.
- **STOCK-TRACK-SPECIFIC (wiring/config only):** the collection written by
  `stocktrack_chat.js` is resolved from `harness/project.config.json`
  (`collections.reports`), not a literal; the mock seed's `region:'Inventory'` is
  demo content in the mock repository (the wiring layer), not the framework. A future
  3rd app reuses the sheet + helpers verbatim and points `--build` at its own config.

## Deferred (intentional, per parity map)

- Workflow **grouping** in the sheet (single flat list first).
- **Accept-all / View-in-panel** per group.
- Still-broken → auto-open a **linked sub-report** with mic + draft frozen to the
  screen (plain reopen first; sub-reports/mic are later chunks).
- **Route capture** to populate `region` automatically (falls back to `area` today).
- FCM push on `--build` (poke + in-app badge carry it for now).
