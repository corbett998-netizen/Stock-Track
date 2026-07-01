import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_voice/harness_voice.dart';
import 'package:stock_track/features/dev/voice/harness_report_draft.dart';

/// MIC-parity coverage for the ported app-owned voice stack (the reference mic
/// pattern). The native recognizer + platform bridges are product-facing and
/// proven on-device per doctrine; these guard the pure, load-bearing rules that
/// make dictation feel unbroken:
///  - the report DRAFT accumulator (base + append spacing / freeze-screen / snapshot
///    + restore for the chat borrow), and
///  - the engine-agnostic [VoiceDictationController] (partial→live, final→append,
///    status transitions) driven by a fake engine with zero platform dependency.
void main() {
  group('HarnessReportDraft — the model sink the mic writes into', () {
    setUp(() => HarnessReportDraft.instance.clear());
    tearDown(() => HarnessReportDraft.instance.clear());

    test('appendNote spaces successive utterances (no run-together)', () {
      final d = HarnessReportDraft.instance;
      d.appendNote('the badge overlaps');
      d.appendNote('on narrow phones');
      expect(d.note, 'the badge overlaps on narrow phones');
    });

    test('appendNote does not double-space when the note already ends in space', () {
      final d = HarnessReportDraft.instance..setNote('typed note ');
      d.appendNote('spoken');
      expect(d.note, 'typed note spoken');
    });

    test('start() freezes the screen ONCE (idempotent while started)', () {
      final d = HarnessReportDraft.instance;
      d.start(screen: 'Inventory');
      d.start(screen: 'Dashboard'); // ignored — already started
      expect(d.screen, 'Inventory');
      expect(d.started, isTrue);
    });

    test('isActive = started AND has content; clear resets everything', () {
      final d = HarnessReportDraft.instance;
      expect(d.isActive, isFalse);
      d.start(screen: 'Inventory');
      expect(d.isActive, isFalse); // started but empty
      d.appendNote('a bug');
      expect(d.isActive, isTrue);
      d.clear();
      expect(d.started, isFalse);
      expect(d.note, isEmpty);
      expect(d.screen, isNull);
    });

    test('snapshot + restore returns the draft verbatim (chat-borrow isolation)', () {
      final d = HarnessReportDraft.instance
        ..start(screen: 'Inventory')
        ..appendNote('real report words');
      final snap = d.snapshot();
      // Borrower mutates the shared draft…
      d.appendNote('chat dictation that must NOT leak');
      expect(d.note, contains('chat dictation'));
      // …then restores it: the borrowed words are gone, the real draft is intact.
      d.restore(snap);
      expect(d.note, 'real report words');
      expect(d.screen, 'Inventory');
    });
  });

  group('VoiceDictationController — engine-agnostic core (fake engine)', () {
    late _FakeEngine engine;
    late VoiceDictationController controller;
    late List<String> finals;

    setUp(() {
      engine = _FakeEngine();
      finals = <String>[];
      controller = VoiceDictationController(engine: engine)
        ..onFinal = finals.add;
    });

    tearDown(() => controller.dispose());

    test('start toggles listening intent + starts the engine', () async {
      expect(controller.isListening, isFalse);
      await controller.start();
      expect(controller.isListening, isTrue);
      expect(engine.started, isTrue);
    });

    test('partials drive liveTranscript; a final APPENDS + clears the live chip',
        () async {
      await controller.start();
      engine.emit(const VoicePartial('low stock badge'));
      await _tick();
      expect(controller.liveTranscript, 'low stock badge');
      engine.emit(const VoiceFinal('low stock badge overlaps'));
      await _tick();
      expect(finals, <String>['low stock badge overlaps']);
      expect(controller.liveTranscript, isEmpty); // cleared after final
    });

    test('a permanent error stops listening + surfaces the message', () async {
      await controller.start();
      engine.emit(const VoiceError('permission denied', permanent: true));
      await _tick();
      expect(controller.isListening, isFalse);
      expect(controller.error, 'permission denied');
    });

    test('an idle status event flips listening intent off', () async {
      await controller.start();
      engine.emit(const VoiceStatus(VoiceState.idle));
      await _tick();
      expect(controller.isListening, isFalse);
    });
  });
}

/// Let the broadcast-stream listener process a queued event before asserting.
Future<void> _tick() => Future<void>.delayed(Duration.zero);

/// A platform-free [VoiceEngine] for driving the controller in unit tests.
class _FakeEngine implements VoiceEngine {
  final StreamController<VoiceEvent> _c = StreamController<VoiceEvent>.broadcast();
  bool started = false;

  void emit(VoiceEvent e) => _c.add(e);

  @override
  Stream<VoiceEvent> get events => _c.stream;

  @override
  Future<void> start({bool preferOnDevice = true}) async => started = true;

  @override
  Future<void> stop() async => started = false;

  @override
  Future<void> dispose() async {
    if (!_c.isClosed) await _c.close();
  }
}
