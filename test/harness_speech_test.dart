import 'package:flutter_test/flutter_test.dart';
import 'package:stock_track/core/utils/harness_speech.dart';

/// MIC-group correction coverage: the pure continuous-dictation accumulator
/// ([HarnessSpeechTurn]) extracted from the OS speech seam. The seam itself (re-arm
/// loop, permission degradation, beep behaviour) is product-facing and proven
/// on-device per doctrine; these guard the load-bearing base+append / dedup / seam-
/// recovery / flush rules that make continuous capture feel unbroken.
void main() {
  group('HarnessSpeechTurn — base + append', () {
    test('empty base: first final becomes the text', () {
      final t = HarnessSpeechTurn()..start('');
      t.finalize('hello world');
      expect(t.text, 'hello world');
    });

    test('keyboard base is preserved and dictation appends after it', () {
      final t = HarnessSpeechTurn()..start('typed note');
      t.partial('and then');
      expect(t.text, 'typed note and then');
      t.finalize('and then this happened');
      expect(t.text, 'typed note and then this happened');
    });

    test('base is trimRight-normalised so no double space at the seam', () {
      final t = HarnessSpeechTurn()..start('typed note   ');
      t.finalize('spoken');
      expect(t.text, 'typed note spoken');
    });

    test('multiple utterances append in order (continuous capture)', () {
      final t = HarnessSpeechTurn()..start('');
      // first sentence
      t.partial('first');
      t.finalize('first sentence');
      // >2s pause → the OS finalised; second sentence in the same turn
      t.partial('second');
      expect(t.text, 'first sentence second');
      t.finalize('second sentence');
      expect(t.text, 'first sentence second sentence');
    });
  });

  group('HarnessSpeechTurn — live partial vs final', () {
    test('partial is transient and is replaced, not accumulated', () {
      final t = HarnessSpeechTurn()..start('');
      t.partial('hel');
      t.partial('hello');
      t.partial('hello wor');
      expect(t.text, 'hello wor');
      t.finalize('hello world');
      expect(t.text, 'hello world');
    });
  });

  group('HarnessSpeechTurn — seam recovery + flush', () {
    test('flushPartial commits a retained partial (lost-at-seam recovery)', () {
      final t = HarnessSpeechTurn()..start('note');
      // a session ended WITHOUT delivering a final for its last partial
      t.partial('unfinished words');
      expect(t.flushPartial(), isTrue);
      expect(t.text, 'note unfinished words');
      // the NEXT session then delivers a fresh utterance
      t.partial('next');
      t.finalize('next sentence');
      expect(t.text, 'note unfinished words next sentence');
    });

    test('flushPartial is a no-op (returns false) when nothing is in flight', () {
      final t = HarnessSpeechTurn()..start('note');
      t.finalize('done');
      expect(t.flushPartial(), isFalse);
      expect(t.text, 'note done');
    });

    test('flush-on-stop keeps words when tapping off mid-sentence', () {
      final t = HarnessSpeechTurn()..start('');
      t.partial('half a sentence');
      // user taps Stop mid-sentence → seam flushes before reset
      expect(t.flushPartial(), isTrue);
      expect(t.text, 'half a sentence');
    });
  });

  group('HarnessSpeechTurn — dedup guard', () {
    test('committing the same tail twice does not duplicate it', () {
      final t = HarnessSpeechTurn()..start('');
      t.partial('hello world');
      // seam recovery commits the partial...
      expect(t.flushPartial(), isTrue);
      // ...then the same words arrive as a final (re-presented tail)
      t.finalize('hello world');
      expect(t.text, 'hello world');
    });

    test('dedup is case-insensitive on the trailing run', () {
      final t = HarnessSpeechTurn()..start('');
      t.finalize('Testing One Two');
      t.finalize('testing one two');
      expect(t.text, 'Testing One Two');
    });
  });

  group('HarnessSpeechTurn — turn-boundary reset', () {
    test('reset clears finals + partial (no bleed into the next turn)', () {
      final t = HarnessSpeechTurn()..start('base');
      t.finalize('first turn words');
      t.reset();
      // a new turn starts over the CURRENT sink text (the caller passes it as base)
      t.start('base first turn words');
      t.finalize('second turn');
      expect(t.text, 'base first turn words second turn');
    });

    test('start over new base drops the prior turn accumulation', () {
      final t = HarnessSpeechTurn()..start('');
      t.finalize('old');
      t.start('fresh');
      t.partial('spoken');
      expect(t.text, 'fresh spoken');
    });
  });

  group('HarnessSpeechOptions — config defaults (app-agnostic tuning)', () {
    test('defaults are continuous, online-first, generous silence window', () {
      const o = HarnessSpeechOptions();
      expect(o.continuous, isTrue);
      expect(o.preferOnDevice, isFalse);
      expect(o.pauseFor, const Duration(seconds: 3));
      expect(o.listenFor, const Duration(minutes: 10));
    });

    test('knobs are overridable without touching the seam', () {
      const o = HarnessSpeechOptions(
        continuous: false,
        preferOnDevice: true,
        pauseFor: Duration(milliseconds: 1800),
        listenFor: Duration(minutes: 2),
      );
      expect(o.continuous, isFalse);
      expect(o.preferOnDevice, isTrue);
      expect(o.pauseFor, const Duration(milliseconds: 1800));
    });
  });
}
