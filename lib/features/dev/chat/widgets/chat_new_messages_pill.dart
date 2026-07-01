import 'package:flutter/material.dart';

/// A floating "new messages" pill — sits over the message list (via a `Positioned`
/// in a `Stack`), so it never shifts the composer or consumes list layout. Tapping
/// it clears the unread state and jumps to the newest message.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic; the accent is passed in.
class ChatNewMessagesPill extends StatelessWidget {
  const ChatNewMessagesPill({
    super.key,
    required this.onTap,
    required this.accent,
  });

  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_downward, size: 16, color: Colors.black),
              SizedBox(width: 6),
              Text(
                'New messages',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
