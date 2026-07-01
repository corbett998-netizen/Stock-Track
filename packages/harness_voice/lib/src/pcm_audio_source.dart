import 'dart:typed_data';

/// A source of raw microphone PCM for an engine that does its own recognition
/// (e.g. [SherpaOnnxEngine]).
///
/// **Why this is an injected abstraction, not a bundled package:** the obvious
/// Flutter mic packages (`record`, `flutter_sound`) transitively pull
/// `package:web ^1.x`, which can CONFLICT with a host app's Firebase v2
/// (`web ^0.5.1`) — the dependency pincer the reference pattern avoids. So the
/// app supplies a concrete source backed by a native `AudioRecord` platform
/// channel (zero web-pulling Dart deps). Keeping it an interface also makes the
/// engine unit-testable with a fake source.
///
/// Contract: emit **mono float32 PCM normalized to [-1, 1]** at [sampleRate]
/// (16 kHz for the streaming models), in small chunks, only while started.
abstract interface class PcmAudioSource {
  /// The sample rate of [pcm] (Hz). Must match the model's expected rate.
  int get sampleRate;

  /// Mono float32 PCM chunks in [-1, 1], emitted while listening.
  Stream<Float32List> get pcm;

  /// Begin capturing (requests mic permission if needed).
  Future<void> start();

  /// Stop capturing (mic released).
  Future<void> stop();

  /// Release any native resources.
  Future<void> dispose();
}
