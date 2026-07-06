import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dev_gate.dart';
import '../push/harness_push_service.dart';
import '../services/harness_providers.dart';
import 'harness_tool_button.dart';
import 'harness_tools.dart';
import 'single_instance_launcher.dart';

/// The floating dev-tools CLUSTER — a draggable, config-driven column of tool
/// buttons that floats over the live screen, mounted at the `MaterialApp.builder`
/// seam so it sits ABOVE the Navigator and can never be covered by a pushed route.
///
/// This REPLACES the single-FAB → command-center-page model. The buttons ARE the
/// menu: each opens its tool directly over the current screen (a full tool as a
/// route pushed on the ROOT navigator, ready-to-test as a bottom sheet, poke inline)
/// and returns to the exact same screen on close — the tested screen is never left.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic. The button set comes from
/// [kHarnessTools]; the cluster/launcher name no app tool. Hardening ported from the
/// retired single-FAB overlay:
///  - dev-gated ([kHarnessEnabled]) — never mounts in a release build;
///  - the whole cluster is ONE draggable unit (long-press-drag anywhere OR a grip
///    handle), a plain gesture (no `Draggable`: there is no Overlay ancestor here);
///  - position is stored as a screen FRACTION in [SharedPreferences] and re-clamped
///    every build to a band that folds in the safe-area insets + a bottom-nav
///    clearance, so it survives rotation / a smaller screen and never strands under
///    the status bar or the bottom nav.
class HarnessFabCluster extends ConsumerStatefulWidget {
  const HarnessFabCluster({super.key, required this.child, this.navigatorKey});

  final Widget child;

  /// The app Navigator the tools push through. The cluster sits ABOVE the Navigator,
  /// so `Navigator.of(clusterContext)` would not find it — every launch routes via
  /// this shared key (set on [SingleInstanceLauncher]). Null → a standalone test,
  /// where the launcher falls back to the ancestor Navigator of the tapped context.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  ConsumerState<HarnessFabCluster> createState() => _HarnessFabClusterState();
}

class _HarnessFabClusterState extends ConsumerState<HarnessFabCluster> {
  static const double _buttonSize = 44;
  static const double _gap = 6;
  static const double _gripHeight = 22;
  static const double _clusterWidth = 56;
  // Clearance kept below the cluster on top of the system nav/gesture inset, so it
  // never overlaps a bottom NavigationBar either.
  static const double _bottomClearance = 84;
  static const String _prefFx = 'harness_cluster_fx';
  static const String _prefFy = 'harness_cluster_fy';

  /// Restored position as a screen fraction (0..1 of width/height), null → default.
  Offset? _frac;

  /// Live absolute position while/after a drag this session.
  Offset? _pos;

  /// Anchor captured at long-press start, so a long-press-drag is relative.
  Offset _dragAnchor = Offset.zero;

  /// The uid we've registered for push against (once per distinct uid). Push is harness
  /// infra, so registration lives here — the cluster is dev-gated and already resolves
  /// the owner uid; the wiring/handlers were set up in main() via [HarnessPushService].
  String? _pushRegisteredUid;

