import 'package:flutter/foundation.dart';

import '../chat/models/chat_item.dart';

/// Push-carried chat overlay — the FAST PATH that makes an orchestrator reply appear
/// the instant its FCM push arrives, independent of the Firestore stream.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic (no project nouns). Ported
/// from the reference harness's `OrchestratorChatInbox`.
///
/// WHY IT EXISTS (the reference-proven problem): on a real device the chat's Firestore
/// `snapshots()` Watch stream is not reliably real-time, and a foreground server re-get
/// can return stale/cached — so neither the live listener nor the poll surfaces an
/// orchestrator reply quickly. The ONE channel that reaches the phone at once is the FCM
/// push itself. So the orchestrator puts `{id, role, text, createdAtMs}` in the push
/// `data` payload, and the push handler drops it into THIS inbox the moment it arrives
/// (foreground `onMessage`, background-tap `onMessageOpenedApp`, cold-start
/// `getInitialMessage` — all run in the MAIN isolate). The chat screen listens here and
/// renders it within milliseconds.
///
/// Firestore stays the durable source of truth: the orchestrator writes the doc FIRST,
/// so when the poll/listener eventually delivers it the chat DEDUPES by the carried doc
/// [id] (the same id) — no duplicate bubble. The pushed entry is a pure overlay.
class HarnessChatInbox extends ChangeNotifier {
  HarnessChatInbox._();

  /// Process-lifetime singleton the push handler feeds and the chat screen listens to.
  static final HarnessChatInbox instance = HarnessChatInbox._();

  /// Keyed by doc id so a re-delivered push is idempotent and a Firestore doc with the
  /// same id can dedupe the overlay.
  final Map<String, ChatItem> _byId = <String, ChatItem>{};

  /// Keep the overlay bounded — it only ever needs the handful of messages that arrived
  /// faster than Firestore could deliver them; older ones are already in the durable
  /// thread.
  static const int _cap = 50;

  /// Current pushed messages (unordered; the chat controller sorts by createdAtMs).
  List<ChatItem> get messages => _byId.values.toList(growable: false);

  /// Whether a message with [id] is currently held in the overlay.
  bool contains(String id) => _byId.containsKey(id);

  /// Drop a push-carried message into the overlay. No-op (no notify) if [id] is empty
  /// or already present, so a duplicate FCM delivery never re-renders.
  void ingest({
    required String id,
    required String role,
    required String text,
    required int createdAtMs,
  }) {
    if (id.isEmpty) return;
    if (_byId.containsKey(id)) return;
    _byId[id] = ChatItem(
      id: id,
      role: role,
      text: text,
      createdAtMs: createdAtMs,
    );
    if (_byId.length > _cap) {
      // Evict the oldest by send time.
      final oldest = _byId.values.reduce(
        (a, b) => a.createdAtMs <= b.createdAtMs ? a : b,
      );
      _byId.remove(oldest.id);
    }
    notifyListeners();
  }

  /// Drop overlay entries whose id now appears in the durable thread — called by the
  /// chat controller once Firestore has caught up, so the overlay never double-renders
  /// a message the real stream already carries.
  void prune(Iterable<String> durableIds) {
    var changed = false;
    for (final id in durableIds) {
      if (_byId.remove(id) != null) changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Testing/hygiene hook — clear the overlay.
  @visibleForTesting
  void clear() => _byId.clear();
}
