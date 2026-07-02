import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

/// One chat bubble — owner (right, accent) vs orchestrator (left, surface). Chunk 4
/// adds per-bubble copy + multi-select; Chunk 5 adds an inline image attachment
/// (tap to zoom). Chunk 6 adds the copy VISUAL CONFIRM: once copied, the bubble
/// fades to gray + a tappable "copied ✓" badge appears (auto-reverts after a moment,
/// or tap the badge to undo), so the owner can see the text is on the clipboard.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic; accent + callbacks passed
/// in. Uses plain `Text` (not `SelectableText`) so long-press cleanly enters
/// multi-select instead of fighting the OS text-selection handles; the copy icon +
/// bulk-copy cover the copy-out need.
///
/// Stateful only for the transient copied-confirm flag — the copy PAYLOAD stays with
/// the parent's [onCopy] (it owns the clipboard write); this widget just reflects that
/// a copy happened. Pure presentation: no Firestore / schema / rules involvement.
class ChatBubble extends StatefulWidget {
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

  /// Copy just this bubble (per-bubble copy icon). Hidden in selection mode. This
  /// widget calls it, then shows its own gray-out + "copied" confirm.
  final VoidCallback? onCopy;

  /// Tap handler — in selection mode, toggles this bubble's membership.
  final VoidCallback? onTap;

  /// Long-press — enters selection mode with this bubble selected.
  final VoidCallback? onLongPress;

  final bool selected;
  final bool selectionMode;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  /// How long the copied confirm lingers before it auto-reverts.
  static const Duration _confirmLinger = Duration(milliseconds: 1800);

  /// A dedicated confirm-green, deliberately NOT the accent — so the "copied"
  /// state never reads as (or collides with) a selection/accent colour.
  static const Color _confirmGreen = Color(0xFF3DD68C);

  bool _copied = false;
  Timer? _revertTimer;

  void _handleCopy() {
    // The parent owns the actual clipboard write (the copy payload).
    widget.onCopy?.call();
    _revertTimer?.cancel();
    setState(() => _copied = true);
    _revertTimer = Timer(_confirmLinger, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _revert() {
    _revertTimer?.cancel();
    if (mounted) setState(() => _copied = false);
  }

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.isOwner;
    final accent = widget.accent;
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
        color: widget.selected ? accent.withValues(alpha: 0.32) : baseColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isOwner ? 16 : 4),
          bottomRight: Radius.circular(isOwner ? 4 : 16),
        ),
        border: Border.all(
          color: widget.selected
              ? accent
              : (isOwner
                    ? accent.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08)),
          width: widget.selected ? 1.5 : 1,
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
              if (widget.selectionMode) ...[
                Icon(
                  widget.selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 13,
                  color: widget.selected ? accent : Colors.white38,
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
              if (!widget.selectionMode && widget.onCopy != null) ...[
                const SizedBox(width: 6),
                // The copy affordance turns into the "copied ✓" confirm once tapped;
                // tapping the confirm undoes it (matches the reference behaviour).
                _copied
                    ? _copiedBadge()
                    : InkWell(
                        onTap: _handleCopy,
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
          if ((widget.imageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            _image(context, widget.imageUrl!),
          ],
          if (widget.text.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              widget.text,
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
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        // Copied → fade the whole bubble toward gray so the confirm is unmistakable.
        child: AnimatedOpacity(
          opacity: _copied ? 0.5 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: bubble,
        ),
      ),
    );
  }

  /// Small tappable "copied ✓" pill shown in place of the copy icon after a copy.
  /// Tapping it reverts immediately (undo); it also auto-reverts via [_confirmLinger].
  Widget _copiedBadge() {
    return InkWell(
      onTap: _revert,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _confirmGreen.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _confirmGreen.withValues(alpha: 0.7),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 11, color: _confirmGreen),
            SizedBox(width: 3),
            Text(
              'copied',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: _confirmGreen,
              ),
            ),
          ],
        ),
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
      onTap: widget.selectionMode
          ? widget.onTap
          : () => showChatImageZoom(context, source),
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
