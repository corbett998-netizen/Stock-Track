/// Events a [VoiceEngine] emits, and the listening states a consumer cares about.
///
/// Engine-agnostic: the phone's on-device recognizer and a bundled offline
/// engine (sherpa-onnx) both produce the SAME event shapes, so the controller +
/// UI never branch on which engine is underneath.
library;

/// High-level state of a dictation session, for driving UI (mic colour, pill).
enum VoiceState {
  /// Not listening.
  idle,

  /// Microphone is hot and capturing.
  listening,

  /// Audio captured, transcription in flight (brief).
  processing,

  /// A permanent error stopped the session (e.g. permission denied).
  error,
}

/// A single event from an engine. Sealed so consumers exhaustively handle each
/// kind (Dart 3 `switch`).
sealed class VoiceEvent {
  const VoiceEvent();
}

/// Live, not-yet-finalized words — drive the on-screen transcript only; do NOT
/// commit to a text sink (the matching [VoiceFinal] will carry the committed form).
final class VoicePartial extends VoiceEvent {
  const VoicePartial(this.text);
  final String text;
}

/// A finalized utterance — append this to the consumer's text sink.
final class VoiceFinal extends VoiceEvent {
  const VoiceFinal(this.text);
  final String text;
}

/// A state change. [onDevice] is the engine's recognition mode when known
/// (true = on-device/offline, false = online fallback, null = not reported).
final class VoiceStatus extends VoiceEvent {
  const VoiceStatus(this.state, {this.onDevice});
  final VoiceState state;
  final bool? onDevice;
}

/// An error. [permanent] true means the session stopped and won't auto-recover
/// (e.g. permission denied); false is a transient that the engine re-arms past.
final class VoiceError extends VoiceEvent {
  const VoiceError(this.message, {this.permanent = false});
  final String message;
  final bool permanent;
}
