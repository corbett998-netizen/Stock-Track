import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_engine.dart';
import 'voice_event.dart';

/// The single public entry point a consuming app uses for voice dictation.
///
/// Wraps a swappable [VoiceEngine] and exposes a tiny, UI-friendly surface:
///  - [isListening] / [state] / [onDevice] for the mic button + diagnostics,
///  - [liveTranscript] for an on-screen "words landing as you speak" chip
///    (transient — cleared once finalized; NEVER the source of truth for text),
///  - [onFinal] callback: each finalized utterance, for the app to append to
///    wherever it keeps text (a report note, a chat composer, a search box).
///
/// A [ChangeNotifier] so a `ListenableBuilder` mic widget repaints on change.
/// This is the engine-agnostic core; the harness report reporter is consumer #1.
class VoiceDictationController extends ChangeNotifier {
  VoiceDictationController({
    required VoiceEngine engine,
    this.preferOnDevice = true,
  }) : _engine = engine;

  final VoiceEngine _engine;

  /// Ask the engine to prefer on-device recognition (faster, offline, private).
  final bool preferOnDevice;

  /// Called once per finalized utterance. The app appends [text] to its sink.
  /// (Kept a callback, not a stream, so the controller doesn't dictate sink
  /// semantics — the consumer owns spacing/formatting.)
  void Function(String text)? onFinal;

  StreamSubscription<VoiceEvent>? _sub;

  bool _wantListening = false;
  String _liveTranscript = '';
  VoiceState _state = VoiceState.idle;
  bool? _onDevice;
  String? _error;

  bool get isListening => _wantListening;
  String get liveTranscript => _liveTranscript;
  VoiceState get state => _state;

  /// Engine recognition mode once known (true on-device, false online, null TBD).
  bool? get onDevice => _onDevice;
  String? get error => _error;

  Future<void> toggle() => _wantListening ? stop() : start();

  Future<void> start() async {
    if (_wantListening) return;
    _error = null;
    _wantListening = true;
    notifyListeners();
    _sub ??= _engine.events.listen(_onEvent, onError: _onStreamError);
    await _engine.start(preferOnDevice: preferOnDevice);
  }

  Future<void> stop() async {
    if (!_wantListening) return;
    _wantListening = false;
    _liveTranscript = '';
    _state = VoiceState.idle;
    notifyListeners();
    await _engine.stop();
  }

  void _onEvent(VoiceEvent event) {
    switch (event) {
      case VoicePartial(:final text):
        if (text != _liveTranscript) {
          _liveTranscript = text;
          notifyListeners();
        }
      case VoiceFinal(:final text):
        if (text.isNotEmpty) onFinal?.call(text);
        _liveTranscript = '';
        notifyListeners();
      case VoiceStatus(:final state, :final onDevice):
        _state = state;
        if (onDevice != null) _onDevice = onDevice;
        if (state == VoiceState.listening && !_wantListening) {
          _wantListening = true;
        } else if (state == VoiceState.idle && _wantListening) {
          _wantListening = false;
          _liveTranscript = '';
        }
        notifyListeners();
      case VoiceError(:final message, :final permanent):
        if (permanent) {
          _error = message;
          _wantListening = false;
          _state = VoiceState.error;
          _liveTranscript = '';
          notifyListeners();
        }
    }
  }

  void _onStreamError(Object error) {
    _error = 'Voice error: $error';
    _wantListening = false;
    _state = VoiceState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _engine.dispose();
    super.dispose();
  }
}
