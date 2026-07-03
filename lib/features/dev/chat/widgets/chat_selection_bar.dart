import 'package:flutter/material.dart';

/// The selection-mode AppBar for the chat — "N selected", a Copy(N) action, and a
/// close button. Shown in place of the normal AppBar while the owner multi-selects
/// bubbles to bulk-copy (the daily "grab replies to paste into an external LLM"
/// lever).
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic; colours passed in.
class ChatSelectionBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatSelectionBar({
    super.key,
    required this.count,
    required this.onCopy,
    required this.onClear,
    required this.background,
    required this.accent,
    this.onTag,
  });

  final int count;
  final VoidCallback onCopy;
  final VoidCallback onClear;
  final Color background;
  final Color accent;

  /// Open the tag/label picker for the current selection (HI-11). Null → the action is
  /// hidden (e.g. tagging disabled).
  final VoidCallback? onTag;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: background,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Clear selection',
        onPressed: onClear,
      ),
      title: Text('$count selected'),
      actions: [
        if (onTag != null)
          IconButton(
            onPressed: count == 0 ? null : onTag,
            icon: Icon(Icons.label_outline, color: accent),
            tooltip: 'Tag / Label',
          ),
        TextButton.icon(
          onPressed: count == 0 ? null : onCopy,
          icon: Icon(Icons.copy, size: 18, color: accent),
          label: Text('Copy ($count)', style: TextStyle(color: accent)),
        ),
      ],
    );
  }
}
