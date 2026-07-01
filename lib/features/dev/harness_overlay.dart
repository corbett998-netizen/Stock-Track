import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dev_gate.dart';
import 'harness_home_screen.dart';
import 'harness_theme.dart';
import 'services/harness_providers.dart';

/// Wraps the app content and, when [kHarnessEnabled] (dev builds only), overlays a
/// draggable entry button that opens the owner command center. Ported from
/// Blueprint's dev FAB-stack entry, trimmed to a single draggable button (BP's
/// route-region tracking + multi-FAB stack are DEFERRED). In a release build it
/// renders [child] unchanged — the harness never mounts.
///
/// Chunk 1 (HARNESS_PARITY_MAP) hardening:
///  - mounted at the [MaterialApp.builder] seam, so it floats above every route;
///  - the drag clamp folds in the system nav/gesture inset so the entry can never
///    settle under the Android nav bar;
///  - its position is stored as a screen *fraction* in [SharedPreferences] and
///    restored across restarts / rotation;
///  - a merged count badge (open reports) shows "what needs me" without opening.
class HarnessOverlay extends StatefulWidget {
  const HarnessOverlay({super.key, required this.child, this.navigatorKey});

  final Widget child;

  /// The app Navigator the entry pushes through (the overlay sits ABOVE the
  /// Navigator at the builder seam, so `Navigator.of(context)` from here would not
  /// find it). When null (e.g. a standalone test), falls back to the ancestor
  /// Navigator of the button's context.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<HarnessOverlay> createState() => _HarnessOverlayState();
}

class _HarnessOverlayState extends State<HarnessOverlay> {
  static const double _fabSize = 56;
  // Clearance kept below the entry: system nav/gesture inset is added on top of
  // this so the puck never overlaps a bottom NavigationBar (~80) either.
  static const double _bottomClearance = 84;
  static const String _prefFx = 'harness_overlay_fx';
  static const String _prefFy = 'harness_overlay_fy';

  /// Restored position as a screen fraction (0..1 of width/height), null → default.
  Offset? _frac;

  /// Live absolute position while/after a drag this session (null → derive from
  /// [_frac] or the default corner).
  Offset? _pos;

  @override
  void initState() {
    super.initState();
    _restorePosition();
  }

  Future<void> _restorePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fx = prefs.getDouble(_prefFx);
      final fy = prefs.getDouble(_prefFy);
      if (fx != null && fy != null && mounted) {
        setState(() => _frac = Offset(fx, fy));
      }
    } catch (_) {
      // No store (e.g. tests / plugin unavailable) — fall back to the default.
    }
  }

  Future<void> _savePosition(Offset frac) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefFx, frac.dx);
      await prefs.setDouble(_prefFy, frac.dy);
    } catch (_) {
      // Persistence is best-effort; the in-memory position still holds this run.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kHarnessEnabled) return widget.child;
    return Stack(children: [widget.child, _fab(context)]);
  }

  Widget _fab(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;

    // Movable band: keep the puck clear of the top status bar and, at the bottom,
    // clear of the system nav/gesture inset PLUS the bottom-nav clearance.
    final minX = 0.0;
    final maxX = (size.width - _fabSize).clamp(0.0, double.infinity);
    final minY = media.padding.top;
    final maxY =
        (size.height - media.padding.bottom - _bottomClearance - _fabSize)
            .clamp(minY, double.infinity);

    // Resolve the current absolute position (live drag → restored fraction →
    // default corner), always re-clamped to the current movable band so a rotation
    // or a smaller screen can never strand the puck under a bar.
    Offset base;
    if (_pos != null) {
      base = _pos!;
    } else if (_frac != null) {
      base = Offset(_frac!.dx * size.width, _frac!.dy * size.height);
    } else {
      base = Offset(size.width - 76, size.height - media.padding.bottom - 150);
    }
    final pos = Offset(base.dx.clamp(minX, maxX), base.dy.clamp(minY, maxY));

    // A plain pan-drag (NOT a Draggable): the overlay lives above the Navigator at
    // the builder seam, so there is no Overlay ancestor for a Draggable's feedback.
    // Drag ergonomics (long-press/grip/haptic/scale) are DEFERRED (parity map).
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tap is owned by the FAB's onPressed (below); this detector claims only the
        // pan gesture, so tap→open and drag→move disambiguate in the gesture arena.
        onPanUpdate: (d) {
          final np = Offset(
            (pos.dx + d.delta.dx).clamp(minX, maxX),
            (pos.dy + d.delta.dy).clamp(minY, maxY),
          );
          setState(() => _pos = np);
        },
        onPanEnd: (_) {
          final frac = Offset(
            size.width == 0 ? 0 : pos.dx / size.width,
            size.height == 0 ? 0 : pos.dy / size.height,
          );
          _frac = frac;
          _savePosition(frac);
        },
        child: _button(context),
      ),
    );
  }

  Widget _button(BuildContext context) {
    // NOTE: the entry lives at the builder seam ABOVE the Navigator, so it has no
    // Overlay ancestor — Overlay-dependent affordances (Tooltip, Draggable feedback)
    // can't be used here. Accessibility is kept via Semantics instead of a Tooltip.
    // The command center opens as a real route (full Overlay) via the navigatorKey.
    final fab = Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        label: 'Owner harness',
        child: FloatingActionButton(
          heroTag: 'harness-entry-fab',
          backgroundColor: HarnessTheme.accent,
          foregroundColor: Colors.black,
          elevation: 4,
          // The GestureDetector owns tap/drag; keep the FAB visual only.
          onPressed: () => _openCommandCenter(context),
          child: const Icon(Icons.support_agent),
        ),
      ),
    );
    // A glanceable "what needs me" badge — merged count (open reports today; more
    // streams fold in as their providers land). Renders nothing when zero.
    return SizedBox(
      width: _fabSize,
      height: _fabSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          fab,
          const Positioned(top: -4, right: -4, child: _HarnessEntryBadge()),
        ],
      ),
    );
  }

  void _openCommandCenter(BuildContext context) {
    final route = MaterialPageRoute<void>(
      builder: (_) => const HarnessHomeScreen(),
    );
    final navState = widget.navigatorKey?.currentState;
    if (navState != null) {
      navState.push(route);
    } else {
      Navigator.of(context).push(route);
    }
  }
}

/// The merged count badge on the floating entry. A [Consumer] so only the badge
/// subtree rebuilds on report changes, and so the (dev-only) owner sign-in is
/// triggered lazily by watching [ownerUidProvider]. Renders nothing until there is
/// a positive count, so the entry stays clean when there is nothing to action.
class _HarnessEntryBadge extends ConsumerWidget {
  const _HarnessEntryBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(ownerUidProvider).valueOrNull;
    if (uid == null) return const SizedBox.shrink();
    final count = ref
        .watch(ownerReportsProvider(uid))
        .maybeWhen(
          data: (reports) => reports
              .where(
                (r) =>
                    r.status != 'fixed' &&
                    r.status != 'wont_fix' &&
                    !r.manualResolved,
              )
              .length,
          orElse: () => 0,
        );
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
