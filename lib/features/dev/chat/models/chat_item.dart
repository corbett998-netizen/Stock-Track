import 'package:flutter/foundation.dart';

/// One rendered chat row in the owner↔orchestrator thread.
///
/// Ported from Blueprint's `ChatItem`, trimmed for the Stock-Track text-only slice
/// (BP's attachment + workflow-tag arrays are DEFERRED — see the port plan). A
/// single id+role+text+time row lets the message list dedupe by id across the live
/// listener and the foreground server-poll.
@immutable
class ChatItem {
  const ChatItem({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAtMs,
    this.imageUrl,
  });

  final String id;

  /// `'brandon'` (the owner — `HarnessConfig.ownerRole`) or `'orchestrator'`.
  final String role;
  final String text;
  final int createdAtMs;

  /// An attached image — a Storage download URL (Storage on) or a local file path
  /// (Storage off / mock, rendered on-device). Null when the message is text-only.
  final String? imageUrl;

  bool get hasImage => (imageUrl ?? '').isNotEmpty;
}
