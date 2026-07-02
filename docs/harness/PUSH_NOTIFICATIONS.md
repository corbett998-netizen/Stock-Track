# Harness Push Notifications — reusable parity capability

> Patterns-only. How the owner↔orchestrator PUSH capability works, why it exists, the
> generic-vs-app-specific split, how to transfer it to a new project, and exactly what
> the owner must enable in the Firebase console. No reference-repo internals.

## Why push is a harness standard (owner ruling)

Push is a **critical** part of the harness standard, not optional. The observed behaviour
in the reference harness: the in-app chat does not always visually update until it is
interacted with, **but an FCM push arrives on the phone immediately** — the owner taps it,
it opens the chat, and the chat refreshes to show the new message. This lane ports that as
a reusable, app-agnostic capability.

The delivered loop:

```
orchestrator replies (scripts/stocktrack_chat.js --send/--build)
   └─> writes the message doc to Firestore  (durable source of truth)
   └─> admin.messaging().send(...)  → FCM push to the owner's device token
          └─> phone notifies immediately (background/terminated: OS shows it)
                 └─> owner taps → app deep-links to the harness chat
                        └─> chat refreshes (server re-get) + the push-CARRIED
                            message renders instantly via the overlay
```

No Cloud Functions. The orchestrator sends the push itself with the Admin SDK over ADC
(`gcloud auth application-default` — permissions only, never a downloaded key).

---

## The reference (Blueprint) pattern — what it actually does

Studied read-only in the reference repo. Five load-bearing pieces:

1. **App registers for FCM.** On sign-in the app requests notification permission
   (gracefully — denial never crashes), calls `getToken()`, and stores the token at a
   per-user Firestore location (reference: `users/{uid}.fcmToken` + an updated-at). It
   re-stores on `onTokenRefresh`.

2. **Three delivery paths wired** so a tap always reaches the chat:
   - foreground → `FirebaseMessaging.onMessage` (FCM shows no system notification while
     foregrounded, so the app injects the carried message and, in the reference, renders a
     local notification);
   - background (alive) tap → `onMessageOpenedApp`;
   - terminated (cold start) tap → `getInitialMessage()`, deferred to after first frame.
   Navigation is keyed off `data['route']`.

3. **The push CARRIES the message.** The decisive latency fix: on a real device the
   Firestore Watch stream is not reliably real-time and a foreground server-get can return
   cached — so neither surfaces a reply quickly. The one channel that reaches the phone at
   once is the push. So the orchestrator puts `{id, role, text, createdAtMs}` in the FCM
   `data` payload; the handler drops it into a process-lifetime overlay (a `ChangeNotifier`
   singleton) the chat screen listens to → it renders in milliseconds. Firestore stays the
   durable store; the chat **dedupes by doc id** so the eventual Firestore doc doesn't
   double-render.

4. **Deep-link is a single-instance open.** The tap opens the chat through the same
   single-instance launcher the in-app chat button uses, so a repeat tap while the chat is
   already open is a no-op (no stacked duplicate screens).

5. **Orchestrator side sends the push.** In `chat.js`, after writing a reply/build message,
   `sendPush(text, meta)` reads the stored token and calls `admin.messaging().send({ token,
   notification:{title,body}, data:{route,id,role,text,createdAtMs},
   android:{priority:'high', notification:{channelId}} })`. It never throws — a push failure
   must not break the chat write; it is inert until a token exists.

---

## The reusable Stock-Track implementation

Everything below is **config-driven** — the framework modules name no app identity; the
app-specifics live in `harness/project.config.json`, `lib/main.dart`, and the Android
native files.

### Config (`harness/project.config.json` → generated `HarnessConfig`)

```jsonc
"push": {
  "title": "Stock-Track Ops",              // notification title
  "androidChannelId": "stocktrack_ops_channel",
  "dataRoute": "stocktrack_chat",          // data.route the app keys the deep-link on
  "tokenCollection": "${collections.chatRoot}",  // = orchestratorChat (harness's OWN collection)
  "tokenField": "fcmToken"                 // field on the {uid} doc that holds the token
}
```

Token location decision: the device token is stored on the harness's own
`orchestratorChat/{uid}` doc (field `fcmToken`), **not** a separate `users` collection —
it keeps all harness state in one collection and reuses the existing security-rule match.
The location is config-driven (`push.tokenCollection`/`push.tokenField`), generated into
`HarnessConfig.pushTokenCollection`/`pushTokenField`, and read by both the app and the
orchestrator, so no path is hardcoded.

### App side (Flutter)

- `lib/features/dev/push/harness_push_service.dart` — **generic framework** FCM service:
  registers the token (config-driven location), wires `onMessage` / `onMessageOpenedApp` /
  `getInitialMessage`, ingests the carried message, and deep-links via an **injected**
  `openChatSurface(uid)` hook (so the framework never imports a concrete screen). Handles
  the cold-start race: a tap that arrives before the owner uid resolves is remembered and
  fired once `registerForUser` lands.
- `lib/features/dev/push/harness_chat_inbox.dart` — **generic framework** carried-message
  overlay (`ChangeNotifier` singleton), bounded, keyed + deduped by doc id.
- `lib/features/dev/chat/controllers/chat_message_controller.dart` — merges the durable
  thread with the overlay (deduped by id, sorted by time) and prunes overlay entries once
  the durable stream carries them. Same new-message scroll/unread rules apply to a
  push-carried reply and its eventual Firestore doc.
- `lib/main.dart` — the **app-specific seam**: sets `openChatSurface` to open the concrete
  `OrchestratorChatScreen` via the shared single-instance launcher, and calls `init()`
  (dev builds + firebase mode only — push is harness infra; mock has no backend).
