import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Generic, app-agnostic voice-dictation seam for the harness — a THIN wrapper over
/// the OS speech-recognition engine (`speech_to_text`). This is the ADAPT choice
/// from the parity map: the reference's bundled offline dual-engine + A/B toggle is
/// DON'T-PORT (a whole local package that adds no reusability signal); the OS seam
/// proves the "talk to your phone" capability.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — no project identity. Degrades
/// gracefully: [available] returns false (never throws) when the OS engine or the
/// mic permission is unavailable, so a caller can show a clean "mic unavailable"
/// state instead of crashing.
class HarnessSpeech {
  HarnessSpeech();

  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _available = false;

  bool get isListening => _stt.isListening;

  /// Initialise once + report whether dictation can run on this device/build.
  Future<bool> ensureAvailable() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _stt.initialize(
        onError: (e) => debugPrint('[harness_speech] error: ${e.errorMsg}'),
        onStatus: (s) => debugPrint('[harness_speech] status: $s'),
      );
    } catch (e) {
      _available = false;
      debugPrint('[harness_speech] init failed: $e');
    }
    return _available;
  }

  /// Start listening; [onResult] fires with the running transcript, [onFinal] once
  /// when recognition settles. Returns false if dictation isn't available.
  Future<bool> start({
    required void Function(String transcript) onResult,
    void Function(String transcript)? onFinal,
  }) async {
    if (!await ensureAvailable()) return false;
    try {
      await _stt.listen(
        onResult: (r) {
          onResult(r.recognizedWords);
          if (r.finalResult) onFinal?.call(r.recognizedWords);
        },
        listenOptions: SpeechListenOptions(partialResults: true),
      );
      return true;
    } catch (e) {
      debugPrint('[harness_speech] listen failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  void dispose() {
    try {
      _stt.cancel();
    } catch (_) {}
  }
}
