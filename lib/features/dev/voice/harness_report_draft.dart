import 'package:flutter/foundation.dart';

/// In-memory, session-scoped draft for the harness report reporter — the model
/// SINK the floating mic dictates into while the owner keeps using the app.
/// Ported from the reference mic pattern's report draft.
///
/// The draft lives ONLY while the app process is alive — intentionally NO disk
/// persistence (force-quitting loses it). One draft at a time (singleton). Three
/// surfaces touch it:
///  - the floating mic appends dictated finals ([appendNote]);
///  - the report capture screen hydrates from / writes through to it;
///  - Submit-success AND explicit clear both call [clear].
///
/// The screen context ([screen]) is FROZEN once at [start] so a voice-only report
/// attributes to the screen where the owner STARTED talking — not wherever they
/// are when they open the report screen to submit.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — no project noun here.
class HarnessReportDraft extends ChangeNotifier {
  HarnessReportDraft._();

  /// The single live draft.
  static final HarnessReportDraft instance = HarnessReportDraft._();

  String _note = '';
  String? _screen; // frozen at start
  bool _started = false;

  String get note => _note;

  /// The screen the owner was on when the draft was opened (frozen). Null until
  /// [start] with a non-null screen.
  String? get screen => _screen;

  /// Whether a draft has been opened (context frozen). Used by the report screen
  /// to decide hydrate-from-draft vs start-fresh.
  bool get started => _started;

  /// Whether there is resumable content (drives a "resume" affordance/badge).
  bool get hasContent => _note.trim().isNotEmpty;

  /// A started draft that actually has something to resume.
  bool get isActive => _started && hasContent;

  /// Open a draft, freezing the screen context ONCE. Idempotent while a draft is
  /// already started (re-opening keeps the original frozen screen).
  void start({String? screen}) {
    if (_started) return;
    _started = true;
    _screen = screen;
    notifyListeners();
  }

  /// Write-through from the note field (keyboard edits).
  void setNote(String value) {
    if (_note == value) return;
    _note = value;
    notifyListeners();
  }

  /// Append voice-transcribed text to the end of the note. Inserts a single
  /// separating space when the existing note doesn't already end in whitespace,
  /// so dictated phrases don't run together. Used by [HarnessVoiceService];
  /// keyboard edits go through [setNote].
  void appendNote(String text) {
    final String addition = text.trim();
    if (addition.isEmpty) return;
    final bool needsSpace = _note.isNotEmpty && !RegExp(r'\s$').hasMatch(_note);
    _note = needsSpace ? '$_note $addition' : '$_note$addition';
    notifyListeners();
  }

  /// Capture the full draft state so a transient borrower (e.g. the dev
  /// orchestrator chat reusing the shared voice recognizer) can FULLY restore it
  /// afterwards — guaranteeing dictation outside the reporter never mutates a
  /// real report draft.
  HarnessReportDraftSnapshot snapshot() => HarnessReportDraftSnapshot._(
        note: _note,
        screen: _screen,
        started: _started,
      );

  /// Restore a previously [snapshot]-ed state verbatim, discarding anything the
  /// borrower appended in between. One notify so listeners refresh once.
  void restore(HarnessReportDraftSnapshot snap) {
    _note = snap.note;
    _screen = snap.screen;
    _started = snap.started;
    notifyListeners();
  }

  /// Discard the whole draft. Called by Submit-success and by explicit clear.
  void clear() {
    _note = '';
    _screen = null;
    _started = false;
    notifyListeners();
  }
}

/// An immutable capture of [HarnessReportDraft]'s state, used to snapshot + fully
/// restore the shared draft around a transient borrower of the voice recognizer
/// (so dictation in the dev chat can't leak into a real report).
class HarnessReportDraftSnapshot {
  const HarnessReportDraftSnapshot._({
    required this.note,
    required this.screen,
    required this.started,
  });

  final String note;
  final String? screen;
  final bool started;
}
