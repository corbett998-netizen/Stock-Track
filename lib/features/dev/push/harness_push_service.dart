import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../../../core/utils/harness_logger.dart';
import '../../../harness/harness_config.g.dart';
import 'harness_chat_inbox.dart';

/// Owner/operator harness PUSH-NOTIFICATION service — the reusable, app-agnostic
/// capability that makes an orchestrator reply notify the owner's phone immediately,
/// deep-link into the harness chat on tap, and refresh the thread.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK. It hardcodes NO project identity — the push
/// title, channel, deep-link route and the token storage location all come from the
/// generated [HarnessConfig] (project.config.json's `push.*`). The one app-specific
/// piece — WHICH chat surface to open on a tap — is INJECTED via [openChatSurface] at
/// the app wiring seam (lib/main.dart), so this module never imports a concrete screen.
///
/// Ported from the reference harness's push service. What it does:
///   - [registerForUser] requests notification permission (gracefully), fetches the FCM
///     token, stores it at `HarnessConfig.pushTokenCollection/{uid}` field
///     `HarnessConfig.pushTokenField`, and re-stores on token refresh.
///   - [init] wires the three FCM delivery paths so a tap deep-links to the chat:
///       * foreground  -> onMessage            (inject the carried message; the chat
///                                               renders it live — no OS notification is
///                                               shown by FCM while foregrounded).
///       * background  -> onMessageOpenedApp   (tapped while alive -> deep-link).
///       * terminated  -> getInitialMessage()  (tapped from cold start -> deep-link
///                                               once the owner uid + navigator exist).
///
/// Every entry point is wrapped in try/catch — a push-subsystem failure must NEVER
/// block app launch or sign-in.

/// Top-level background message handler. firebase_messaging REQUIRES this to be a
/// top-level (or static) function, not a closure — for a data/notification message
/// received while the app is backgrounded/terminated it runs in a separate isolate.
/// Kept intentionally light: Android auto-displays a message that carries a
/// `notification` payload, so there is nothing to render here; the TAP is handled by
/// onMessageOpenedApp / getInitialMessage on resume.
@pragma('vm:entry-point')
Future<void> harnessFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  // No Firebase init / heavy work here — logging only (release-gated).
  harnessLog.system(
    'push: background msg ${message.messageId} route=${message.data['route']}',
  );
}

class HarnessPushService {
  HarnessPushService._();
  static final HarnessPushService instance = HarnessPushService._();

  /// App-wired action that opens the harness chat surface for [uid]. Set once at the
  /// app wiring seam (lib/main.dart). Kept out of this framework module so no concrete,
  /// app-specific screen is imported here. Null → deep-link is a no-op (logged).
  void Function(String uid)? openChatSurface;

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedSub;

  /// The uid we currently have a token stored against — set by [registerForUser] so a
  /// token-refresh writes to the right user's doc and a deep-link opens the right thread.
  String? _activeUid;

  /// A deep-link tap arrived before the owner uid was known (cold start). Fire it the
  /// moment [registerForUser] resolves the uid.
  bool _pendingOpenChat = false;

  /// Attach the static handlers. Idempotent; safe to call every launch. Does NOT request
  /// permission or fetch a token — that happens in [registerForUser] once a uid exists.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      // The background handler must be registered before runApp completes; call init()
      // from main() (pre-runApp).
      FirebaseMessaging.onBackgroundMessage(
        harnessFirebaseMessagingBackgroundHandler,
      );

