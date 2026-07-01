import 'package:flutter/material.dart';

/// One chat bubble — owner (right, accent) vs orchestrator (left, surface). Ported
/// from Blueprint's `ChatBubble`, trimmed (BP's stream-colour tags, copy-selection
/// and attachments are DEFERRED).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.isOwner,
    required this.accent,
  });

  final String text;
  final bool isOwner;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOwner ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOwner
              ? accent.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOwner ? 16 : 4),
            bottomRight: Radius.circular(isOwner ? 4 : 16),
          ),
          border: Border.all(
            color: isOwner
                ? accent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isOwner ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isOwner ? 'You' : 'Orchestrator',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
                color: (isOwner ? accent : Colors.white).withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 3),
            SelectableText(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}