  /// Collapsed/expanded toggle — collapsed shows only the drag-handle tab; expanded
  /// shows the full tool column below it. Double-tap the grip to toggle. Not
  /// persisted (unlike position): every fresh mount starts collapsed.
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    SingleInstanceLauncher.navigatorKey = widget.navigatorKey;
    _restorePosition();
  }

  double get _clusterHeight =>
      _gripHeight +
      kHarnessTools.length * _buttonSize +
      kHarnessTools.length * _gap;

  /// The on-screen footprint used to clamp the cluster's position — just the grip
  /// tab while collapsed, so it can sit anywhere the full cluster couldn't.
  double get _visibleHeight => _expanded ? _clusterHeight : _gripHeight;

  Future<void> _restorePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fx = prefs.getDouble(_prefFx);
      final fy = prefs.getDouble(_prefFy);
      if (fx != null && fy != null && mounted) {
        setState(() => _frac = Offset(fx, fy));
      }
    } catch (_) {
      // No store (tests / plugin unavailable) — default corner.
    }
  }

  Future<void> _savePosition(Offset frac) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefFx, frac.dx);
      await prefs.setDouble(_prefFy, frac.dy);
    } catch (_) {
      // Best-effort; the in-memory position still holds this run.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kHarnessEnabled) return widget.child;
    // Keep the launcher's root-navigator handle current (idempotent).
    SingleInstanceLauncher.navigatorKey = widget.navigatorKey;
    // Owner-only gate: the cluster renders ONLY for the pinned owner uid, so
    // kHarnessEnabled = true (release-safe) never surfaces the harness to any
    // other signed-in install. Null (still resolving / not signed in) also hides it.
    final uid = ref.watch(ownerUidProvider).valueOrNull;
    if (uid != kOwnerUid) return widget.child;
    // Safe: uid == kOwnerUid above, and kOwnerUid is a non-null String literal.
    return Stack(children: [widget.child, _cluster(context, uid!)]);
  }

  Widget _cluster(BuildContext context, String uid) {
    final media = MediaQuery.of(context);
    final size = media.size;

    final minX = 0.0;
    final maxX = (size.width - _clusterWidth).clamp(0.0, double.infinity);
    final minY = media.padding.top + 4;
    final maxY =
        (size.height -
                media.padding.bottom -
                _bottomClearance -
                _visibleHeight)
            .clamp(minY, double.infinity);

    Offset base;
    if (_pos != null) {
      base = _pos!;
    } else if (_frac != null) {
      base = Offset(_frac!.dx * size.width, _frac!.dy * size.height);
    } else {
      base = Offset(maxX - 8, maxY);
    }
    final pos = Offset(base.dx.clamp(minX, maxX), base.dy.clamp(minY, maxY));

    void applyDelta(Offset next) {
      setState(() {
        _pos = Offset(next.dx.clamp(minX, maxX), next.dy.clamp(minY, maxY));
      });
    }

    void persist() {
      final frac = Offset(
        size.width == 0 ? 0 : pos.dx / size.width,
        size.height == 0 ? 0 : pos.dy / size.height,
      );
      _frac = frac;
      _savePosition(frac);
    }

    // uid is the resolved owner uid — build() only calls _cluster once it has
    // matched kOwnerUid, so it's always non-null and always the owner here.
    final rootCtx = widget.navigatorKey?.currentContext ?? context;

    // Register this uid for push once it resolves (firebase mode only — mock has no
    // backend). Guarded to fire once per distinct uid; registerForUser is fully wrapped
    // and never throws, so it can't disturb the cluster build.
    if (uid != _pushRegisteredUid &&
        kHarnessMode == HarnessMode.firebase) {
      _pushRegisteredUid = uid;
      HarnessPushService.instance.registerForUser(uid);
    }

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        // Long-press-drag ANYWHERE on the cluster (buttons keep their own tap).
        onLongPressStart: (_) => _dragAnchor = pos,
        onLongPressMoveUpdate: (d) =>
            applyDelta(_dragAnchor + d.offsetFromOrigin),
        onLongPressEnd: (_) => persist(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _grip(pos, applyDelta, persist),
            // Collapsed: only the grip tab renders — no tool buttons, no gaps.
            if (_expanded)
              for (final spec in kHarnessTools) ...[
                const SizedBox(height: _gap),
                // A stateful in-place tool (e.g. the floating mic) renders its own
                // constant-footprint widget; every other tool is a tap-to-launch FAB.
                if (spec.builder != null)
                  SizedBox(
                    width: _buttonSize,
                    height: _buttonSize,
                    child: spec.builder!(),
                  )
                else
                  HarnessToolButton(spec: spec, rootContext: rootCtx, uid: uid),
              ],
          ],
        ),
      ),
    );
  }

  /// The dedicated drag handle — a plain pan (incremental) for a precise grab, in
  /// addition to the whole-cluster long-press-drag.
  Widget _grip(Offset pos, void Function(Offset) applyDelta, VoidCallback persist) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => applyDelta((_pos ?? pos) + d.delta),
      onPanEnd: (_) => persist(),
      onDoubleTap: () => setState(() => _expanded = !_expanded),
      child: Semantics(
        label: 'Move dev tools',
        hint: 'Double tap to expand or collapse',
        child: Container(
          width: 44,
          height: _gripHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(
            Icons.drag_indicator,
            size: 15,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}
