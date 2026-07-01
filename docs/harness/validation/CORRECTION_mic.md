# CORRECTION — MIC group (voice dictation: mic-to-report + mic-to-chat)

**Scope:** Stock-Track (`/mnt/c/dev/Brandons_App`) only. No Blueprint files touched.
**One correction:** raise the OS speech seam from **single-shot** to the reference's
**CONTINUOUS-DICTATION** contract. The engine choice (OS `speech_to_text`) is KEPT — the parity
study confirmed the bundled offline dual-engine + A/B toggle is a correct **DON'T-PORT** and the OS
seam already reaches parity with the reference's DEFAULT engine (which is itself the OS recognizer).
The single-shot behaviour was an **un-caught fidelity gap**, not a signed-off adaptation.

---

## 1. What was wrong (verified against the code)

`lib/core/utils/harness_speech.dart` did one `_stt.listen(...)` with only
`SpeechListenOptions(partialResults: true)` — no re-arm, no `pauseFor`/`listenFor`/`listenMode`.
`speech_to_text` 7.x does **not** auto-restart across pauses, so the session **ended at the first
natural pause** — the opposite of the reference's re-arm contract.

Both callers made it worse:
- `chat_compose_controller.toggleMic()` and `report_capture_screen._toggleMic()` set `_listening =
  false` **inside `onFinal`**, so the mic UI flipped OFF after ONE utterance.
- Each captured `_micBase` **once** at toggle-on and did `text = _micBase + ' ' + t` on every result;
  a second utterance would have **overwritten** the first (no advance-base-on-final).

Net: tap mic → say one sentence → it stops. There was no on-device preference, no turn-boundary
reset, no flush-on-stop — none bit *today* only because the seam was single-shot; all become live the
moment continuous capture is added.

## 2. What changed

**All work is in ONE app-agnostic file + the two thin UI callers. No new package, no native code.**

### `lib/core/utils/harness_speech.dart` (the seam) — rewritten to the continuous contract
- **`HarnessSpeechOptions`** (new, in-file) — config-driven tuning, no magic literals: `continuous`
  (default true), `preferOnDevice` (default false), `pauseFor` (default 3s), `listenFor` (default
  10m). Mirrors the reference's `kVoiceEngine`/`kVoicePreferOnDevice` const-config pattern.
- **`HarnessSpeechTurn`** (new, in-file, **pure/platform-free**) — owns the turn accumulator so the
  load-bearing rules are unit-testable without the OS engine: base + finalised run + live partial,
  dedup-guarded append, seam-recovery (`flushPartial`), and turn-boundary `reset`.
- **`HarnessSpeech`** now implements:
  - **Listening INTENT** (`ValueNotifier<bool>`, exposed as `isListening` + `listening` +
    `onListeningChanged`) separate from the engine's momentary `isListening`, so the FAB stays
    "listening" **across re-arms** and is never inferred from a single final.
  - **Re-arm loop** — an `onStatus` handler re-calls `listen(...)` when a session ends
    (`notListening`/`done`) while the user still wants to listen and there is no permanent error.
    `SpeechListenOptions(partialResults: true, listenMode: ListenMode.dictation, onDevice: <config>,
    cancelOnError: false, pauseFor, listenFor)` with a long `listenFor`/generous `pauseFor` so one
    OS session runs as long as allowed (fewer re-arms = fewer seams = fewer tones).
  - **Callback contract flip** — `onFinal` now means "an utterance finalised — append it," NOT
    "stop." The seam owns base+append; the caller just renders the emitted transcript.
  - **Turn-boundary reset + flush-on-stop** — the accumulator resets only at `start()`/`stop()`
    (never on an internal re-arm), and `stop()` flushes the in-flight partial (dedup-guarded) so a
    tap-off mid-sentence keeps its words.
  - **Seam recovery** — a session that ended without finalising its last partial commits those words
    on re-arm, so nothing is lost at a session seam.
  - **Graceful degradation intact** — `ensureAvailable()` never throws; a permanent error (permission
    denied) ends the turn and surfaces a clean message; transient errors are ignored so continuous
    capture isn't killed by a routine no-match.
  - **Fast-fail guard** — if sessions keep dying immediately (recognizer can't stay up), it stops
    cleanly after 6 fast restarts rather than loop/beep forever.

### `chat_compose_controller.dart` + `report_capture_screen.dart` (the two callers)
- Removed the `_listening = false` in `onFinal` and the `_micBase` field. The mic UI is now driven by
  the seam's `onListeningChanged`; the caller passes `base: <current text>` and renders `onTranscript`
  (`controller.text = t`). Permanent errors surface via `onError`. The existing send/submit auto-stop
  (`if (_listening) await toggleMic()/_toggleMic()`) is kept.

## 3. Owner-decision flags (surfaced, not silently shipped)

1. **DON'T-PORT the bundled offline engine — CONFIRMED correct.** The sherpa-onnx path is a whole
   standalone package + native FFI `.so` per ABI + a tens-of-MB model download + a native AudioRecord
   PCM source + a runtime A/B toggle. The reference built it only to escape a Firebase-v2 `web`
   dependency pincer **this project does not have** (it uses `speech_to_text ^7.4.0` cleanly), and the
   reference's DEFAULT engine is still the OS recognizer. On-device preference is preserved via the
   `preferOnDevice` config knob (`SpeechListenOptions.onDevice`) without the heavy package.
   **Recommendation: keep DON'T-PORT.** (No TODO owed — this is the conscious, now-reinforced ADAPT.)

2. **"Dictate while navigating to reproduce" is NOT delivered by a field-scoped seam — deferred.**
   This correction ships **field-scoped CONTINUOUS** capture (closes the real, un-caught single-shot
   gap on the report + chat screens). The reference's headline "dictate the bug even while navigating
   to reproduce it" needs a model-sink report DRAFT + a GLOBAL mic FAB + a live transcript chip (its
   sibling "mic + draft frozen to screen" is already DEFER in the parity map). **TODO / owner call**
   (`// TODO(mic)` in `harness_speech.dart` header + here): is field-scoped dictation enough for the
   harness's report/chat screens, or is navigate-while-dictating a required harness capability? If the
   owner wants the full headline, it is a scoped follow-up — do not build blind.

