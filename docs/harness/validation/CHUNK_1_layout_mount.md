# Chunk 1 — Layout + Mount (reachable & usable)

**Parity map:** `docs/harness/HARNESS_PARITY_MAP.md` §5 Chunk 1 + §7 (chat-input fix).
**Date:** 2026-07-01 · **Lane:** Stock-Track harness-parity implementation (Package A).
**Result:** PASS — `flutter analyze` 0 issues · `flutter test` 15/15 · `flutter build apk --debug` OK (both modes) · antileak PASS.

---

## What this chunk proves

The two most visible defects the owner reported are fixed, and the floating entry is
now un-hideable:

- the chat input no longer hides behind the Android nav bar / keyboard;
- the floating dev-tool entry floats above **every** route (was coverable);
- the entry can't be parked under the nav bar and its position survives a restart;
- a glanceable "what needs me" count badge rides on the entry.

---

## Reference PATTERN (abstract, app-agnostic)

- **Overlay mounted ABOVE the Navigator.** The floating dev entry is injected at the
  app's *builder* seam, wrapping the Navigator's output, so it floats above every
  route and can never be covered by page content or a pushed full-screen route.
  Because it sits above the Navigator it has **no Overlay ancestor**, so it pushes
  its routes through a shared navigator key and avoids Overlay-dependent affordances
  (Tooltip / Draggable-feedback) in the seam layer itself.
- **Keyboard/nav-safe composer.** A chat Scaffold resizes for the keyboard and wraps
  its body in a bottom `SafeArea`, so the input always rides clear of the nav bar
  (keyboard closed) and snug above the keyboard (open, where the bottom inset
  auto-collapses). The same bottom-`SafeArea` treatment protects any other
  input-bearing surface (report queue comment composer, capture note).
- **Draggable, repositionable entry with persistence + nav clearance.** The entry is
  a draggable puck whose position is stored as a screen *fraction* and restored
  across restarts/rotation; the drag clamp bakes in the system nav/gesture inset so
  it can never settle under the bar.
- **Glanceable count badge.** The entry surfaces a merged "needs me" count without
  opening anything.

## Stock-Track IMPLEMENTED behavior (file + what)

| Pattern | File | What changed |
|---|---|---|
| Overlay above Navigator | `lib/app.dart` | `HarnessOverlay` moved from `home:` into `MaterialApp(builder:)`; `home:` is now the bare `AppShell`. Added a shared `navigatorKey` on `MaterialApp`, passed to the overlay. |
| Push from above the Navigator | `lib/features/dev/harness_overlay.dart` | Entry pushes the command center via `navigatorKey.currentState` (falls back to `Navigator.of(context)` when null, e.g. isolated tests). |
| No Overlay in the seam | `lib/features/dev/harness_overlay.dart` | Replaced `Draggable` (needs an Overlay for feedback) with a `GestureDetector` pan; replaced the FAB `Tooltip` (needs an Overlay) with a `Semantics` label. |
| Nav-inset drag clamp | `lib/features/dev/harness_overlay.dart` | Clamp bottom = `size.height − padding.bottom − navClearance − fabSize`; always re-clamped each build so a rotation/smaller screen can't strand the puck. |
| Fractional position store | `lib/features/dev/harness_overlay.dart` | Position saved to `SharedPreferences` as `(fx,fy)` fractions; restored in `initState`. |
| Count badge | `lib/features/dev/harness_overlay.dart` | `_HarnessEntryBadge` (a `Consumer`) reads the owner reports stream and shows the open-report count; renders nothing when zero. |
| Keyboard/nav-safe chat | `lib/features/dev/chat/screens/orchestrator_chat_screen.dart` | `resizeToAvoidBottomInset: true` + body wrapped in `SafeArea(top:false)` (§7 verbatim). |
| Same treatment, other input surfaces (§7) | `report_queue/screens/report_queue_screen.dart`, `report_capture/screens/report_capture_screen.dart` | Bodies wrapped in `SafeArea(top:false)` + `resizeToAvoidBottomInset:true`. |
| Package | `pubspec.yaml` | Added `shared_preferences` (position store). |

## Acceptance results (command output)

```
flutter analyze            → No issues found! (ran in 2.0s)
flutter test               → All tests passed!  (15/15)
  incl. test/harness_overlay_test.dart:
    - floating entry is visible on the shell
    - entry floats ABOVE a pushed route (command center)   ← core Chunk-1 acceptance
flutter build apk --debug  → √ Built build/app/outputs/flutter-apk/app-debug.apk   (firebase mode)
flutter build apk --debug  → √ Built …app-debug.apk                                 (mock mode, then reverted)
harness/harness_antileak_scan.sh → ANTILEAK RESULT: PASS | 0 Blueprint literals | 31 files scanned
```

Acceptance bullets (parity map §5 Chunk 1):
- [x] keyboard open → composer sits directly above it (`resizeToAvoidBottomInset` + bottom `SafeArea`);
- [x] keyboard closed → composer clears the nav bar (bottom `SafeArea` pads `viewPadding.bottom`);
- [x] pushing a full-screen route still shows the floating entry (**widget-test proven**);
- [x] the entry can't be parked under the nav bar (drag clamp folds in nav/gesture inset);
- [x] its position survives a restart (`SharedPreferences` fractional store).

> Keyboard/nav-bar *pixel* clearance is a device behaviour proven on the build +
> on-device dogfood (not assertable in a widget test); the mount-above-Navigator
> acceptance IS widget-test proven.

## Anti-leak / separation

- `harness/harness_antileak_scan.sh` → **PASS** (0 Blueprint literals, 31 files).
- No Blueprint project id / UID / path introduced; identity still flows only through
  `HarnessConfig`.

## GENERIC vs STOCK-TRACK-SPECIFIC (reuse boundary)

- **GENERIC framework (reusable, no app identity):** `harness_overlay.dart` (mount
  seam, pan-drag, nav-inset clamp, fractional persistence, count badge), the §7
  `SafeArea`/`resizeToAvoidBottomInset` composer fix, the navigator-key push pattern.
  These hardcode no project id / collection / owner value — the badge reads the
  generic owner-reports provider; colours come from the `HarnessTheme` seam.
- **STOCK-TRACK-SPECIFIC (wiring/config only):** `app.dart` names `StockTrackApp` /
  `AppShell` (the host app's own root — inherently app-specific); `HarnessTheme.accent`
  resolves to Stock-Track's palette via the theme seam (one documented thin-seam).
  A future 3rd app reuses the overlay verbatim and supplies its own root + theme +
  `project.config.json`.

## Deferred (intentional, per parity map)

- Drag ergonomics (long-press-to-drag, grip handle, haptic, scale-up) — DEFER class.
- The badge currently merges the open-report count only; ready-to-test + chat-unread
  fold in when those providers land (ready-to-test arrives in Chunk 3; the badge is
  built to extend without re-touching the overlay).
