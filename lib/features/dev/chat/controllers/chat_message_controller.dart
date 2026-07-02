import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/utils/harness_logger.dart';
import '../../push/harness_chat_inbox.dart';
import '../models/chat_item.dart';
import '../services/chat_repository.dart';

/// The live-message engine for the owner↔orchestrator chat. Ported from
/// Blueprint's `ChatMessageController`, trimmed to the Stock-Track slice (BP's push
/// overlay, unread-badge service, workflow tagging + latency log are DEFERRED).
///
/// The load-bearing behaviour BP proved is KEPT: a single stable listener (instant
/// for the owner's own local writes) PLUS a ~3s foreground SERVER re-get poll —
/// because on a real device the Firestore Watch stream is not reliably real-time,
/// so the poll is the deterministic lever that surfaces the orchestrator's reply
/// within one interval. Also kept: decide the scroll intent against the PRE-update
/// layout, and never yank the owner if he's scrolled up reading history.
class ChatMessageController {
  ChatMessageController({
    required this.repository,
    required this.notify,
    required this.isNearBottom,
    required this.autoScroll,
  });

  final ChatRepository repository;
  final VoidCallback notify;
  final bool Function() isNearBottom;
  final VoidCallback autoScroll;

  static const Duration _pollInterval = Duration(seconds: 3);

  StreamSubscription<List<ChatItem>>? _sub;
  Timer? _pollTimer;
  String? _uid;
  bool _pollInFlight = false;

  /// The durable (Firestore/mock) thread, oldest→newest. The rendered [items] merge
  /// this with the push-carried overlay ([HarnessChatInbox]) so an orchestrator reply
  /// shows the instant its FCM push arrives, before the stream/poll catches up.
  List<ChatItem> _items = const <ChatItem>[];
  bool _loaded = false;
  Object? _loadError;
  String? _lastSig;
  String? _lastNewestId;
  bool _hasUnreadBelow = false;
  bool _inboxAttached = false;

  /// The rendered thread = durable items + any push-carried overlay entry not yet in the
  /// durable set, sorted oldest→newest. Dedupe is by doc id (the carried message and its
  /// eventual Firestore doc share the id), so a reply never double-renders.
  List<ChatItem> get items {
    final overlay = HarnessChatInbox.instance.messages;
    if (overlay.isEmpty) return _items;
    final durableIds = _items.map((i) => i.id).toSet();
    final merged = <ChatItem>[
      ..._items,
      ...overlay.where((m) => !durableIds.contains(m.id)),
    ]..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    return merged;
  }

  bool get loaded => _loaded;
  Object? get loadError => _loadError;
  bool get hasUnreadBelow => _hasUnreadBelow;

  void clearUnread() {
    if (_hasUnreadBelow) {
      _hasUnreadBelow = false;
      notify();
    }
  }

  /// Attach to [uid]: open the live listener + start the foreground poll, and subscribe
  /// to the push-carried overlay so an FCM-delivered reply renders instantly.
  /// Idempotent per-uid so `build` can call it freely.
  void attach(String uid) {
    if (!_inboxAttached) {
      HarnessChatInbox.instance.addListener(_onInboxChanged);
      _inboxAttached = true;
    }
    if (_uid == uid && _sub != null) {
      _pollTimer ??= _startPoll(uid);
      return;
    }
    _subscribe(uid);
    _pollTimer = _startPoll(uid);
    pollOnce(uid);
  }

  /// The push overlay changed (an FCM-carried reply arrived) — re-render the merged
  /// thread, applying the same new-message scroll/unread rules as a durable update.
  void _onInboxChanged() => _apply();

  void _subscribe(String uid) {
    _sub?.cancel();
    _uid = uid;
    _sub = repository
        .watchMessages(uid)
        .listen(
          _onItems,
          onError: (Object e) {
            if (!_loaded) {
              _loadError = e;
              notify();
            }
          },
        );
  }

  Timer _startPoll(String uid) =>
      Timer.periodic(_pollInterval, (_) => pollOnce(uid));

  void stopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// App resumed with the chat open — re-open the listener + restart the poll.
  void resume() {
    final uid = _uid;
    if (uid != null) {
      _subscribe(uid);
      _pollTimer = _startPoll(uid);
      pollOnce(uid);
    }
  }

  void pauseBackground() => stopPoll();

  /// One server re-get (the deterministic delivery lever). Fire-and-forget +
  /// in-flight guarded so weak signal can never pile up requests.
  void pollOnce(String uid) {
    if (_pollInFlight) return;
    _pollInFlight = true;
    unawaited(() async {
      try {
        final items = await repository
            .fetchMessages(uid)
            .timeout(const Duration(seconds: 8));
        _onItems(items);
      } catch (_) {
        // swallow — the listener + next tick recover.
      } finally {
        _pollInFlight = false;
      }
    }());
  }

  /// A durable (stream/poll) emission landed — adopt it, drop any overlay entry it now
  /// carries (dedupe), then re-render the merged thread.
  void _onItems(List<ChatItem> items) {
    _items = items;
    _apply();
    // Memory hygiene: an overlay entry the durable stream now carries is redundant.
    HarnessChatInbox.instance.prune(items.map((i) => i.id));
  }

  /// Recompute the rendered (merged durable + overlay) thread and apply the new-message
  /// scroll/unread rules. Funnelled by both the durable stream and the push overlay so
  /// an FCM-carried reply and its eventual Firestore doc behave identically (deduped by
  /// id, so no double bubble / double scroll).
  void _apply() {
    final merged = items;
    final sig = _sigOf(merged);
    final firstLoad = _lastSig == null;
    // A passive re-emission of the same set must be invisible (no flicker/yank).
    if (!firstLoad && sig == _lastSig) return;

    final newest = merged.isNotEmpty ? merged.last : null;
    final newestId = newest?.id ?? '-';
    final newestRole = newest?.role ?? '-';

    // Decide the scroll intent BEFORE the list mutates.
    final wasNearBottom = isNearBottom();
    final isNewMessage = !firstLoad && newestId != _lastNewestId;
    final isOwnSend = newestRole == 'brandon';

    if (firstLoad) {
      harnessLog.chat('receive: loaded ${merged.length} msgs');
    } else if (isNewMessage) {
      harnessLog.chat('receive: new msg from $newestRole');
    }

    _lastSig = sig;
    _lastNewestId = newestId;
    _loaded = true;
    _loadError = null;
    notify();

    if (firstLoad || (isNewMessage && (wasNearBottom || isOwnSend))) {
      if (_hasUnreadBelow) _hasUnreadBelow = false;
      autoScroll();
    } else if (isNewMessage && !_hasUnreadBelow) {
      _hasUnreadBelow = true;
      notify();
    }
  }

  String _sigOf(List<ChatItem> items) =>
      '${items.length}:${items.map((i) => i.id).join(',')}';

  void dispose() {
    if (_inboxAttached) {
      HarnessChatInbox.instance.removeListener(_onInboxChanged);
      _inboxAttached = false;
    }
    _sub?.cancel();
    stopPoll();
  }
}
