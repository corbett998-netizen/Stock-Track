import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/chat_repository.dart';

/// Send orchestration for the owner↔orchestrator chat. Ported from Blueprint's
/// `ChatComposeController`, trimmed to text-only (BP's image staging + voice are
/// DEFERRED per the port plan). Owns the `sending` flag and the send/retry loop.
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

  bool _sending = false;
  bool get sending => _sending;

  Future<void> send() async {
    if (_sending) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    _sending = true;
    notify();

    var queuedOffline = false;
    try {
      try {
        await repository
            .sendMessage(uid: uid, text: text)
            .timeout(_sendAckTimeout);
      } on TimeoutException {
        queuedOffline = true;
      }
    } catch (e) {
      _sending = false;
      notify();
      snack("Couldn't send — tap send to resend.");
      return; // keep the text so the owner can resend
    }

    controller.clear();
    _sending = false;
    notify();
    if (queuedOffline) {
      snack('Message queued — will send when back online.');
    }
  }
}
