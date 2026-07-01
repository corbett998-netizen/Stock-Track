# MIC / VOICE PARITY — ported the reference EXACT mic, not the OS-dictation seam

**Scope:** Stock-Track (`/mnt/c/dev/Brandons_App`) only. The reference app was read
READ-ONLY as the pattern source; nothing in it was modified.

**Owner ruling (NON-NEGOTIABLE):** port the reference's EXACT mic implementation as the
reusable-harness standard — do NOT keep or substitute the weaker OS-dictation seam. This
REVERSES the earlier `CORRECTION_mic.md` "keep the OS `speech_to_text` seam" ADAPT decision
(its own §3.2 flagged that as an owner call). The OS seam is now removed.

---

## 1. What the reference ACTUALLY uses (the pattern I ported)

The reference's mic is an **app-owned, dual-engine, native voice subsystem** — deliberately
NOT the `speech_to_text` Flutter plugin. Its own code comments state why: that plugin is a
dependency pincer (its 7.x needs a `web` version that clashes with a Firebase-v2 host), and a
keyboard/OS mic can only feed a FOCUSED text field with the keyboard up — it cannot run while
the owner NAVIGATES the app to reproduce a bug. So the reference built its own recognizer.

**Package(s) / model:**
- A standalone reusable Dart package (`bp_voice` in the reference) — the engine-agnostic spine:
  `VoiceEngine` (swappable backend), `VoiceEvent` (sealed partial/final/status/error),
  `VoiceDictationController` (the one public entry: `isListening` / `liveTranscript` / `onFinal`).
- Engine A = the phone's native **Android `SpeechRecognizer`** over a platform channel (the
  PROVEN default). Engine B = a **bundled offline `sherpa_onnx`** streaming Zipformer transducer
  (int8 ~20M English model, downloaded + cached on first use), fed raw PCM by a native
  **`AudioRecord`** platform channel. `sherpa_onnx` is native/FFI (pulls only `ffi`, no `web`).

**Recording lifecycle:** app-owned + CONTINUOUS. The native recognizer finalizes after a short
silence and **re-arms** while the user still wants to listen, so dictation survives natural
pauses. Hard-won lessons baked into the native bridge (ported verbatim):
- REUSE one `SpeechRecognizer` for the whole session (destroy+create per utterance caused
  progressive sluggishness / cut-outs via repeated IPC binds).
- Tuned silence windows (1.8s) so a mid-sentence pause doesn't finalize (fewer re-arm seams).
- Session-restart detection in `onPartialResults` (a shrinking partial = the recognizer silently
  restarted → commit the prior words as a final) + flush-on-stop, so no phrase is lost.
- Per-session output-stream MUTE to suppress the recognizer's ready/end beep on every re-arm.
- On-device preference (API 31 on-device recognizer / `EXTRA_PREFER_OFFLINE`) with a sticky
  online fallback if the device has no offline language pack — never silently dead.
- `lastPartial` reset at USER start/stop boundaries so a prior turn can't prepend into the next.

**Transcription behaviour:** partials are transient (drive a live chip only); each FINAL is
appended to a text sink. `onFinal` means "append," not "stop." Turn accumulator resets only at
start/stop.

**How it populates the target:** a singleton `ChangeNotifier` voice SERVICE writes finals into a
session-scoped **report DRAFT** (model-sink, screen frozen at mic-start), NOT a focused field.
The report screen hydrates from that draft; the dev chat BORROWS the same recognizer and
snapshots/restores the draft so chat speech can never leak into a report.

---

## 2. What I ported into Stock-Track (generic / app-agnostic)

Every piece is a faithful port, renamed to carry ZERO app identity and driven by config.

**Reusable package — `packages/harness_voice/`** (mirror of the reference spine):
`voice_event.dart`, `voice_engine.dart`, `voice_dictation_controller.dart`, `pcm_audio_source.dart`,
`sherpa_model_manager.dart`, `engines/sherpa_onnx_engine.dart`. Depends on `sherpa_onnx: ^1.13.2`
(resolved 1.13.3). Added to the app pubspec as a path dep; `speech_to_text` REMOVED.

**Native Android bridges — `android/app/src/main/kotlin/com/stocktrack/stock_track/`:**
- `HarnessVoiceBridge.kt` — the `SpeechRecognizer` bridge (Engine A, the proven default).
- `MicPcmRecorder.kt` — the `AudioRecord` PCM source (feeds Engine B).
- `MainActivity.kt` — registers both + forwards the mic-permission result.
- Generic platform-channel names (`harness/voice_stt`, `harness/voice_pcm`) — no app noun.

**Dart harness module — `lib/features/dev/voice/`:**
- `harness_voice_config.dart` — `HarnessVoiceEngineKind` + `kHarnessVoiceEngine` (androidSystem
  default = one-flip rollback) + `kHarnessVoicePreferOnDevice` + the channel-name constants.
- `channel_pcm_audio_source.dart` — app-side PCM source over the native channel.
- `harness_report_draft.dart` — session draft (note + FROZEN screen + snapshot/restore).
- `harness_voice_service.dart` — the singleton dual-engine service (finals → draft).
- `harness_voice_button.dart` — the pulsing mic FAB (long-press A/Bs the engine; live chip).

