import 'package:flutter/material.dart';

/// One chat bubble — owner (right, accent) vs orchestrator (left, surface). Ported
/// from Blueprint's `ChatBubble`; Chunk 4 adds a per-bubble copy affordance +
/// multi-select support (long-press to enter selection, tap to toggle) so the owner
/// can copy replies out to an external LLM — the daily lever.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic; accent + callbacks passed
/// in. Uses plain `Text` (not `SelectableText`) so long-press cleanly enters
/// multi-select instead of fighting the OS text-selection handles; the copy icon +
/// bulk-copy cover the copy-out need.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.isOwner,
    required this.accent,
    this.onCopy,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  final String text;
  final bool isOwner;
  final Color accent;

  /// Copy just this bubble (per-bubble copy icon). Hidden in selection mode.
  final VoidCallback? onCopy;

  /// Tap handler — in selection mode, toggles this bubble's membership.
  final VoidCallback? onTap;

  /// Long-press — enters selection mode with this bubble selected.
  final VoidCallback? onLongPress;

  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final baseColor = isOwner
        ? accent.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.06);
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.32) : baseColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isOwner ? 16 : 4),
          bottomRight: Radius.circular(isOwner ? 4 : 16),
        ),
        border: Border.all(
          color: selected
              ? accent
              : (isOwner
                    ? accent.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08)),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: isOwner
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectionMode) ...[
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 13,
                  color: selected ? accent : Colors.white38,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                isOwner ? 'You' : 'Orchestrator',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                  color: (isOwner ? accent : Colors.white).withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
              if (!selectionMode && onCopy != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onCopy,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.copy,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.3,
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: isOwner ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: bubble,
      ),
    );
  }
}
