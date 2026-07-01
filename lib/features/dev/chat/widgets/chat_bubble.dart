import 'dart:io';

import 'package:flutter/material.dart';

/// One chat bubble — owner (right, accent) vs orchestrator (left, surface). Chunk 4
/// adds per-bubble copy + multi-select; Chunk 5 adds an inline image attachment
/// (tap to zoom).
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
    this.imageUrl,
    this.onCopy,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  final String text;
  final bool isOwner;
  final Color accent;

  /// An attached image — a Storage URL or a local file path. Null = text-only.
  final String? imageUrl;

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
          if ((imageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            _image(context, imageUrl!),
          ],
          if (text.isNotEmpty) ...[
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

  Widget _image(BuildContext context, String source) {
    final img = source.startsWith('http')
        ? Image.network(
            source,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _imgError(),
          )
        : Image.file(
            File(source),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _imgError(),
          );
    return GestureDetector(
      // In selection mode a tap toggles the bubble; otherwise it zooms the image.
      onTap: selectionMode ? onTap : () => showChatImageZoom(context, source),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: img,
        ),
      ),
    );
  }

  Widget _imgError() => Container(
    width: 140,
    height: 100,
    color: Colors.white.withValues(alpha: 0.06),
    child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
  );
}

/// Full-screen, pinch-to-zoom view of a chat image (URL or local path).
Future<void> showChatImageZoom(BuildContext context, String source) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: source.startsWith('http')
                ? Image.network(source)
                : Image.file(File(source)),
          ),
        ),
      ),
    ),
  );
}
