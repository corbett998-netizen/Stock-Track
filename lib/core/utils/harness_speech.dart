import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Config knobs for the dictation seam. App-agnostic BEHAVIOUR tuning (not project
/// identity, so it deliberately does NOT live in the generated `HarnessConfig` /
/// project.config.json — that file holds names/ids only). Mirrors the reference's
/// `kVoiceEngine`/`kVoicePreferOnDevice` const-config pattern: nothing here is a
/// magic literal buried in the seam.
@immutable
class HarnessSpeechOptions {
  const HarnessSpeechOptions({
    this.continuous = true,
    this.preferOnDevice = false,
    this.pauseFor = const Duration(seconds: 3),
    this.listenFor = const Duration(minutes: 10),
  });

  /// Re-arm across natural pauses so narration feels continuous until the user
  /// explicitly stops. `false` = legacy single-shot (session ends at first pause).
  final bool continuous;

  /// Prefer the on-device recognizer (`EXTRA_PREFER_OFFLINE`). Default `false` to
  /// match the reference's DEFAULT engine (the online OS recognizer) and to never go
  /// silently dead on a device without an offline language pack; a project can opt in.
  final bool preferOnDevice;

  /// Max trailing silence before the OS finalises an utterance. Kept generous so a
  /// natural mid-sentence pause doesn't cut the turn (reference tunes ~1.8s+).
  final Duration pauseFor;

  /// Max single-session duration. Kept long so one OS session runs as long as allowed
  /// before the re-arm takes over — fewer re-arms = fewer seams = fewer ready/end tones.
  final Duration listenFor;
}

/// Pure, platform-free accumulator for ONE dictation turn — the load-bearing part of
/// the continuous-dictation contract, extracted so it is unit-testable without the OS
/// engine. Owns base + finalised utterances + the in-flight partial, and the
/// dedup/append/recovery rules. The seam ([HarnessSpeech]) drives it from engine
/// callbacks and emits [text] after each mutation.
///
///  - [start] snapshots the caller's existing text so finals APPEND to it (mic +
///    keyboard mix freely).
///  - [partial]/[finalize] track the live partial vs the committed run.
///  - [flushPartial] commits the retained in-flight partial — used at a session seam
///    (a session that ended without finalising) and on stop, so nothing is lost.
///  - [reset] clears finals + partial at a turn boundary only.
class HarnessSpeechTurn {
  String _base = '';
  String _committed = '';
  String _livePartial = '';

  /// Begin a turn over the caller's existing [base] text.
  void start(String base) {
    _base = base.trimRight();
    _committed = '';
    _livePartial = '';
  }

  /// A live (transient) partial for the current utterance.
  void partial(String words) => _livePartial = words;

  /// A finalised utterance — append it (dedup-guarded) and clear the live partial.
  void finalize(String words) {
    _commit(words);
    _livePartial = '';
  }

  /// Commit the retained in-flight partial (seam recovery / flush-on-stop). Returns
  /// true if anything was committed (so the seam knows to re-emit).
  bool flushPartial() {
    if (_livePartial.trim().isEmpty) return false;
    _commit(_livePartial);
    _livePartial = '';
    return true;
  }

  /// Clear finals + partial at a turn boundary (start()/stop()) only.
  void reset() {
    _committed = '';
    _livePartial = '';
  }

  /// The full current transcript to render: base + finalised run + live partial.
  String get text => [
    _base,
    _committed,
    _livePartial,
  ].where((p) => p.trim().isNotEmpty).join(' ');

  void _commit(String words) {
    final w = words.trim();
    if (w.isEmpty) return;
    // Dedup: a re-arm/flush can re-present the same tail.
    if (_committed.toLowerCase().endsWith(w.toLowerCase())) return;
    _committed = _committed.isEmpty ? w : '$_committed $w';
  }
}

/// Generic, app-agnostic voice-dictation seam for the harness — a THIN wrapper over
/// the OS speech-recognition engine (`speech_to_text`). This is the ADAPT choice from
/// the parity map: the reference's bundled offline dual-engine + A/B toggle is
/// DON'T-PORT (a whole local package that adds no reusability signal); the OS seam
/// reaches parity with the reference's DEFAULT engine (which is itself the OS
/// recognizer). The custom native bridge existed only to dodge a Firebase-v2 `web`
/// dependency pincer this project does not have.
///
/// This seam implements the reference's load-bearing CONTINUOUS-DICTATION contract,
/// which is the real value (not the recognizer choice):
///  - CONTINUOUS CAPTURE: re-arms across natural pauses; only an explicit stop or a
///    permanent error (permission denied) ends the turn.
///  - PARTIAL vs FINAL: partials are transient/live; each final is APPENDED to the
///    accumulated turn — the seam owns base+append so the consumer just renders the
///    emitted transcript.
///  - TURN-BOUNDARY RESET: the accumulator resets ONLY at start()/stop(), never on an
///    internal re-arm, so the prior turn's tail can't prepend into the next recording.
///  - SEAM RECOVERY: a session that ends without finalising its last partial commits
///    those words on re-arm, so nothing is lost at a session seam.
///  - FLUSH ON STOP: the in-flight partial is flushed (dedup-guarded) on stop, so a
///    tap-off mid-sentence keeps its words.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — no project identity. Degrades gracefully:
/// [ensureAvailable] returns false (never throws) when the engine/permission is
/// unavailable, so a caller shows a clean "mic unavailable" state instead of crashing.
///
/// This ships FIELD-SCOPED continuous capture (report note + chat composer). The
/// reference's "dictate while navigating to reproduce" headline needs a model-sink
/// report draft + a global mic FAB + a live transcript chip — a scoped follow-up, not
/// a silent weaker substitute.
/// TODO(mic): owner decision — is field-scoped dictation enough for the harness's
/// report/chat screens, or is navigate-while-dictating a required capability? Do not
/// build the global-draft path blind. See docs/harness/validation/CORRECTION_mic.md §3.
///
/// KNOWN on-device follow-up (surfaced, not silently shipped): a naive re-arm loop can
/// re-trigger the OS recogniser's ready/end tone each cycle. Mitigated here by
/// minimising restarts (long [HarnessSpeechOptions.listenFor]/[pauseFor]); if audible
/// beeping still shows up on-device, the minimal port is the reference's session-scoped
/// stream-mute in a tiny native seam — verified by ear, not assumed. See
/// docs/harness/validation/CORRECTION_mic.md.
class HarnessSpeech {
  HarnessSpeech();

  final SpeechToText _stt = SpeechToText();
  final HarnessSpeechTurn _turn = HarnessSpeechTurn();
  bool _initialized = false;
  bool _available = false;

  // ----- listening intent (separate from the engine's momentary isListening) -----
  final ValueNotifier<bool> _listeningVN = ValueNotifier<bool>(false);
  bool _permanentError = false;

  // ----- callbacks + config for the active turn -----
  void Function(String transcript)? _transcriptCb;
  void Function(String finalUtterance)? _finalCb;
  void Function(bool listening)? _listeningCb;
  void Function(String message)? _errorCb;
  HarnessSpeechOptions _options = const HarnessSpeechOptions();

  // ----- re-arm bookkeeping -----
  bool _rearming = false;
  DateTime? _lastListenStart;
  int _consecutiveFastStops = 0;

  /// The listening INTENT — true from start() until an explicit stop or a permanent
  /// error, INCLUDING across internal re-arms (so the FAB stays "listening" during a
  /// natural pause). Drive the mic UI from this, not from a per-utterance final.
  bool get isListening => _listeningVN.value;

  /// Listening-state changes as a listenable, for callers that prefer it over the
  /// [start]-time `onListeningChanged` callback.
  ValueListenable<bool> get listening => _listeningVN;

  /// Initialise once + report whether dictation can run on this device/build. Never
  /// throws. Registers the status/error listeners that drive the re-arm loop.
  Future<bool> ensureAvailable() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _stt.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );
    } catch (e) {
      _available = false;
      debugPrint('[harness_speech] init failed: $e');
    }
    return _available;
  }

  /// Start a dictation turn. [base] is the caller's existing text (snapshotted so
  /// finals APPEND to it); [onTranscript] receives the full current transcript to
  /// render (base + finals + live partial); [onListeningChanged] reflects the
  /// listening intent for the UI; [onFinal] optionally observes each finalised
  /// utterance; [onError] surfaces a permanent mid-session failure. Returns false if
  /// dictation isn't available (caller shows the "mic unavailable" snack).
  Future<bool> start({
    required String base,
    required void Function(String transcript) onTranscript,
    void Function(bool listening)? onListeningChanged,
    void Function(String finalUtterance)? onFinal,
    void Function(String message)? onError,
    HarnessSpeechOptions? options,
  }) async {
    _permanentError = false;
    if (!await ensureAvailable()) return false;

    _turn.start(base);
    _transcriptCb = onTranscript;
    _finalCb = onFinal;
    _listeningCb = onListeningChanged;
    _errorCb = onError;
    _options = options ?? const HarnessSpeechOptions();
    _consecutiveFastStops = 0;

    _setListening(true);
    final ok = await _listen();
    if (!ok) {
      _setListening(false);
      return false;
    }
    return true;
  }

  /// Stop the turn. Flushes the in-flight partial (dedup-guarded) so a tap-off
  /// mid-sentence keeps its words, then resets the accumulator.
  Future<void> stop() async {
    _setListening(false); // intent off first so the re-arm guard blocks
    if (_turn.flushPartial()) _emit();
    _turn.reset();
    try {
      await _stt.stop();
    } catch (_) {}
  }

  void dispose() {
    _listeningVN.dispose();
    try {
      _stt.cancel();
    } catch (_) {}
  }

  // ----- internals -----

  Future<bool> _listen() async {
    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          onDevice: _options.preferOnDevice,
          cancelOnError: false,
          pauseFor: _options.pauseFor,
          listenFor: _options.listenFor,
        ),
      );
      _lastListenStart = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('[harness_speech] listen failed: $e');
      return false;
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    if (r.finalResult) {
      _turn.finalize(r.recognizedWords);
    } else {
      _turn.partial(r.recognizedWords);
    }
    _emit();
    if (r.finalResult) _finalCb?.call(r.recognizedWords);
  }

  void _onStatus(String status) {
    debugPrint('[harness_speech] status: $status');
    final ended =
        status == SpeechToText.notListeningStatus ||
        status == SpeechToText.doneStatus;
    if (!ended) return;
    if (!isListening || _permanentError) return;

    // Single-shot mode: the session ending IS the end of the turn.
    if (!_options.continuous) {
      if (_turn.flushPartial()) _emit();
      _setListening(false);
      return;
    }

    // Fast-fail guard: if sessions keep dying immediately the recogniser can't stay
    // up — stop cleanly rather than loop (and beep) forever.
    final now = DateTime.now();
    if (_lastListenStart != null &&
        now.difference(_lastListenStart!) < const Duration(milliseconds: 500)) {
      _consecutiveFastStops++;
    } else {
      _consecutiveFastStops = 0;
    }
    if (_consecutiveFastStops >= 6) {
      _permanentError = true;
      _setListening(false);
      _errorCb?.call('Mic stopped — the recognizer could not keep running.');
      return;
    }

    unawaited(_rearm());
  }

  void _onError(SpeechRecognitionError e) {
    debugPrint('[harness_speech] error: ${e.errorMsg} permanent=${e.permanent}');
    // Transient errors (no-match / speech-timeout) fire constantly in continuous
    // mode — ignore them; the status→re-arm loop keeps capture alive. Only a
    // permanent error (e.g. permission denied) ends the turn.
    if (!e.permanent) return;
    _permanentError = true;
    if (isListening) {
      _setListening(false);
      _errorCb?.call('Mic stopped — check the microphone permission.');
    }
  }

  Future<void> _rearm() async {
    if (_rearming) return;
    _rearming = true;
    // Brief release so the engine fully tears down before restarting.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (isListening && !_permanentError) {
      // Seam recovery: a session that ended without finalising its last partial —
      // commit those words before the fresh session so nothing is lost at the seam.
      if (_turn.flushPartial()) _emit();
      await _listen();
    }
    _rearming = false;
  }

  void _emit() => _transcriptCb?.call(_turn.text);

  void _setListening(bool v) {
    if (_listeningVN.value != v) _listeningVN.value = v;
    _listeningCb?.call(v);
  }
}
