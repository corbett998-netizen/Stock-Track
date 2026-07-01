import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/harness_logger.dart';
import '../services/chat_repository.dart';
import '../services/chat_upload_service.dart';
import 'chat_voice_controller.dart';

/// Send orchestration for the owner↔orchestrator chat. Adds a staged image
/// attachment (Storage-gated upload) + app-owned native mic dictation into the
/// composer (the reference mic pattern, via [ChatVoiceController] — reuses the
/// single shared recognizer, snapshots the report draft so chat speech never leaks
/// into a report). Owns the `sending` flag and the send/retry loop.
class ChatComposeController {
  ChatComposeController({
    required this.repository,
    required this.uid,
    required this.controller,
    required this.notify,
    required this.snack,
    VoidCallback? autoScroll,
  }) {
    _voice = ChatVoiceController(
      controller: controller,
      notify: notify,
      autoScroll: autoScroll,
    )..start();
  }

  final ChatRepository repository;
  final String uid;
  final TextEditingController controller;
  final VoidCallback notify;
  final void Function(String message) snack;

  /// Cap the wait on the server ack so weak signal can't spin the UI forever — a
  /// timeout means "queued, will sync", not "lost" (Firestore applies the write to
  /// the local cache synchronously + durably queues it).
  static const Duration _sendAckTimeout = Duration(seconds: 8);

  late final ChatVoiceController _voice;

  XFile? _staged;
  bool _sending = false;

  bool get sending => _sending;
  bool get listening => _voice.isListening;
  XFile? get staged => _staged;
  bool get hasStaged => _staged != null;

  /// Forward the composer's onChanged so the owner typing tears down a live mic
  /// turn cleanly (keyboard text becomes authoritative).
  void handleUserTyping() => _voice.handleUserTyping();

  // ----- Image attachment -----
  void stage(XFile image) {
    _staged = image;
    notify();
  }

  void clearStaged() {
    _staged = null;
    notify();
  }

  // ----- Mic dictation (app-owned native recognizer, via ChatVoiceController) --
  //
  // The recognizer is app-owned + continuous (re-arms across pauses); the borrow
  // controller mirrors the dictated delta into the chat input and isolates it from
  // the shared report draft. This just toggles + surfaces a permission failure.
  Future<void> toggleMic() async {
    await _voice.toggleMic();
  }

  Future<void> send() async {
    if (_sending) return;
    if (_voice.isListening) await _voice.stop();
    final text = controller.text.trim();
    if (text.isEmpty && _staged == null) return;
    _sending = true;
    notify();

    harnessLog.chat(
      'send (${text.length} chars${_staged != null ? ', +image' : ''})',
    );

    // Resolve the attachment (Storage-gated): a URL when Storage is on, a local path
    // when it's off (rendered on-device this session).
    String? imageSource;
    try {
      imageSource = await ChatUploadService.resolve(_staged, uid: uid);
    } catch (e) {
      harnessLog.chat('image resolve failed: $e');
      imageSource = _staged?.path;
    }

    var queuedOffline = false;
    try {
      try {
        await repository
            .sendMessage(uid: uid, text: text, imageSource: imageSource)
            .timeout(_sendAckTimeout);
      } on TimeoutException {
        queuedOffline = true;
      }
    } catch (e) {
      _sending = false;
      notify();
      harnessLog.chat('send FAILED: $e');
      snack("Couldn't send — tap send to resend.");
      return; // keep the text + staged image so the owner can resend
    }

    controller.clear();
    _staged = null;
    _sending = false;
    _voice.markSent(); // clear per-turn dictation state so the next message is fresh
    notify();
    harnessLog.chat(queuedOffline ? 'send queued offline' : 'send OK');
    if (queuedOffline) {
      snack('Message queued — will send when back online.');
    }
  }

  void dispose() => _voice.dispose();
}