`RECORD_AUDIO` was already declared in the Stock-Track manifest.

---

## 3. Cluster + report wiring (STEP 3)

- **MIC is now a button in the floating dev-tool cluster.** `HarnessToolSpec` gained an optional
  `builder` for STATEFUL in-place tools; the cluster renders the mic's own widget (constant
  footprint) instead of a tap-to-launch FAB. So the owner can start dictation **while staying on
  the screen being tested** — not buried inside a text field.
- **Mic → REPORT:** tapping the cluster mic starts app-owned dictation that streams into the
  shared `HarnessReportDraft`, freezing the current screen at mic-start. "File a report" hydrates
  from that draft; on submit the report is filed with the FROZEN screen as `region` and the draft
  is cleared. The report still carries `logsInline` + `appBuild` + `deviceInfo.platform` +
  screen-context (unchanged `fileReport`, now with an optional `region` override). An amber dot on
  the idle mic signals "dictation waiting to file" so the draft is discoverable from the cluster.
- **Chat** dictation migrated to the same recognizer via a ported borrow controller
  (`chat_voice_controller.dart`) that snapshots/restores the draft — chat speech never leaks into
  a report; typing tears the mic down cleanly.
- **Poke** button kept (owner isn't opposed), relabeled "Nudge orchestrator now" + given a muted
  slate colour so it no longer competes with the core report/mic/chat stack.

---

## 4. Generic (reusable framework) vs Stock-Track-specific

- **Generic / app-agnostic (drops into any harness app unchanged):** the whole `harness_voice`
  package, both native bridges (generic channel names; Kotlin package = the host app's own
  namespace), the voice config/service/draft/button, and the `HarnessToolSpec.builder` seam. None
  name a project id, collection, owner, or screen. Engine tuning is const config, not identity.
- **Stock-Track-specific (the app-layer integration points only):** the `kHarnessTools` entry that
  adds the mic; the report-capture screen wiring the draft into its note field + `region`; the
  chat composer's `onChanged`→teardown. These are exactly where an app plugs the generic seam in.

---

## 5. Gate results (this machine, 2026-07-01)

| Gate | Result |
| --- | --- |
| `flutter analyze lib test` (app) | **PASS** — No issues found (0) |
| `flutter analyze lib` (`packages/harness_voice`) | **PASS** — No issues found (0) |
| dependency-safety: `sherpa_onnx` pulls no `web` | **PASS** — deps = `[ffi, flutter, native .so]`; `pub get` resolved cleanly (no Firebase pincer in this project) |
| `flutter test` (whole suite) | **PASS** — 68/68 (removed 14 OS-seam turn tests, added 9 ported-logic tests incl. draft accumulator + `VoiceDictationController`) |
| `bash harness/harness_antileak_scan.sh` | **PASS** — 0 Blueprint literals, 53 files scanned |
| `flutter build apk --debug` — firebase (committed default) | **PASS** — built `app-debug.apk`; sherpa `.so` bundled per ABI |
| `flutter build apk --debug` — mock | **PASS** — built `app-debug.apk` (mode flipped, verified, reverted) |
| BP-identity sweep of package + native + `lib/features/dev/voice` | **PASS** — 0 hits |

**Sherpa native libs confirmed in the APK** (`libonnxruntime.so`, `libsherpa-onnx-c-api.so`,
`libsherpa-onnx-cxx-api.so` for arm64-v8a / armeabi-v7a / x86 / x86_64) — the offline engine is
really compiled in, not inert scaffolding. Debug fat-APK ~344 MB (all ABIs + debug + onnxruntime);
a release app-bundle with ABI splits + arm64-only shrinks this drastically, matching the reference's
+50–90 MB/device note.

---

## 6. On-device proof owed + flagged items (surfaced, not silently substituted)

On-device dogfood is the product-facing proof per doctrine (a green build/unit test is not
sufficient for a product-facing fix). What must be confirmed on the dev build:
- From the cluster mic ON a real screen: talk two sentences with a >2s pause → both land in the
  report draft in order; the mic stays "listening"; "File a report" shows them pre-filled with
  "Reporting on: <that screen>"; submit files with that screen as `region`.
- Deny mic permission → clean "Mic unavailable" message, no crash; grant → auto-starts.
- Chat mic dictates into the composer and NEVER mutates a real report draft; typing stops the mic.
- Long-press the mic (idle) A/Bs Phone ⇄ Offline; first Offline use downloads the model once then
  works in airplane mode (fully offline).

**Nothing was silently substituted.** One thing genuinely differs by environment, flagged not
hidden: the reference kept the OS plugin OUT to dodge a Firebase-v2 `web` pincer — this project's
newer Firebase has no such pincer, but the port keeps the native bridges anyway (that is the whole
point of "port the EXACT mic"). The offline model is DOWNLOADED on first use (reference default),
not pre-bundled as an asset; if a zero-network first-run is required, bundling the model as a
package asset is a follow-up (same code path, no API change).
