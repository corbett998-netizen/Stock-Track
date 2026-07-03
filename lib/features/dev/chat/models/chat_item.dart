import 'package:flutter/foundation.dart';

import 'workflow_tag.dart';

/// One rendered chat row in the owner↔orchestrator thread.
///
/// A single id+role+text+time row lets the message list dedupe by id across the live
/// listener and the foreground server-poll. [tags] (HI-11) is an ADDITIVE, optional
/// array — an untagged row is byte-identical to the pre-tagging path, so old
/// docs/clients are unaffected.
@immutable
class ChatItem {
  const ChatItem({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAtMs,
    this.imageUrl,
    this.tags = const <WorkflowTag>[],
  });

  final String id;

  /// `'brandon'` (the owner — `HarnessConfig.ownerRole`) or `'orchestrator'`.
  final String role;
  final String text;
  final int createdAtMs;

  /// An attached image — a Storage download URL (Storage on) or a local file path
  /// (Storage off / mock, rendered on-device). Null when the message is text-only.
  final String? imageUrl;

  /// STRUCTURED tags on this message (HI-11). Additive + optional — empty for an
  /// untagged message, which then renders exactly as the text-only path always did.
  final List<WorkflowTag> tags;

  bool get hasImage => (imageUrl ?? '').isNotEmpty;

  /// Order-independent tag fingerprint (empty when untagged). Folded into the render
  /// signature so an IN-PLACE tag edit (same message id) surfaces its chip on the next
  /// poll without a new message / scroll-yank.
  String get tagFingerprint => workflowTagFingerprint(tags);

  ChatItem copyWith({List<WorkflowTag>? tags}) => ChatItem(
    id: id,
    role: role,
    text: text,
    createdAtMs: createdAtMs,
    imageUrl: imageUrl,
    tags: tags ?? this.tags,
  );

  /// JSON for the durable local store (mock/local path). Self-contained — carries
  /// its own [createdAtMs] so [fromMap] can rebuild it without any side channel.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'role': role,
    'text': text,
    'createdAtMs': createdAtMs,
    if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
    if (tags.isNotEmpty) 'tags': <Map<String, dynamic>>[for (final t in tags) t.toMap()],
  };

  /// Rebuild from a stored map (reads [createdAtMs] from the map itself). Tolerant
  /// of missing fields so an older/partial record can never crash the load.
  static ChatItem fromMap(Map<String, dynamic> m) => ChatItem(
    id: (m['id'] ?? '').toString(),
    role: (m['role'] ?? 'orchestrator').toString(),
    text: (m['text'] ?? '').toString(),
    createdAtMs: (m['createdAtMs'] as num?)?.toInt() ?? 0,
    imageUrl: m['imageUrl'] as String?,
    tags: WorkflowTag.listFrom(m['tags']),
  );
}
