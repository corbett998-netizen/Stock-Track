import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../dev_gate.dart';
import '../controllers/chat_compose_controller.dart';

/// The bottom composer. Chunk 5 adds an OS mic-dictation button, an image-attach
/// button (Storage-gated), and a staged-image preview strip. Reads the controller's
/// live state each build; the screen rebuilds it via the injected notify.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic; accent passed in.
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

  /// Image sharing needs Storage; while it's off we still allow it in mock mode
  /// (renders locally on-device for the demo), and show a clear "off" state in
  /// firebase mode.
  bool get _attachAvailable =>
      kHarnessStorageEnabled || kHarnessMode == HarnessMode.mock;

  Future<void> _attach() async {
    if (!_attachAvailable) {
      compose.snack('Image sharing needs Storage enabled (currently off).');
      return;
    }
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (img != null) compose.stage(img);
    } catch (e) {
      compose.snack("Couldn't attach image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      color: Colors.black.withValues(alpha: 0.35),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compose.hasStaged) _stagedStrip(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(
                  compose.listening ? Icons.stop_circle : Icons.mic_none,
                  color: compose.listening ? Colors.redAccent : accent,
                ),
                tooltip: compose.listening ? 'Stop dictation' : 'Dictate',
                onPressed: compose.sending ? null : compose.toggleMic,
              ),
              IconButton(
                icon: Icon(Icons.add_photo_alternate_outlined, color: accent),
                tooltip: 'Attach image',
                onPressed: compose.sending ? null : _attach,
              ),
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: Icon(Icons.send, color: accent),
                      tooltip: 'Send',
                      onPressed: compose.send,
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stagedStrip() {
    final path = compose.staged?.path;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: path == null
                  ? const SizedBox(width: 56, height: 56)
                  : Image.file(
                      File(path),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
            ),
            Positioned(
              top: -8,
              right: -8,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
                onPressed: compose.sending ? null : compose.clearStaged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
