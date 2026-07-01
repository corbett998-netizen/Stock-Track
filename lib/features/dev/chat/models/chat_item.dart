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

  /// JSON for the durable local store (mock/local path). Self-contained — carries
  /// its own [createdAtMs] so [fromMap] can rebuild it without any side channel.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'role': role,
    'text': text,
    'createdAtMs': createdAtMs,
    if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
  };

  /// Rebuild from a stored map (reads [createdAtMs] from the map itself). Tolerant
  /// of missing fields so an older/partial record can never crash the load.
  static ChatItem fromMap(Map<String, dynamic> m) => ChatItem(
    id: (m['id'] ?? '').toString(),
    role: (m['role'] ?? 'orchestrator').toString(),
    text: (m['text'] ?? '').toString(),
    createdAtMs: (m['createdAtMs'] as num?)?.toInt() ?? 0,
    imageUrl: m['imageUrl'] as String?,
  );
}
