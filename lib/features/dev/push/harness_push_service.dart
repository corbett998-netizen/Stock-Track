import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
///   - [init] wires the three FCM delivery paths so a tap deep-links to the chat, and
///     initializes flutter_local_notifications so the FOREGROUND path also pops an OS
///     heads-up banner (Android does NOT auto-display an FCM `notification` while the app
///     is foregrounded — the app must post it itself):
///       * foreground  -> onMessage            (inject the carried message AND post a
///                                               local heads-up notification on the
///                                               config channel, so the banner pops while
///                                               the app is open — matching background).
///       * background  -> onMessageOpenedApp   (tapped while alive -> deep-link; the
///                                               banner itself is FCM's auto-notification).
///       * terminated  -> getInitialMessage()  (tapped from cold start -> deep-link
///                                               once the owner uid + navigator exist).
///     A tap on the foreground heads-up (flutter_local_notifications' response callback)
///     routes to the chat exactly like an FCM tap.
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

  /// flutter_local_notifications is the only way to pop an OS banner while the app is in
  /// the FOREGROUND (FCM auto-displays only in background/terminated). Created lazily in
  /// [init]; [_localNotifReady] gates every use so a plugin failure never breaks push.
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _localNotifReady = false;

  /// Monotonic id for each posted heads-up so successive replies stack rather than
  /// overwrite (kept small — Android tolerates reuse; this just avoids collisions).
  int _localNotifId = 0;

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

      // Prepare the local-notification plugin + channel so the foreground path can pop an
      // OS heads-up (FCM won't while foregrounded). Guarded — never blocks init.
      await _initLocalNotifications();

      // Foreground: FCM does not show a system notification while the app is in the
      // foreground — we inject the carried message so the chat updates live AND post a
      // local heads-up banner so the owner still gets the OS notification.
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

  /// Initialize flutter_local_notifications and ensure the high-importance channel exists
  /// so a FOREGROUND heads-up banner can be posted. The channel id + name come from config
  /// (never a hardcoded app noun); it mirrors the native channel created in MainActivity,
  /// and createNotificationChannel is idempotent so re-creating it is harmless. Fully
  /// guarded — a plugin failure leaves [_localNotifReady] false and push still works
  /// (chat overlay updates; background FCM notifications are unaffected).
  Future<void> _initLocalNotifications() async {
    try {
      // Reuse the app launcher icon (Android tints/masks it) — no new drawable needed,
      // matching the FCM default_notification_icon meta-data.
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      // iOS: don't prompt here (firebase_messaging.requestPermission owns the iOS prompt);
      // Android is the dogfood target. Kept so the module compiles cross-platform.
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      );
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleLocalTap,
      );

      // Create/ensure the high-importance channel (config id + config title as its name).
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final channel = AndroidNotificationChannel(
          HarnessConfig.pushAndroidChannelId,
          HarnessConfig.pushTitle,
          importance: Importance.high,
        );
        await android.createNotificationChannel(channel);
      }

      _localNotifReady = true;
      harnessLog.system(
        'push: local-notifications ready (channel ${HarnessConfig.pushAndroidChannelId})',
      );
    } catch (e) {
      harnessLog.system('push: local-notifications init error (non-fatal): $e');
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

      // Belt-and-suspenders on Android 13+: also ask via the local-notifications plugin.
      // POST_NOTIFICATIONS gates BOTH the FCM banner and our foreground heads-up; the OS
      // only prompts once, so a second call just returns the current status. Guarded.
      try {
        final androidNotif = _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final granted = await androidNotif?.requestNotificationsPermission();
        if (granted != null) {
          harnessLog.system('push: local-notif permission granted=$granted');
        }
      } catch (e) {
        harnessLog.system('push: local-notif permission error (non-fatal): $e');
      }

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

  /// A foreground message: inject the carried message so the chat renders it live, AND
  /// pop a local heads-up so the owner still gets the OS banner (FCM won't show one while
  /// the app is foregrounded).
  void _handleForeground(RemoteMessage message) {
    harnessLog.system('push: onMessage(fg) route=${message.data['route']}');
    _ingestCarried(message);
    _showForegroundNotification(message);
  }

  /// Post a heads-up notification for a foreground FCM message on the config channel,
  /// carrying the FCM `data` payload (JSON) so a tap deep-links to the chat. Prefers the
  /// FCM `notification` block for the title/body, falling back to the config title +
  /// carried text. No-op if the plugin isn't ready or there is nothing to show. Guarded.
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (!_localNotifReady) return;
    try {
      final data = message.data;
      final notif = message.notification;
      final title = (notif?.title?.trim().isNotEmpty ?? false)
          ? notif!.title!
          : HarnessConfig.pushTitle;
      final body = (notif?.body?.trim().isNotEmpty ?? false)
          ? notif!.body!
          : (data['text'] ?? '').toString();
      if (body.trim().isEmpty) return; // nothing meaningful to surface

      final androidDetails = AndroidNotificationDetails(
        HarnessConfig.pushAndroidChannelId,
        HarnessConfig.pushTitle,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      );
      await _localNotifications.show(
        _localNotifId++,
        title,
        body,
        details,
        payload: jsonEncode(data),
      );
      harnessLog.system('push: foreground heads-up shown');
    } catch (e) {
      harnessLog.system('push: foreground heads-up error (non-fatal): $e');
    }
  }

  /// Tap on the foreground heads-up (flutter_local_notifications response). Decode the
  /// carried FCM `data` payload, inject the message, and deep-link to the chat — the same
  /// destination as an FCM notification tap. Guarded; a bad payload still opens the chat.
  void _handleLocalTap(NotificationResponse response) {
    harnessLog.system('push: local-notif tap');
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          final data = <String, dynamic>{};
          decoded.forEach((k, v) => data[k.toString()] = v);
          _ingestCarried(RemoteMessage(data: data));
          final route = data['route'];
          if (route != null && route != HarnessConfig.pushDataRoute) {
            harnessLog.system('push: local-notif tap unknown route=$route');
          }
        }
      } catch (e) {
        harnessLog.system('push: local-notif payload decode error: $e');
      }
    }
    _requestOpenChat();
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