- `lib/features/dev/overlay/harness_fab_cluster.dart` — calls `registerForUser(uid)` once
  the owner uid resolves (dev-gated, guarded, once per uid).

FCM foreground display note: this port renders the foreground case via the **live
carried-message overlay** (the chat updates instantly when open) rather than a local OS
notification. The reference additionally shows a foreground OS notification via
`flutter_local_notifications`; that is a deliberate omission here to avoid the extra
dependency + native desugaring, since the owner's acceptance flow is the background tap
(the OS shows those automatically). Adding it later is a one-dependency add-on.

### Orchestrator side (`scripts/stocktrack_chat.js`)

`sendPush(text, meta, uid)` reads the token from `push.tokenCollection/{uid}.tokenField`
and calls `admin.messaging().send(...)` over **ADC (no key)**. It is called after both
`--send` and `--build` writes, carries `{id, role, text, createdAtMs}` for the instant
render, and never throws. The BP-abort guard covers the push config too, and `--selftest`
asserts the push config resolves with zero reference-repo literal.

### Android native

- `AndroidManifest.xml` — `POST_NOTIFICATIONS` permission (Android 13+ runtime prompt) +
  `default_notification_channel_id` / `default_notification_icon` meta-data.
- `MainActivity.kt` — creates the `stocktrack_ops_channel` notification channel (Android
  8+ drops notifications with no channel). Channel id/name are app identity in an app
  native file (legitimate — not framework).

---

## Generic-vs-app-specific boundary

| Generic framework (no app identity) | App-specific (names Stock-Track / the screen) |
| --- | --- |
| `harness_push_service.dart` (config-driven, hook-injected) | `main.dart` `_wireHarnessPush` — sets `openChatSurface` to the concrete chat screen + route |
| `harness_chat_inbox.dart` (overlay singleton) | `harness/project.config.json` `push.*` values |
| chat controller merge/dedupe | `MainActivity.kt` channel id/name; manifest meta-data value |
| `HarnessConfig.push*` accessors (generated) | orchestrator wiring calling `sendPush` after send/build |

Proven mechanically by `bash harness/harness_antileak_scan.sh` (framework modules carry
zero reference-repo literal; the `push/` files are in scope).

---

## Transfer to a new project

1. In `harness/project.config.json`, set the `push` block: `title`, `androidChannelId`,
   `dataRoute`, `tokenCollection` (default `${collections.chatRoot}`), `tokenField`. Run
   `node harness/gen_app_config.js` to regenerate `HarnessConfig`.
2. Add `firebase_messaging` (the line matching your `firebase_core` major — 16.x for
   firebase_core 4.x) and `flutter pub get`.
3. Android: add `POST_NOTIFICATIONS` + the two FCM meta-data lines to the manifest; create
   the channel in `MainActivity` with the same channel id/name as the config +
   `default_notification_channel_id`.
4. Wire `openChatSurface` + `init()` in `main.dart` (dev + firebase mode), and
   `registerForUser(uid)` where the owner uid resolves.
5. Deploy the security rule that lets the owner write their own token doc (see below).
6. Orchestrator: nothing extra — `sendPush` is already wired into `--send`/`--build` and
   reads the config token location.

The two framework files (`push/`) and the controller merge copy verbatim — only config +
the `main.dart`/native seams change.

---

## What the owner must enable in Firebase (console)

- **Cloud Messaging (FCM): auto-enabled with the project.** FCM/Cloud Messaging is
  available on every Firebase project by default — there is **no console toggle to flip**
  and no billing upgrade needed. The Admin SDK `messaging().send(...)` works as soon as the
  Android app config (`google-services.json`) is in place, which it already is
  (`android/app/google-services.json`, project `easy-stock-track`).
- **Security rule (already in `firestore.rules`, needs deploying):** the owner client must
  be allowed to write its own token doc. This lane changed the `orchestratorChat/{uid}` doc
  rule from read-only to `allow read, write: if signedIn() && request.auth.uid == uid`.
  Deploy: `firebase deploy --only firestore:rules --project easy-stock-track`.
- **Nothing else.** No APNs/iOS key is needed for the Android dogfood. (For iOS later, an
  APNs auth key in the console would be required — out of scope here.)
- **On-device:** the app asks for the notification permission at runtime (Android 13+); the
  owner taps **Allow** once.

---

## On-device validation checklist (owner acceptance)

Precondition: the wired build (firebase mode, live bridge, this push code) is on the phone,
the security rule above is deployed, and an operator loop is running `stocktrack_chat.js`.

1. Open the app, tap **Allow** on the notification permission prompt.
   - Verify: the token is stored — `orchestratorChat/{uid}` doc has an `fcmToken` field
     (operator can confirm via a Firestore read).
2. Background the app (go to the home screen).
3. Operator replies: `node scripts/stocktrack_chat.js --send "push test"`.
   - Verify: **the phone shows a "Stock-Track Ops" notification within a second or two.**
4. Tap the notification.
   - Verify: the app opens **directly to the orchestrator chat** (deep-link), and the
     **"push test" message is already shown** (carried-message overlay) and/or appears on
     the refresh — no manual pull needed.
5. Repeat with the app **foreground on a different screen**, then again **fully closed
   (terminated)** — the tap must open the chat and show the message in all three regimes.
6. Send a second reply while the chat is already open → it appears live (overlay), the chat
   auto-scrolls if near the bottom, and there is **no duplicate bubble** when Firestore
   catches up (dedupe by id).

PASS = steps 3–5 deliver a push, the tap opens the chat, and the new message shows.
