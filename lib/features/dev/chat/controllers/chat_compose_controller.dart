import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/harness_logger.dart';
import '../../../../core/utils/harness_speech.dart';
import '../services/chat_repository.dart';
import '../services/chat_upload_service.dart';

/// Send orchestration for the owner↔orchestrator chat. Chunk 5 adds a staged image
/// attachment (Storage-gated upload) + OS mic dictation into the composer. Owns the
/// `sending` flag and the send/retry loop.
class ChatComposeController {
  ChatComposeController({
    required this.repository,
    required this.uid,
    required this.controller,
    required this.notify,
    required this.snack,
  });

  final ChatRepository repository;
  final String uid;
  final TextEditingController controller;
  final VoidCallback notify;
  final void Function(String message) snack;

  /// Cap the wait on the server ack so weak signal can't spin the UI forever — a
  /// timeout means "queued, will sync", not "lost" (Firestore applies the write to
  /// the local cache synchronously + durably queues it).
  static const Duration _sendAckTimeout = Duration(seconds: 8);

  final HarnessSpeech _speech = HarnessSpeech();
  bool _listening = false;
  String _micBase = '';

  XFile? _staged;
  bool _sending = false;

  bool get sending => _sending;
  bool get listening => _listening;
  XFile? get staged => _staged;
  bool get hasStaged => _staged != null;

  // ----- Image attachment -----
  void stage(XFile image) {
    _staged = image;
    notify();
  }

  void clearStaged() {
    _staged = null;
    notify();
  }

  // ----- Mic dictation (OS speech seam) -----
  Future<void> toggleMic() async {
    if (_listening) {
      await _speech.stop();
      _listening = false;
      notify();
      return;
    }
    _micBase = controller.text.trimRight();
    final ok = await _speech.start(
      onResult: (t) {
        controller.text = _micBase.isEmpty ? t : '$_micBase $t';
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        notify();
      },
      onFinal: (_) {
        _listening = false;
        notify();
      },
    );
    if (!ok) {
      snack('Mic unavailable — check the microphone permission.');
      return;
    }
    _listening = true;
    notify();
  }

  Future<void> send() async {
    if (_sending) return;
    if (_listening) await toggleMic();
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
    notify();
    harnessLog.chat(queuedOffline ? 'send queued offline' : 'send OK');
    if (queuedOffline) {
      snack('Message queued — will send when back online.');
    }
  }

  void dispose() => _speech.dispose();
}
