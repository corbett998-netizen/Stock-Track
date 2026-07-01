import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:harness_voice/harness_voice.dart';

import 'harness_voice_config.dart';

/// App-side [PcmAudioSource] backed by the native `MicPcmRecorder` platform
/// channel. Feeds the bundled sherpa-onnx engine raw mic audio WITHOUT a Flutter
/// audio package (`record`/`flutter_sound` pull `package:web`, which can clash
/// with a Firebase-v2 host app). Ported verbatim from the reference mic pattern.
///
/// Native streams 16 kHz mono PCM16 (little-endian) byte chunks; we convert to
/// float32 [-1, 1] for the recognizer.
class ChannelPcmAudioSource implements PcmAudioSource {
  static const MethodChannel _method =
      MethodChannel(HarnessVoiceChannels.pcmMethod);
  static const EventChannel _events =
      EventChannel(HarnessVoiceChannels.pcmEvents);

  final StreamController<Float32List> _controller =
      StreamController<Float32List>.broadcast();
  StreamSubscription<dynamic>? _sub;

  @override
  int get sampleRate => 16000;

  @override
  Stream<Float32List> get pcm => _controller.stream;

  @override
  Future<void> start() async {
    _sub ??= _events.receiveBroadcastStream().listen(
      _onData,
      onError: (Object e) => _controller.addError(e),
    );
    final bool? ok = await _method.invokeMethod<bool>('start');
    if (ok != true) {
      throw StateError(
        'Mic PCM capture did not start (microphone permission or device issue).',
      );
    }
  }

  void _onData(dynamic data) {
    if (data is Uint8List) {
      _controller.add(_pcm16ToFloat32(data));
    } else if (data is Map && data['type'] == 'error') {
      _controller.addError(
        StateError((data['message'] ?? 'mic error').toString()),
      );
    }
  }

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final int n = bytes.length ~/ 2;
    final Float32List out = Float32List(n);
    final ByteData bd = ByteData.sublistView(bytes);
    for (int i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  @override
  Future<void> stop() async {
    await _method.invokeMethod<bool>('stop');
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _method.invokeMethod<bool>('stop');
    } catch (_) {
      // best-effort
    }
    if (!_controller.isClosed) await _controller.close();
  }
}