3. **Beep on re-arm — possible on-device follow-up.** A naive re-arm loop can re-trigger the OS
   recogniser's ready/end tone each cycle. Mitigated here by minimising restarts (long
   `listenFor`/generous `pauseFor`). If audible beeping still shows up on-device, the minimal port is
   the reference's session-scoped stream-mute in a tiny native seam — **verified by ear, not
   assumed.** Flagged, not pre-built.

## 4. Gate results (this machine, 2026-07-01)

| Gate | Result |
| --- | --- |
| `flutter analyze` (changed files) | **PASS** — No issues found (0) |
| `flutter analyze` (whole project) | **PASS** — No issues found (0) |
| `bash harness/harness_antileak_scan.sh` | **PASS** — 0 Blueprint literals, 47 files scanned |
| `flutter test` (whole suite) | **PASS** — 73/73 (incl. new `test/harness_speech_test.dart`, 14 cases) |
| `flutter build apk --debug` — firebase (committed default) | **PASS** — built `app-debug.apk` |
| `flutter build apk --debug` — mock | **PASS** — built `app-debug.apk` (mode flipped, verified, reverted) |

**On-device dogfood is the product-facing proof per doctrine** (a green unit test is NOT sufficient
for a product-facing fix). What must be confirmed on the dev build:
- Report-capture note AND chat composer: tap mic, speak two sentences with a >2s pause → BOTH land,
  appended in order; the mic stays "listening" the whole time; tap Stop → the last in-flight words
  are retained.
- Deny mic permission → clean "Mic unavailable — check the microphone permission." snack, no crash.
- Sending/submitting while listening auto-stops the mic.
- No runaway repeated beeping across re-arms (the one item that may need the small native de-beep
  follow-up above).

The `HarnessSpeechTurn` unit tests prove the deterministic accumulator rules (base+append across
utterances, transient-partial replacement, seam-recovery/flush, case-insensitive dedup, turn-boundary
reset) — the parts most likely to carry a subtle bug — without a platform dependency.

## 5. Generic (reusable framework) vs Stock-Track-specific

- **Generic / app-agnostic (reusable harness framework):** the ENTIRE change. `HarnessSpeech`,
  `HarnessSpeechTurn`, and `HarnessSpeechOptions` name no project id, collection, owner, tool, or
  screen. Tuning flows from `HarnessSpeechOptions` (a value class with defaults), **not** from
  `HarnessConfig`/`project.config.json` — deliberately, because speech tuning is app-agnostic
  BEHAVIOUR, not per-project IDENTITY (that generated file holds names/ids only). The seam drops into
  any app the harness ports to unchanged.
- **Stock-Track-specific:** none in the seam. The only ST touch-points are the two existing UI callers
  (`chat_compose_controller.dart`, `report_capture_screen.dart`) wiring the seam into their own text
  fields — which is exactly the app-layer integration point, not seam identity.