      // Foreground: FCM does not show a system notification while the app is in the
      // foreground — we inject the carried message so the chat updates live.
      _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForeground);

      // App was in the background (alive) and the user tapped the notification.
      _onOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

      // App was terminated and launched by tapping the notification.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _handleOpened(initial);
      }

      harnessLog.system('push: init complete (handlers attached)');
    } catch (e) {
      harnessLog.system('push: init error (non-fatal): $e');
    }
  }

  /// Request permission (gracefully), fetch the FCM token, store it at the config-driven
  /// token location, and subscribe to token refresh. Safe to call repeatedly (e.g. once
  /// the owner uid resolves) — it re-points the active uid and re-writes the token.
  /// Fully guarded; never throws.
  Future<void> registerForUser(String uid) async {
    final firstUid = _activeUid == null;
    _activeUid = uid;
    try {
      await init();

      final messaging = FirebaseMessaging.instance;

      // Graceful permission request. On Android 13+ this shows the runtime
      // POST_NOTIFICATIONS prompt; pre-13 it's a no-op grant. Denial is fine — we still
      // try to fetch a token so a later opt-in works without re-registering.
      final settings = await messaging.requestPermission();
      harnessLog.system('push: permission ${settings.authorizationStatus}');

      final token = await messaging.getToken();
      if (token == null) {
        harnessLog.system('push: getToken returned null — skipping store');
      } else {
        await _storeToken(uid, token);
        // Re-subscribe the refresh listener against the current uid.
        await _tokenRefreshSub?.cancel();
        _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) {
          final active = _activeUid;
          if (active != null) _storeToken(active, newToken);
        });
      }
    } catch (e) {
      harnessLog.system('push: registerForUser error (non-fatal): $e');
    }

    // A cold-start deep-link that arrived before the uid was known now has its uid.
    if (_pendingOpenChat && firstUid) {
      _pendingOpenChat = false;
      _requestOpenChat();
    }
  }

  /// Write the token to `pushTokenCollection/{uid}` field `pushTokenField` (+ an
  /// updated-at). Merge so we never clobber other fields on the doc.
  Future<void> _storeToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance
          .collection(HarnessConfig.pushTokenCollection)
          .doc(uid)
          .set(
            <String, dynamic>{
              HarnessConfig.pushTokenField: token,
              '${HarnessConfig.pushTokenField}UpdatedAt':
                  FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
      final tail = token.length > 8 ? token.substring(token.length - 8) : token;
      harnessLog.system('push: stored token for $uid (…$tail)');
    } catch (e) {
      harnessLog.system('push: store token error (non-fatal): $e');
    }
  }

  /// A foreground message: inject the carried message so the chat renders it live.
  void _handleForeground(RemoteMessage message) {
    harnessLog.system('push: onMessage(fg) route=${message.data['route']}');
    _ingestCarried(message);
  }

  /// A tapped notification (background/terminated) — inject the carried message, then
  /// deep-link to the chat so it shows the instant it opens.
  void _handleOpened(RemoteMessage message) {
    harnessLog.system('push: opened(tap) route=${message.data['route']}');
    _ingestCarried(message);
    final route = message.data['route'];
    if (route != null && route != HarnessConfig.pushDataRoute) {
      harnessLog.system('push: tap with unknown route=$route — opening chat');
    }
    _requestOpenChat();
  }

  /// Drop a push-carried chat message into the [HarnessChatInbox] overlay so the chat
  /// renders it immediately, bypassing the unreliable Firestore stream. No-op for a push
  /// that doesn't carry the payload (id/text absent) — those still deep-link and the poll
  /// eventually delivers the durable doc.
  void _ingestCarried(RemoteMessage message) {
    try {
      final data = message.data;
      final id = (data['id'] ?? '').toString();
      final text = (data['text'] ?? '').toString();
      if (id.isEmpty || text.isEmpty) return;
      final role = (data['role'] ?? 'orchestrator').toString();
      final createdAtMs =
          int.tryParse((data['createdAtMs'] ?? '').toString()) ??
          DateTime.now().millisecondsSinceEpoch;
      HarnessChatInbox.instance.ingest(
        id: id,
        role: role,
        text: text,
        createdAtMs: createdAtMs,
      );
      harnessLog.system('push: ingested carried msg id=$id role=$role');
    } catch (e) {
      harnessLog.system('push: ingest error (non-fatal): $e');
    }
  }

  /// Open the harness chat via the app-wired [openChatSurface], once the owner uid is
  /// known and a navigator exists. If the uid hasn't resolved yet (cold start), remember
  /// the intent and fire it from [registerForUser].
  void _requestOpenChat() {
    final uid = _activeUid;
    if (uid == null) {
      _pendingOpenChat = true;
      return;
    }
    final open = openChatSurface;
    if (open == null) {
      harnessLog.system('push: no openChatSurface wired — deep-link skipped');
      return;
    }
    // Defer to the next frame so a cold-start navigator is mounted before we push.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        open(uid);
      } catch (e) {
        harnessLog.system('push: open chat error (non-fatal): $e');
      }
    });
  }

  /// Tear down subscriptions (handy for tests; not normally needed for the singleton).
  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _onMessageSub?.cancel();
    await _onOpenedSub?.cancel();
    _tokenRefreshSub = null;
    _onMessageSub = null;
    _onOpenedSub = null;
  }
}
