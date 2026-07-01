import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:harness_voice/harness_voice.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/current_screen_tracker.dart';
import 'channel_pcm_audio_source.dart';
import 'harness_report_draft.dart';
import 'harness_voice_config.dart';

/// App-owned voice-to-text for the harness report reporter — ported verbatim from
/// the reference mic pattern (the reusable-harness standard).
///
/// Why an app-owned recognizer (not the keyboard mic): the keyboard's voice
/// typing only feeds a focused text field with the keyboard up, so it can't run
/// while you navigate the app. This service drives a NATIVE Android
/// `SpeechRecognizer` over a platform channel and writes transcribed text
/// straight into [HarnessReportDraft] — no field focus or keyboard required — so
/// dictation keeps running while the owner reproduces a bug. Keyboard typing and
/// the mic both feed the SAME draft (mic appends to the end), so the two methods
/// mix freely.
///
/// Why a custom platform channel (not a Flutter speech plugin): a plain platform
/// channel touches zero shared Dart deps, so a Firebase-v2 host app never picks
/// up a conflicting `web` dependency — and an app-owned recognizer runs while
/// navigating (the keyboard mic cannot).
///
/// Continuous capture + auto-restart live on the NATIVE side (the recognizer
/// finalizes after a short silence and re-arms while listening). This service
/// just toggles start/stop and appends each FINAL transcript event to the draft.
/// Singleton + [ChangeNotifier] so the mic FAB reflects listening state.
/// Android-first (iOS no-ops gracefully — the channel simply has no handler).
class HarnessVoiceService extends ChangeNotifier {
  HarnessVoiceService._();

  static final HarnessVoiceService instance = HarnessVoiceService._();

  static const MethodChannel _method =
      MethodChannel(HarnessVoiceChannels.sttMethod);
  static const EventChannel _events =
      EventChannel(HarnessVoiceChannels.sttEvents);

  /// Transient chip text shown while the offline model downloads — never a real
  /// transcript, so it must not be flushed into the draft on stop, nor composed
  /// into the report field. Public so the report screen can exclude it too.
  static const String preparingHint = 'Preparing offline voice…';

  /// User intent: the mic toggle is ON. Drives the FAB state. Reconciled with the
  /// native side's `status` events (listening / stopped).
  bool _wantListening = false;

  /// Last error surfaced to the UI (e.g. permission denied / no recognizer).
  String? _error;

  /// Live (not-yet-finalized) words from the recognizer, for the on-screen
  /// transcript chip. Replaced on each `partial`, cleared when committed as a
  /// `final` to the draft or when listening stops. NOT part of the draft until
  /// finalized, so the chip shows progress without polluting the note.
  String _liveTranscript = '';

  /// Whether the native side is using the on-device engine. Surfaced for
  /// diagnostics; null until first status.
  bool? _onDevice;

  /// Bundled-engine controller (sherpa-onnx), built lazily the first time the
  /// sherpaOnnx engine is used. Null on the default path.
  VoiceDictationController? _sherpa;

  /// Active engine — starts from the compile-time default [kHarnessVoiceEngine]
  /// (the proven `androidSystem` path = zero-regression + instant rollback) and
  /// can be flipped at RUNTIME (long-press the mic) to A/B the bundled offline
  /// engine in-app without a rebuild.
  HarnessVoiceEngineKind _engine = kHarnessVoiceEngine;

  HarnessVoiceEngineKind get engine => _engine;

  /// Switch engines while idle (no-op mid-session). Long-pressed from the FAB.
  void cycleEngine() {
    if (_wantListening) return;
    _engine = _engine == HarnessVoiceEngineKind.androidSystem
        ? HarnessVoiceEngineKind.sherpaOnnx
        : HarnessVoiceEngineKind.androidSystem;
    _error = null;
    _onDevice = null;
    notifyListeners();
  }

  bool get isListening => _wantListening;
  String? get error => _error;

  /// Current live partial transcript (empty when nothing in-flight).
  String get liveTranscript => _liveTranscript;

  /// True/false once the engine reports its mode; null before then.
  bool? get onDevice => _onDevice;

  /// Toggle convenience for the mic button.
  Future<void> toggle() => _wantListening ? stop() : start();

  /// Start (or resume) continuous dictation into the report draft.
  Future<void> start() async {
    if (_wantListening) return;
    _error = null;

    // Make sure a draft exists + its screen context is frozen — so a voice-only
    // report still attributes to the screen the owner was on when they started
    // talking (not the report screen they open later to submit).
    if (!HarnessReportDraft.instance.started) {
      HarnessReportDraft.instance.start(
        screen: CurrentScreenTracker.currentScreen,
      );
    }

    // Bundled offline engine path (selected at runtime). The default
    // (androidSystem) path below is unchanged = instant rollback.
    if (_engine == HarnessVoiceEngineKind.sherpaOnnx) {
      await _startSherpa();
      return;
    }

    _eventSub ??= _events
        .receiveBroadcastStream()
        .listen(_onEvent, onError: _onStreamError);

    // Optimistically reflect intent so the FAB responds to the tap; native
    // `status` events (listening/stopped) and a permission denial correct it.
    _wantListening = true;
    notifyListeners();

    try {
      // Prefer the on-device engine; native falls back to online if the device
      // has no offline language pack.
      await _method.invokeMethod<bool>('start', <String, dynamic>{
        'preferOnDevice': kHarnessVoicePreferOnDevice,
      });
    } on PlatformException catch (e) {
      _error = 'Voice capture error: ${e.message}';
      _wantListening = false;
      notifyListeners();
    } on MissingPluginException {
      // No native handler (e.g. iOS / unsupported) — fail soft, not a crash.
      _error = 'Voice capture isn’t available on this platform yet.';
      _wantListening = false;
      notifyListeners();
    }
  }

