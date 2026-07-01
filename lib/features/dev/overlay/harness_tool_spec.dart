import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One declarative entry in the floating dev cluster's button set.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic. The cluster renders
/// whatever list of these it is given; adding/removing a tool is a one-line edit to
/// the config list ([kHarnessTools]), never a change to the cluster or launcher
/// widget. No app-specific noun lives here — the concrete tool wiring (which screen,
/// which provider) lives in the config list.
@immutable
class HarnessToolSpec {
  const HarnessToolSpec({
    required this.key,
    required this.icon,
    required this.label,
    required this.launch,
    this.color,
    this.exclusive = false,
    this.badgeCount,
  });

  /// Unique single-instance key — the launcher latches open surfaces under this so a
  /// re-tap is a no-op and exclusive tools swap cleanly.
  final String key;

  /// The button glyph.
  final IconData icon;

  /// Accessibility / hero label (there is no `Tooltip` above the Navigator, so this
  /// is the semantic name and the source of the button's unique `heroTag`).
  final String label;

  /// Accent for this button. Null → the cluster falls back to `HarnessTheme.accent`.
  final Color? color;

  /// When true, opening this surface first dismisses any other open exclusive
  /// surface — "one dev surface at a time".
  final bool exclusive;

  /// Opens the tool. Receives the ROOT navigator context (an ancestor of a real
  /// Navigator/Overlay/ScaffoldMessenger, unlike the cluster's own context) and the
  /// resolved owner uid, and performs the actual push/sheet through the launcher.
  final void Function(BuildContext rootContext, String uid) launch;

  /// Optional live badge count for this button. Called from the button's `build`
  /// with its `WidgetRef`, so it may `ref.watch(...)` a stream; returns 0 (or is
  /// null) when there is nothing to surface. Scoped to the resolved [uid].
  final int Function(WidgetRef ref, String uid)? badgeCount;
}
