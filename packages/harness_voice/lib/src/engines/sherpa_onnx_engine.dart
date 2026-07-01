import 'dart:async';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../pcm_audio_source.dart';
import '../sherpa_model_manager.dart';
import '../voice_engine.dart';
import '../voice_event.dart';

/// A bundled, fully-offline streaming speech engine backed by sherpa-onnx
/// (streaming Zipformer transducer + built-in endpointing).
///
/// Recognition runs entirely on-device via FFI — audio never leaves the phone.
/// It consumes raw mic PCM from an injected [PcmAudioSource] (the app supplies
/// a native `AudioRecord`-backed source, so no `web`-pulling audio package is
/// needed — keeps the app Firebase-safe). The model files come from
/// [SherpaModelManager] (downloaded + cached on first launch).
///
/// `sherpa_onnx` pulls only `ffi` — NO `web` package, so it does not clash with
/// a host app's Firebase v2 stack.
///
/// Note: the decode loop runs synchronously on the platform thread in the PCM
/// callback. The small int8 model is fast enough for dictation; if UI jank ever
/// shows up under load, move the recognizer onto an isolate (the public surface
/// here doesn't change).
class SherpaOnnxEngine implements VoiceEngine {
  SherpaOnnxEngine({
    required PcmAudioSource audioSource,
    required SherpaModelPaths model,
    this.numThreads = 1,
  })  : _audio = audioSource,
        _model = model;

  /// sherpa native bindings are process-global; init exactly once.
  static bool _bindingsReady = false;

  final PcmAudioSource _audio;
  final SherpaModelPaths _model;
  final int numThreads;

  final StreamController<VoiceEvent> _controller =
      StreamController<VoiceEvent>.broadcast();

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Float32List>? _audioSub;
  bool _started = false;
  String _lastPartial = '';

  @override
  Stream<VoiceEvent> get events => _controller.stream;

  @override
  Future<void> start({bool preferOnDevice = true}) async {
    if (_started) return;
    if (!_bindingsReady) {
      sherpa.initBindings();
      _bindingsReady = true;
    }
    _recognizer ??= _buildRecognizer();
    _stream = _recognizer!.createStream();
    _lastPartial = '';
    _started = true;
    // sherpa is always on-device/offline.
    _emit(const VoiceStatus(VoiceState.listening, onDevice: true));
    _audioSub = _audio.pcm.listen(
      _onPcm,
      onError: (Object e) {
        _emit(VoiceError('Audio error: $e'));
      },
    );
    try {
      await _audio.start();
    } catch (e) {
      _emit(VoiceError('Mic start failed: $e', permanent: true));
      await stop();
    }
  }

  void _onPcm(Float32List chunk) {
    final sherpa.OnlineStream? stream = _stream;
    final sherpa.OnlineRecognizer? rec = _recognizer;
    if (stream == null || rec == null) return;

    stream.acceptWaveform(samples: chunk, sampleRate: _audio.sampleRate);
    while (rec.isReady(stream)) {
      rec.decode(stream);
    }

    final String text = rec.getResult(stream).text.trim();
    if (text.isNotEmpty && text != _lastPartial) {
      _lastPartial = text;
      _emit(VoicePartial(text));
    }

    // Endpoint = the recognizer's silence/length rules say the utterance ended.
    if (rec.isEndpoint(stream)) {
      if (text.isNotEmpty) _emit(VoiceFinal(text));
      rec.reset(stream);
      _lastPartial = '';
    }
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _audioSub?.cancel();
    _audioSub = null;
    await _audio.stop();
    _stream?.free();
    _stream = null;
    _lastPartial = '';
    _emit(const VoiceStatus(VoiceState.idle));
  }

  @override
  Future<void> dispose() async {
    await stop();
    _recognizer?.free();
    _recognizer = null;
    if (!_controller.isClosed) await _controller.close();
  }

  sherpa.OnlineRecognizer _buildRecognizer() {
    final sherpa.OnlineModelConfig modelConfig = sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: _model.encoder,
        decoder: _model.decoder,
        joiner: _model.joiner,
      ),
      tokens: _model.tokens,
      numThreads: numThreads,
      modelType: _model.modelType,
      debug: false,
    );
    final sherpa.OnlineRecognizerConfig config = sherpa.OnlineRecognizerConfig(
      model: modelConfig,
      enableEndpoint: true,
      // Finalize after a SHORT pause so transcribed text lands in the note field
      // as you speak (not only on stop) — matches the phone engine's feel. The
      // consumer's appendNote spaces successive utterances, so splitting on a
      // natural pause is harmless. rule2 (~0.8s after speech) is the common
      // trigger; rule1 (~1.4s of leading/!speech silence) is the fallback.
      rule1MinTrailingSilence: 1.4,
      rule2MinTrailingSilence: 0.8,
      rule3MinUtteranceLength: 20,
    );
    return sherpa.OnlineRecognizer(config);
  }

  void _emit(VoiceEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }
}
