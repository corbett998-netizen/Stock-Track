# CORRECTION — OVERLAY + LABELING group (floating dev-tools cluster + honest mode banner)

**Scope:** Stock-Track (`/mnt/c/dev/Brandons_App`) only. No Blueprint files touched.
**Two corrections in one group:**
1. **OVERLAY** — the floating dev-tools are rebuilt from a single FAB → separate command-center
   *page* into a **draggable, config-driven, multi-button CLUSTER** whose buttons launch each tool
   directly over the current screen.
2. **LABELING** — an honest **mode banner** (local-only vs saved-but-not-read vs connected) so a
   functional-looking-but-disconnected channel can never mislead a dogfooder.

---

## 1. OVERLAY — what was wrong (verified against the code)

Stock-Track shipped the WRONG shape: `harness_overlay.dart` rendered exactly ONE draggable FAB whose
`onPressed` pushed `HarnessHomeScreen` — a separate `Scaffold`+`ListView` *command-center page*. The
owner flow was TWO hops that LEFT the tested screen (tap FAB → land on the menu page → tap a tile →
land on the tool). There was one merged badge (no per-tool badges), and no single-instance /
mutual-exclusion launcher.

## OVERLAY — what changed

The single-FAB→page model is gone. The buttons ARE the menu, mounted at the `MaterialApp.builder`
seam above the Navigator so they float over EVERY route.

