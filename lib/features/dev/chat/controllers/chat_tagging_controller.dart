import '../../../../harness/harness_config.g.dart';
import '../models/workflow_tag.dart';
import '../services/chat_repository.dart';

/// The write engine for chat message-tagging (HI-11). Applies/removes tags across one
/// OR many selected messages via the [ChatRepository], then pokes + polls so the new
/// chip surfaces fast (the message controller's tag fingerprint re-renders just those
/// bubbles — no scroll-yank).
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic. Reads current tags + the
/// durable-doc guard through closures the screen supplies (backed by the message
/// controller), so it never names a concrete data source. Manual taps are always the
/// owner-role provenance ([HarnessConfig.ownerRole]) — never an auto-classifier.
class ChatTaggingController {
  ChatTaggingController({
    required this.repository,
    required this.uid,
    required this.currentTagsOf,
    required this.hasDurableDoc,
    required this.pollOnce,
    required this.snack,
  });

  final ChatRepository repository;
  final String uid;

  /// The structured tags currently on [msgId] (read from the live rendered set). Empty
  /// for an untagged or overlay-only message.
  final List<WorkflowTag> Function(String msgId) currentTagsOf;

  /// Whether [msgId] is a REAL durable message (not a push-overlay-only id). Patching an
  /// overlay-only id would create a junk doc (tags but no role/text) that pollutes the
  /// thread, so the write is guarded on this.
  final bool Function(String msgId) hasDurableDoc;

  /// Surface the chip fast (don't wait the full poll tick).
  final void Function() pollOnce;

  final void Function(String message) snack;

  /// The `(kind,id)`s [msgId] carries, filtered to [kind] — used by the picker to
  /// compute the common-across-selection checked state per dimension.
  Set<String> tagIdsOfKind(String msgId, String kind) => currentTagsOf(msgId)
      .where((t) => t.kind == kind)
      .map((t) => t.id)
      .toSet();

  /// Patch [msgId]'s tags to exactly [tags]. Guards a REAL durable doc first.
  Future<void> _writeMessageTags(String msgId, List<WorkflowTag> tags) async {
    if (!hasDurableDoc(msgId)) {
      snack('Message still syncing — try tagging again in a moment');
      return;
    }
    try {
      await repository.writeTags(uid: uid, msgId: msgId, tags: tags);
      pollOnce();
    } catch (_) {
      snack('Could not save tag');
    }
  }

  /// Add tag (`kind`,`tagId`) to [msgId] — idempotent on the `(kind,id)` PAIR. Manual
  /// taps are always owner-role provenance (never the auto-classifier).
  Future<void> applyTag(
    String msgId,
    String tagId, {
    String kind = 'workflow',
    String? label,
  }) async {
    final current = currentTagsOf(msgId);
    if (current.any((t) => t.id == tagId && t.kind == kind)) return;
    await _writeMessageTags(msgId, <WorkflowTag>[
      ...current,
      WorkflowTag(
        id: tagId,
        kind: kind,
        label: label,
        addedBy: HarnessConfig.ownerRole,
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
  }

  /// Remove the (`kind`,`tagId`) tag from [msgId]. A `workflow x` and a `chatgpt x` are
  /// independent — removing one leaves the other intact.
  Future<void> removeTag(
    String msgId,
    String tagId, {
    String kind = 'workflow',
  }) async {
    final current = currentTagsOf(msgId);
    if (!current.any((t) => t.id == tagId && t.kind == kind)) return;
    await _writeMessageTags(
      msgId,
      current.where((t) => !(t.id == tagId && t.kind == kind)).toList(),
    );
  }

  /// Apply a free-form conversation LABEL (`kind:'chatgpt'`, dimension b) to EVERY
  /// selected message, carrying [label] so the operator + a fresh device read the exact
  /// label. Sequential so each patch lands + the poll surfaces every new chip.
  Future<void> applyLabelToAll(
    List<String> msgIds,
    String labelId,
    String? label,
  ) async {
    for (final id in msgIds) {
      await applyTag(id, labelId, kind: 'chatgpt', label: label);
    }
  }

  /// Remove a conversation label from EVERY selected message.
  Future<void> removeLabelFromAll(List<String> msgIds, String labelId) async {
    for (final id in msgIds) {
      await removeTag(id, labelId, kind: 'chatgpt');
    }
  }

  /// Apply a workflow lane (`kind:'workflow'`, dimension a — gated) to EVERY selected
  /// message.
  Future<void> applyWorkflowToAll(List<String> msgIds, String workflowId) async {
    for (final id in msgIds) {
      await applyTag(id, workflowId);
    }
  }

  /// Remove a workflow lane from EVERY selected message.
  Future<void> removeWorkflowFromAll(
    List<String> msgIds,
    String workflowId,
  ) async {
    for (final id in msgIds) {
      await removeTag(id, workflowId);
    }
  }
}
