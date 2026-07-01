/// Voice-dictation config for the harness — app-agnostic BEHAVIOUR knobs, not
/// project IDENTITY, so they live here as const config (NOT in the generated
/// `HarnessConfig` / project.config.json, which holds names/ids only). Mirrors
/// the reference pattern's `kVoiceEngine` / `kVoicePreferOnDevice` const-config.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — no project noun here.
library;

/// Which speech engine the harness mic uses:
///  - [androidSystem]: the phone's on-device recognizer over a native platform
///    channel (the PROVEN default — app-owned, runs while the owner navigates).
///  - [sherpaOnnx]: the bundled offline engine in `packages/harness_voice/` —
///    fully offline, device-independent, private (audio never leaves the phone).
///
/// Default is [androidSystem] so this flag IS the one-flip engine rollback: if
/// the bundled engine misbehaves, set it back and the app uses the proven path.
/// The engine can also be flipped at RUNTIME (long-press the mic) to A/B in-app
/// without a rebuild. First [sherpaOnnx] use downloads a small model once.
enum HarnessVoiceEngineKind { androidSystem, sherpaOnnx }

/// The compile-time default engine (see [HarnessVoiceEngineKind]).
const HarnessVoiceEngineKind kHarnessVoiceEngine =
    HarnessVoiceEngineKind.androidSystem;

/// Prefer the phone's ON-DEVICE recognizer (Android 12+ on-device recognizer /
/// `EXTRA_PREFER_OFFLINE`) over the cloud path. On-device is faster + works
/// offline; the native bridge auto-falls-back to online if the device has no
/// offline language pack. Flip to `false` to force the online path.
const bool kHarnessVoicePreferOnDevice = true;

/// Platform-channel names for the native voice bridges. Generic (no app noun) so
/// the same module drops into any harness-instrumented app; the native side
/// declares the identical strings ([HarnessVoiceBridge] / [MicPcmRecorder]).
class HarnessVoiceChannels {
  const HarnessVoiceChannels._();

  /// Native SpeechRecognizer bridge (the androidSystem engine).
  static const String sttMethod = 'harness/voice_stt';
  static const String sttEvents = 'harness/voice_stt/events';

  /// Native AudioRecord PCM source (feeds the bundled sherpa-onnx engine).
  static const String pcmMethod = 'harness/voice_pcm';
  static const String pcmEvents = 'harness/voice_pcm/events';
}
