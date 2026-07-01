# Chunk 5 — Rich Capture (image/file/screenshot + mic)

**Parity map:** `docs/harness/HARNESS_PARITY_MAP.md` §5 Chunk 5 + §8 (mic adapted; chat image = fast-follow gated on Storage).
**Date:** 2026-07-01 · **Lane:** Stock-Track harness-parity implementation (Package B).
**Result:** PASS — `flutter analyze` 0 issues · `flutter test` 37/37 · `flutter build apk --debug` OK (both modes) · antileak PASS (39 files).

---

## What this chunk proves (+ what is deliberately gated)

The capture affordances the owner named are present + mock-testable:

- **image attach in chat** (staged strip → inline bubble image → tap-to-zoom);
- **screenshot attach on reports** rendered on-device + a **full-screen pinch-zoom
  gallery**;
- **mic dictation** into both the chat composer and the report note (OS speech seam);
- **submit-success report-ID with a copy button**.

**Storage is deliberately OFF** in easy-stock-track for the first proof (Pete). So
attachments are **fully functional in mock mode** (staged + rendered locally) and
**Storage-gated with graceful degrade** in firebase mode — no crash, a clear "Storage
off" state. **Live upload lands the moment Brandon enables Storage** (one flag flip;
the upload seam is already wired). This is the one item §8 calls a legitimate
fast-follow.

## Reference PATTERN (abstract, app-agnostic)

- **Image + file attachments** (send from phone, render inline, tap-to-zoom) — how a
  non-coder shows a visual bug/reference. **Device-log tail already lands (Chunk 2);**
  this adds the visual channel.
- **Voice/mic dictation** into the composer + mic-to-report — "talk to your phone".
  ADAPTED to the OS speech seam; the reference's bundled offline dual-engine + A/B
  toggle is DON'T-PORT.
- **Note + multi-screenshot capture, uploaded owner-scoped**, with a **full-screen
  gallery / pinch-zoom** to read a bug screenshot on a phone.
- **Submit-success with a short report ID + copy** so the owner can reference the
  report in chat.

## Stock-Track IMPLEMENTED behavior (file + what)

| Pattern | File | What |
|---|---|---|
| Storage gate | `dev_gate.dart` | `kHarnessStorageEnabled = false` — the ONLY switch; while false, NO upload is attempted anywhere. |
| Mic seam | `core/utils/harness_speech.dart` (**new**) | thin `speech_to_text` wrapper; `ensureAvailable()` never throws (degrades to false); partial + final transcript callbacks. |
| Chat upload seam | `chat/services/chat_upload_service.dart` (**new**) | `resolve(XFile)` → local path when Storage off, upload → URL when on, local fallback on live-upload failure; path prefix from `HarnessConfig.chatRoot`. |
| Screenshot resolve gate | `report_capture/services/screenshot_upload_service.dart` | Storage off → local descriptor `{localPath,bytes,contentType,storageOff}`; on → upload; live-fail degrades to local (report never lost). |
| Chat image UI | `chat/widgets/chat_composer.dart` | attach button (gated: mock always, firebase-off shows "Storage off"), mic button, staged-image strip. |
| Chat mic + staging + send | `chat/controllers/chat_compose_controller.dart` | mic toggle; `stage/clearStaged`; send resolves the attachment + allows image-only sends; disposes the mic. |
| Inline image + zoom | `chat/widgets/chat_bubble.dart` | renders URL/local image inline; `showChatImageZoom` (full-screen `InteractiveViewer`). |
| Model | `chat/models/chat_item.dart` | `imageUrl` + `hasImage`. Repo `sendMessage(imageSource)` (Firebase writes `imageUrl`, reads it back; Mock carries it). |
| Report mic + report-ID | `report_capture/screens/report_capture_screen.dart` | mic-to-note (Dictate/Stop); submit-success dialog with a short, copyable report ID (`fileReport` now returns the id). |
| Report image render + gallery | `report_queue/widgets/report_image.dart` (**new**) | `ReportImage` (remote/local/placeholder) + `showScreenshotGallery` (full-screen pinch-zoom PageView). Wired into `report_detail.dart` (tap → gallery) + `report_card.dart` (thumb). |
| Model localPath | `report_queue/models/report.dart` | resolves a `{localPath}` screenshot entry. |
| Native permissions | `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` | `RECORD_AUDIO` + speech `<queries>`; `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription`. |
| Package | `pubspec.yaml` | `speech_to_text`. |

## Acceptance results (command output)

```
flutter analyze            → No issues found! (ran in 2.1s)
flutter test               → All tests passed!  (37/37)
  new (Chunk 5): ChatUploadService returns local path when Storage off + null for
  no attachment; Report resolves a localPath screenshot; ChatItem.hasImage.
flutter build apk --debug  → √ Built app-debug.apk   (firebase mode)  [incl. speech plugin + RECORD_AUDIO]
flutter build apk --debug  → √ Built app-debug.apk   (mock mode, then reverted)
harness/harness_antileak_scan.sh → ANTILEAK RESULT: PASS | 0 Blueprint literals | 39 files
```

Acceptance bullets (parity map §5 Chunk 5):
- [x] owner sends an image in chat → renders inline (mock: local; firebase: gated) —
  **mock-testable on-device**;
- [x] dictates a report/message by voice (OS speech seam; graceful "mic unavailable");
- [x] sees a copyable report-ID on submit;
- [x] pinch-zooms a report screenshot (full-screen gallery) + a chat image.

> Upload FORMATTERS/gates are unit-proven; picker/mic/render wiring is compile-proven
> both modes + is an on-device dogfood check. The mic + local-image render need a real
> device (mic permission + a real file); the storage-off path never touches Storage.

## Anti-leak / separation

- `harness/harness_antileak_scan.sh` → **PASS** (0 Blueprint literals, 39 files incl.
  3 new files).
- No backend key/token; upload seam is client-side `firebase_storage` (still ADC-free
  on-device / Storage-gated).

## GENERIC vs STOCK-TRACK-SPECIFIC (reuse boundary)

- **GENERIC framework (reusable, no app identity):** `harness_speech.dart`,
  `chat_upload_service.dart`, `screenshot_upload_service.dart` gate, `report_image.dart`,
  the composer/bubble/capture UI, and the `kHarnessStorageEnabled` switch. Paths are
  built from `HarnessConfig.chatRoot` / `HarnessConfig.reportsCollection` (config).
- **STOCK-TRACK-SPECIFIC (wiring/config only):** the native permission strings live in
  Stock-Track's own `AndroidManifest.xml` / `Info.plist` (every host app owns these);
  the collection/chat-root names are config. A future 3rd app reuses the seams verbatim
  + its own manifest entries + config.

## Deferred (intentional, per parity map / §8)

- **LIVE Storage upload** — gated on Brandon enabling Storage in easy-stock-track
  (flip `kHarnessStorageEnabled` → true; seam already wired). Until then: mock-local +
  a clear firebase "Storage off" state.
- **Non-image file/doc sharing** in chat + operator→owner doc push — the trailing edge
  (§8); image is the named must.
- Bundled offline speech engine + A/B toggle — DON'T-PORT (OS seam proves it).
- Draft minimize/resume; log-percent selector.
