import 'package:flutter/material.dart';

import 'dev_gate.dart';
import 'harness_home_screen.dart';
import 'harness_theme.dart';

/// Wraps the app content and, when [kHarnessEnabled] (dev builds only), overlays a
/// draggable entry button that opens the owner command center. Ported from
/// Blueprint's dev FAB-stack entry, trimmed to a single draggable button (BP's
/// route-region tracking + multi-FAB stack are DEFERRED). In a release build it
/// renders [child] unchanged — the harness never mounts.
class HarnessOverlay extends StatefulWidget {
  const HarnessOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<HarnessOverlay> createState() => _HarnessOverlayState();
}

class _HarnessOverlayState extends State<HarnessOverlay> {
  Offset? _pos; // null → default bottom-right

  @override
  Widget build(BuildContext context) {
    if (!kHarnessEnabled) return widget.child;
    return Stack(
      children: [
        widget.child,
        _fab(context),
      ],
    );
  }

  Widget _fab(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final pos = _pos ??
        Offset(size.width - 76, size.height - media.padding.bottom - 150);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Draggable(
        feedback: _button(context, dragging: true),
        childWhenDragging: const SizedBox.shrink(),
        onDragEnd: (d) {
          setState(() {
            final dx = d.offset.dx.clamp(0.0, size.width - 56);
            final dy = d.offset.dy.clamp(media.padding.top, size.height - 56);
            _pos = Offset(dx, dy);
          });
        },
        child: _button(context),
      ),
    );
  }

  Widget _button(BuildContext context, {bool dragging = false}) {
    return Material(
      color: Colors.transparent,
      child: FloatingActionButton(
        heroTag: 'harness-entry-fab',
        backgroundColor: HarnessTheme.accent,
        foregroundColor: Colors.black,
        elevation: dragging ? 8 : 4,
        onPressed: dragging
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HarnessHomeScreen()),
                ),
        tooltip: 'Owner harness',
        child: const Icon(Icons.support_agent),
      ),
    );
  }
}
