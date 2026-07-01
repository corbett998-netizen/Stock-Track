import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../harness_theme.dart';
import 'harness_tool_spec.dart';

/// One tool button in the floating dev cluster — a small FAB that renders a single
/// [HarnessToolSpec], with its own live count badge.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic. In [bare] mode it renders
/// ONLY the FAB core (no SafeArea/Align/Padding) so the cluster owns positioning;
/// with `bare == false` it self-positions in the bottom-right (a legacy standalone
/// use). Because the cluster lives above the Navigator (no Overlay ancestor), this
/// uses [Semantics] for its label instead of a `Tooltip`, and a unique `heroTag`
/// derived from the spec key so multiple FABs never collide.
class HarnessToolButton extends ConsumerWidget {
  const HarnessToolButton({
    super.key,
    required this.spec,
    required this.rootContext,
    required this.uid,
    this.bare = true,
  });

  final HarnessToolSpec spec;

  /// The ROOT navigator context handed to [HarnessToolSpec.launch] — an ancestor of
  /// a real Navigator/Overlay/ScaffoldMessenger, which the cluster's own context is
  /// not.
  final BuildContext rootContext;

  /// The resolved owner uid, or null while it is still resolving — a null uid
  /// disables the button and hides its badge (the tool needs a uid to open).
  final String? uid;

  final bool bare;

  static const double _size = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedUid = uid;
    final core = SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Semantics(
            button: true,
            label: spec.label,
            child: FloatingActionButton.small(
              heroTag: 'harness-tool-${spec.key}',
              backgroundColor: spec.color ?? HarnessTheme.accent,
              foregroundColor: Colors.black,
              elevation: 3,
              // Only launch-tools render through this button (builder-tools render
              // their own widget in the cluster), so launch is non-null here.
              onPressed: (resolvedUid == null || spec.launch == null)
                  ? null
                  : () => spec.launch!(rootContext, resolvedUid),
              child: Icon(spec.icon, size: 20),
            ),
          ),
          if (spec.badgeCount != null && resolvedUid != null)
            Positioned(
              top: -4,
              right: -4,
              child: _Badge(count: spec.badgeCount!(ref, resolvedUid)),
            ),
        ],
      ),
    );

    if (bare) return core;
    // Legacy standalone positioning (unused by the cluster).
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(padding: const EdgeInsets.all(16), child: core),
      ),
    );
  }
}

/// A small red count pill that renders nothing at zero — so "what needs me" is
/// glanceable per tool without opening anything. Mirrors the ported entry badge.
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
