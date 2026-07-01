import 'package:flutter/material.dart';

import '../controllers/chat_compose_controller.dart';

/// The bottom composer (text-only). Ported from Blueprint's `ChatComposer`, trimmed
/// to the input row (BP's mic + attach-image are DEFERRED). Reads the controller's
/// live `sending` state each build; the screen rebuilds it via the injected notify.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.compose,
    required this.controller,
    required this.focusNode,
    required this.accent,
  });

  final ChatComposeController compose;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      color: Colors.black.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Message the orchestrator…',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1E1E20),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          compose.sending
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  ),
                )
              : IconButton(
                  icon: Icon(Icons.send, color: accent),
                  tooltip: 'Send',
                  onPressed: compose.send,
                ),
        ],
      ),
    );
  }
}