  StreamSubscription<dynamic>? _eventSub;

  /// Stop dictation (user toggled off, or the note field took keyboard focus so
  /// the app-mic yields the microphone to keyboard voice typing).
  Future<void> stop() async {
    if (!_wantListening) return;
    _wantListening = false;
    // Flush any in-flight (not-yet-finalized) words into the report draft so a
    // tap-off mid-sentence — or tapping into the note field, which stops the mic
    // — never loses dictation. An utterance only finalizes after an endpoint
    // (short trailing silence), so the latest words often live only in the live
    // transcript at stop time. A committed final already cleared _liveTranscript,
    // so this fires only on a genuine pending tail (no dupes).
    final String pending = _liveTranscript.trim();
    if (pending.isNotEmpty && pending != preparingHint) {
      HarnessReportDraft.instance.appendNote(pending);
    }
    _liveTranscript = '';
    notifyListeners();
    if (_engine == HarnessVoiceEngineKind.sherpaOnnx) {
      try {
        await _sherpa?.stop();
      } catch (_) {
        // best-effort; intent already flipped off
      }
      return;
    }
    try {
      await _method.invokeMethod<bool>('stop');
    } catch (_) {
      // best-effort; we've already flipped intent off
    }
  }

  // ---- Bundled sherpa-onnx engine path (opt-in via kHarnessVoiceEngine) ------

  /// Build (once) + start the bundled offline engine. Mirrors the controller's
  /// state into this service's fields so the existing FAB works unchanged.
  Future<void> _startSherpa() async {
    // Optimistic FAB-on; first run downloads the model (a few seconds) — show a
    // hint in the transcript chip so the tap clearly registered.
    _wantListening = true;
    notifyListeners();
    try {
      if (_sherpa == null) {
        final Directory base = await getApplicationSupportDirectory();
        final Directory modelDir = Directory('${base.path}/voice_model');
        final SherpaModelManager manager = SherpaModelManager(modelDir);
        if (!await manager.isReady()) {
          _liveTranscript = preparingHint;
          notifyListeners();
        }
        final SherpaModelPaths model = await manager.ensureModel();
        final VoiceDictationController c = VoiceDictationController(
          engine: SherpaOnnxEngine(
            audioSource: ChannelPcmAudioSource(),
            model: model,
          ),
        )..onFinal = HarnessReportDraft.instance.appendNote;
        c.addListener(_syncFromSherpa);
        _sherpa = c;
      }
      await _sherpa!.start();
    } catch (e) {
      _error = 'Offline voice engine failed: $e';
      _wantListening = false;
      notifyListeners();
    }
  }

  /// Copy the bundled controller's state into this service so the FAB (which
  /// listens to this singleton) reflects listening / live words / errors.
  void _syncFromSherpa() {
    final VoiceDictationController? c = _sherpa;
    if (c == null) return;
    _wantListening = c.isListening;
    _liveTranscript = c.liveTranscript;
    _onDevice = c.onDevice;
    if (c.error != null) _error = c.error;
    notifyListeners();
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final String type = (event['type'] ?? '').toString();
    switch (type) {
      case 'partial':
        // Live, not-yet-final words — drive the transcript chip only.
        final String text = (event['text'] ?? '').toString();
        if (text != _liveTranscript) {
          _liveTranscript = text;
          notifyListeners();
        }
        break;
      case 'final':
        final String text = (event['text'] ?? '').toString();
        if (text.isNotEmpty) HarnessReportDraft.instance.appendNote(text);
        // The final has landed in the draft — clear the in-flight chip text.
        if (_liveTranscript.isNotEmpty) {
          _liveTranscript = '';
        }
        notifyListeners();
        break;
      case 'status':
        final String value = (event['value'] ?? '').toString();
        if (event['onDevice'] is bool) _onDevice = event['onDevice'] as bool;
        if (value == 'listening' && !_wantListening) {
          // Native began (e.g. after a permission grant) — sync the FAB on.
          _wantListening = true;
          notifyListeners();
        } else if (value == 'stopped' && _wantListening) {
          _wantListening = false;
          _liveTranscript = '';
          notifyListeners();
        } else {
          // 'fallback_online' / mode update — refresh listeners for diagnostics.
          notifyListeners();
        }
        // 'needs_permission' — OS dialog is up; leave intent as-is.
        break;
      case 'error':
        // Native re-arms transient errors itself; only `permanent` reaches here.
        if (event['permanent'] == true) {
          _error = (event['message'] ?? 'Voice capture stopped').toString();
          _wantListening = false;
          notifyListeners();
        }
        break;
    }
  }

  void _onStreamError(Object error) {
    _error = 'Voice capture error: $error';
    _wantListening = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _sherpa?.removeListener(_syncFromSherpa);
    _sherpa?.dispose();
    super.dispose();
  }
}
