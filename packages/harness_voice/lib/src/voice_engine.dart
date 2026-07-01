import 'voice_event.dart';

/// A swappable speech-recognition backend.
///
/// The reference pattern ships two implementations behind this one interface:
///  - a native on-device recognizer over a platform channel (the proven default
///    path), and
///  - `SherpaOnnxEngine` — a bundled offline engine for device-independent,
///    fully-offline, private recognition.
///
/// A consuming app never talks to an engine directly — it uses
/// [VoiceDictationController], which selects + drives one of these. Keeping the
/// surface this small is what makes the model reusable across apps and lets us
/// upgrade/replace the engine without touching app code.
abstract interface class VoiceEngine {
  /// Stream of recognition events (partial / final / status / error).
  /// Continuous: the engine re-arms across natural pauses while listening.
  Stream<VoiceEvent> get events;

  /// Start (or resume) continuous dictation.
  ///
  /// [preferOnDevice] asks the engine to use on-device recognition where it can
  /// (engines that are inherently offline ignore it). An engine that can't honor
  /// it MUST fall back rather than go silent.
  Future<void> start({bool preferOnDevice = true});

  /// Stop dictation (user toggled off, or the field took keyboard focus).
  Future<void> stop();

  /// Release native resources. The engine is unusable afterwards.
  Future<void> dispose();
}