**NEW (all app-agnostic, `lib/features/dev/overlay/`):**
- `single_instance_launcher.dart` — `SingleInstanceLauncher`: a static keyed open-set behind every
  launch. **Duplicate guard** (re-tapping an open surface is a no-op), **exclusive group** (opening
  one exclusive surface dismisses whichever other exclusive surface is open — "one dev surface at a
  time", keys snapshotted before dismiss), **self-heal** (a synchronous throw releases the latch so a
  failed open can't stick a key 'open'), and the latch always clears on the returned future's
  `whenComplete`. Routes go through a shared root `navigatorKey` (set by the cluster) — no app noun.
- `harness_tool_spec.dart` — `HarnessToolSpec` config model (`key`, `icon`, `label`, `color?`,
  `exclusive`, `launch(rootCtx, uid)`, `badgeCount?(ref, uid)`).
- `harness_tool_button.dart` — `HarnessToolButton`: a generic **bare** `FloatingActionButton.small`
  rendering one spec, with its own red count badge (renders nothing at zero) in a
  `Stack(clipBehavior: Clip.none)`. No `Tooltip` (no Overlay ancestor at the seam) → `Semantics`
  label; unique `heroTag` per spec key. A null uid disables the button + hides its badge.
- `harness_fab_cluster.dart` — `HarnessFabCluster`: the new thing mounted at the builder seam.
  Dev-gated (`kHarnessEnabled`), wraps `Stack([child, cluster])`, watches `ownerUidProvider`, renders
  `Column(min, end)` = a grip handle + one bare button per spec (~6px gaps). Drag = a plain gesture
  (long-press-drag anywhere **+** a dedicated grip pan — NOT a `Draggable`, which needs an Overlay
  ancestor). Position is stored as a screen **fraction** in `SharedPreferences`
  (`harness_cluster_fx/fy`) and **re-clamped every build** to a band that folds in the safe-area
  insets + a bottom-nav clearance, so it survives rotation / a smaller screen and never strands under
  the status bar or the bottom nav. (This fractional-position + clamp logic is **harvested** from the
  retired `harness_overlay.dart`.)
- `harness_tools.dart` — `kHarnessTools`, the **config-driven list** and the ONLY place ST tools are
  named: Orchestrator chat (exclusive route), Report queue (exclusive route, open-reports badge),
  File a report (route), Ready to test (bottom **sheet** via `guard`, awaiting-verification badge),
  Poke (inline, honest), and an optional Command center button (the page still exists but is no
  longer THE entry).

**CHANGED:** `lib/app.dart` mounts `HarnessFabCluster(navigatorKey:…)` at the builder seam instead of
`HarnessOverlay`. **REMOVED:** `lib/features/dev/harness_overlay.dart` (retired).

### The load-bearing gotchas honored
- The cluster's `BuildContext` has **no Navigator/Overlay/ScaffoldMessenger ancestor** → every launch
  goes through the shared root `navigatorKey`, never `Navigator.of(clusterContext)`; a
  `fallbackContext` is used only for standalone widget tests.
- `showReadyToTestSheet` (a `showModalBottomSheet`) is opened on **`navigatorKey.currentContext`**
  (the Navigator's own element resolves `Navigator.of` to itself), never the cluster context.
- `uid` is **async** here (`ownerUidProvider` `FutureProvider`) — resolved once at the cluster and
  passed into each `launch`/`badgeCount`; uid-dependent buttons are disabled until it lands.
- Unique `heroTag` per FAB, `Semantics` labels instead of `Tooltip`, dev-gating on the cluster (each
  button is dev-gated by virtue of the cluster never mounting in release).

## 2. LABELING — what was wrong

In mock/local mode **nothing** is written where an orchestrator could read (verified: `MockChat…` is
in-memory, `MockReport….pokeOrchestrator` is a log line, `MockHarnessAuth` a fixed uid) — yet the UI
presented a fully live-looking channel (composer hint "Message the orchestrator…", a Poke tile that
flipped to "Poked … wake the loop now", and a status card that hardcoded `… in easy-stock-track` and
was **false** in mock mode). Even in firebase mode, "writes to the backend" ≠ "an orchestrator is
reading".

## LABELING — what changed (config-driven, honest)

- `harness/project.config.json` — new `harness` block: `orchestratorBridge` (`off`|`live` — declares
  whether a real operator loop reads this project) and `backendLabel` (`${firebase.projectId}`,
  interpolated — no hardcoded app noun). `gen_app_config.js` maps both → regenerated
  `lib/harness/harness_config.g.dart` (`HarnessConfig.orchestratorBridge`/`.backendLabel`).
- **NEW `lib/features/dev/harness_connectivity.dart`** — a pure, widget-free resolver:
  `enum HarnessConn { localPreview, backendOnly, live }` + `resolveHarnessConn()` (mock → localPreview;
  firebase+`live` → live; else → backendOnly) + config-driven copy (`harnessConnMessage`,
  `harnessBackendLine`). Unit-testable, no project noun.
- **NEW `lib/features/dev/harness_mode_banner.dart`** — `HarnessModeBanner`: an amber strip for
  localPreview / backendOnly, and **nothing** when connected. Mounted at the top of the chat body
  (`orchestrator_chat_screen.dart`) and the top of the command center (`harness_home_screen.dart`).
- **Poke/send honesty:** the command-center Poke tile (`harness_home_screen.dart`) is disabled in
  local preview with subtitle "Local preview — no orchestrator to poke; nothing is sent", and
  mode-aware otherwise; the cluster's Poke button snackbar says "Saved locally — no orchestrator to
  poke." in local preview vs "Poked — …" otherwise; the chat composer hint becomes "Message (local
  preview — not delivered)…" in local preview. The misleading hardcoded `… in easy-stock-track`
  backend line is replaced with `harnessBackendLine(resolveHarnessConn())`, and the separation footer
  now reads `HarnessConfig.backendLabel` — **no UI string hardcodes a project name**.

**NOT implemented (spec was explicitly SPEC-ONLY):** the throwaway-TEST-Firebase *live bridge*
(connectivity part b) and the `bp_guard`/selftest generalization. `orchestratorBridge` ships **"off"**;
flipping it to "live" is the pending owner A/B decision, not this correction.

## Gate results (this machine, 2026-07-01)

| Gate | Result |
| --- | --- |
| `bash harness/harness_antileak_scan.sh` | **PASS** — 0 Blueprint literals, 47 files scanned |
| `node harness/gen_app_config.js --check` | **PASS** — generated config up to date |
| `flutter analyze` | **PASS** — No issues found (0) |
| `flutter test` | **PASS** — 59/59 (new `test/harness_cluster_test.dart` + launcher/connectivity groups in `harness_test.dart`) |
| `flutter build apk --debug` — firebase (default) | **PASS** — built `app-debug.apk` |
| `flutter build apk --debug` — mock | **PASS** — built `app-debug.apk` (mode flipped, verified, reverted) |

On-device dogfood is the product-facing proof per doctrine (multiple buttons floating over the tested
screen, drag/persistence across restart+rotation, one-at-a-time swap, live per-tool badges, honest
banner). The widget test proves the cluster SHAPE + direct-launch-over-the-same-screen; the launcher
unit tests prove duplicate-guard / exclusive-swap / self-heal deterministically.

## Generic (reusable framework) vs Stock-Track-specific

- **Generic / app-agnostic (reusable harness framework):** `SingleInstanceLauncher`,
  `HarnessToolSpec`, `HarnessToolButton`, `HarnessFabCluster`, `HarnessModeBanner`, and the
  `harness_connectivity` resolver. None name a project id, collection, owner, tool, or screen — the
  cluster renders whatever list it is given; the banner reads only the pure resolver + config copy.
- **Stock-Track-specific (by design, isolated to two places):** `kHarnessTools` in
  `overlay/harness_tools.dart` (the one file that names the five ST tools + the optional command
  center — adding/removing a tool is a one-line edit here, cluster/launcher untouched), and the
  `harness` config values in `project.config.json` (`orchestratorBridge`, `backendLabel`). Identity
  flows in **from config** (`backendLabel` interpolates `firebase.projectId`, so a different project
  relabels the banner automatically), never from a literal in a framework file.
