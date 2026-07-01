import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/utils/harness_logger.dart';
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

  List<ChatItem> _items = const <ChatItem>[];
  bool _loaded = false;
  Object? _loadError;
  String? _lastSig;
  String? _lastNewestId;
  bool _hasUnreadBelow = false;

  List<ChatItem> get items => _items;
  bool get loaded => _loaded;
  Object? get loadError => _loadError;
  bool get hasUnreadBelow => _hasUnreadBelow;

  void clearUnread() {
    if (_hasUnreadBelow) {
      _hasUnreadBelow = false;
      notify();
    }
  }

  /// Attach to [uid]: open the live listener + start the foreground poll.
  /// Idempotent per-uid so `build` can call it freely.
  void attach(String uid) {
    if (_uid == uid && _sub != null) {
      _pollTimer ??= _startPoll(uid);
      return;
    }
    _subscribe(uid);
    _pollTimer = _startPoll(uid);
    pollOnce(uid);
  }

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

  void _onItems(List<ChatItem> items) {
    final sig = _sigOf(items);
    final firstLoad = !_loaded;
    // A passive re-emission of the same set must be invisible (no flicker/yank).
    if (!firstLoad && sig == _lastSig) return;

    final newest = items.isNotEmpty ? items.last : null;
    final newestId = newest?.id ?? '-';
    final newestRole = newest?.role ?? '-';

    // Decide the scroll intent BEFORE the list mutates.
    final wasNearBottom = isNearBottom();
    final isNewMessage = !firstLoad && newestId != _lastNewestId;
    final isOwnSend = newestRole == 'brandon';

    if (firstLoad) {
      harnessLog.chat('receive: loaded ${items.length} msgs');
    } else if (isNewMessage) {
      harnessLog.chat('receive: new msg from $newestRole');
    }

    _lastSig = sig;
    _lastNewestId = newestId;
    _items = items;
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
    _sub?.cancel();
    stopPoll();
  }
}
