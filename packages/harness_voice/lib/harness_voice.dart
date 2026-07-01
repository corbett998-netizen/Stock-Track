/// harness_voice — reusable on-device voice-dictation module for the harness.
///
/// A floating mic that transcribes speech into any text sink while the owner
/// keeps using the app. Engine-agnostic, offline-first, private.
///
/// Usage:
/// ```dart
/// final controller = VoiceDictationController(engine: SherpaOnnxEngine(...))
///   ..onFinal = (text) => myNote.append(text);
/// // drop a mic button that calls controller.toggle() and reads
/// // controller.isListening / controller.liveTranscript.
/// ```
library;

export 'src/voice_event.dart';
export 'src/voice_engine.dart';
export 'src/voice_dictation_controller.dart';
export 'src/pcm_audio_source.dart';
export 'src/sherpa_model_manager.dart';
export 'src/engines/sherpa_onnx_engine.dart';
