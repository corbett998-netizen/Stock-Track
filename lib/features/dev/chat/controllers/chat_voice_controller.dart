import 'package:flutter/material.dart';

import '../../voice/harness_report_draft.dart';
import '../../voice/harness_voice_service.dart';

/// Voice dictation for the orchestrator chat composer, isolated so it can NEVER
/// leak into a real report. Ported from the reference mic pattern's chat voice
/// controller.
///
/// Voice REUSES the single app-owned recognizer ([HarnessVoiceService]) — no new
/// recognizer. CRITICAL ISOLATION: that service writes finals into the SHARED
/// [HarnessReportDraft] singleton. To guarantee chat dictation never leaks into a
/// real report, we SNAPSHOT the whole draft the instant the chat mic starts and
/// FULLY RESTORE it the instant the chat mic stops (toggle-off, send, leave).
/// While the mic is live we read the dictated delta off the (temporarily-borrowed)
/// draft into the chat input; on stop we discard the borrowed draft and put the
/// real report draft back exactly as it was. So the chat input is the ONLY place
/// chat speech ever lands.
class ChatVoiceController {
  ChatVoiceController({
    required this.controller,
    required this.notify,
    this.autoScroll,
  });

  /// The shared chat input text controller (owned by the screen).
  final TextEditingController controller;

  /// Refresh the UI (mic button colour, input text) — the screen's `setState`.
  final VoidCallback notify;

  /// Follow the growing input so the owner sees speech become text live.
  final VoidCallback? autoScroll;

  HarnessVoiceService get _voice => HarnessVoiceService.instance;
  HarnessReportDraft get _draft => HarnessReportDraft.instance;

  /// Full capture of the SHARED report draft taken when the chat mic starts,
  /// restored verbatim when it stops — so chat dictation can never mutate a real
  /// report draft. Null when the chat isn't borrowing the recognizer.
  HarnessReportDraftSnapshot? _draftSnapshot;

  /// The chat input text that already existed BEFORE the current dictation turn
  /// began. Live dictated words are appended to this for display.
  String _preVoiceText = '';

  /// The draft note at the moment the mic started, so we extract only the words
  /// dictated DURING this chat turn from the borrowed shared draft.
  String _voiceBaseline = '';

  /// The chat's OWN accumulated dictation buffer for the current mic turn — fully
  /// decoupled from the borrowed report draft. Committed finals are copied here
  /// the moment they land in the draft, so when the draft is RESTORED on mic-off
  /// the chat input keeps its text.
  String _dictationBuffer = '';

  /// Guard so controller updates WE make (mirroring dictation) aren't treated as
  /// the owner typing in onChanged (which would stop the mic).
  bool _applyingVoiceText = false;

  bool get applyingVoiceText => _applyingVoiceText;
  bool get isListening => _voice.isListening;

  /// Register the voice-service listener (call from init).
  void start() {
    _voice.addListener(_onVoiceUpdate);
  }

  /// Stop the mic + restore the borrowed draft + remove the listener.
  Future<void> dispose() async {
    await stop();
    _voice.removeListener(_onVoiceUpdate);
  }

  /// Toggle the in-app mic. On start we SNAPSHOT the entire shared report draft
  /// (so we can put it back untouched), baseline its note so we only pull THIS
  /// turn's dictated words, and remember the chat input we already had.
  Future<void> toggleMic() async {
    if (_voice.isListening) {
      await stop();
      return;
    }
    _draftSnapshot = _draft.snapshot();
    if (!_draft.started) {
      _draft.start(screen: 'orchestrator_chat');
    }
    _voiceBaseline = _draft.note;
    _preVoiceText = controller.text;
    _dictationBuffer = '';
    notify();
    await _voice.start();
  }

  /// Stop the mic and RESTORE the borrowed report draft to its pre-chat snapshot —
  /// the chat input already holds the dictated text, so the real draft is left
  /// exactly as the owner had it. Idempotent AND inert when not borrowing.
  Future<void> stop() async {
    if (_draftSnapshot == null) {
      // Not borrowing — defensive native stop only, never recompose.
      if (_voice.isListening) await _voice.stop();
      return;
    }

    if (_voice.isListening) {
      // stop() flushes any in-flight tail into the borrowed draft and fires
      // _onVoiceUpdate, which folds it into _dictationBuffer + the input.
      await _voice.stop();
    }
    // Capture the final draft delta into our OWN buffer BEFORE restoring the draft.
    _captureDeltaIntoBuffer();
    final shown = _composeInput();
    if (shown != controller.text) {
      _applyingVoiceText = true;
      controller.value = TextEditingValue(
        text: shown,
        selection: TextSelection.collapsed(offset: shown.length),
      );
      _applyingVoiceText = false;
    }
    final snap = _draftSnapshot;
    _draftSnapshot = null; // clear FIRST so the restore's notify is ignored
    _draft.restore(snap!);
    _resetDictationState();
  }

  /// Post-send reset: dictation baselines + the borrow all clear so the next
  /// message starts fresh. The borrowed draft was already restored by [stop].
  void markSent() {
    _resetDictationState();
    _draftSnapshot = null;
  }

  /// onChanged: the owner is typing → keyboard text is authoritative. Ignore our
  /// own dictation-mirroring updates; otherwise tear down a live mic turn WITHOUT
  /// recomposing the controller.
  void handleUserTyping() {
    if (_applyingVoiceText) return;
    if (_draftSnapshot != null || _voice.isListening) {
      _teardownVoiceForTyping();
    }
  }

  void _teardownVoiceForTyping() {
    final snap = _draftSnapshot;
    _draftSnapshot = null; // inert FIRST — no recompose after this point
    if (_voice.isListening) {
      // Best-effort native stop; the flushed tail lands in the about-to-be-
      // discarded borrowed draft and is intentionally dropped — typed text wins.
      _voice.stop();
    }
    if (snap != null) _draft.restore(snap);
    _resetDictationState();
  }

  void _resetDictationState() {
    _voiceBaseline = '';
    _preVoiceText = '';
    _dictationBuffer = '';
  }

  /// Fold this turn's committed dictation (the draft delta beyond the baseline)
  /// into the chat's own [_dictationBuffer] so it survives a draft restore.
  void _captureDeltaIntoBuffer() {
    final fullNote = _draft.note;
    String delta = fullNote;
    if (_voiceBaseline.isNotEmpty && fullNote.startsWith(_voiceBaseline)) {
      delta = fullNote.substring(_voiceBaseline.length);
    }
    final committed = delta.trim();
    if (committed.isNotEmpty) _dictationBuffer = committed;
  }

  /// Compose the chat input from what the owner already had + this turn's
  /// committed dictation + the live (not-yet-final) partial.
  String _composeInput() {
    final live = _voice.liveTranscript.trim();
    final parts = <String>[
      _preVoiceText.trimRight(),
      _dictationBuffer.trim(),
      live == HarnessVoiceService.preparingHint ? '' : live,
    ].where((p) => p.isNotEmpty);
    return parts.join(' ');
  }

  /// Each draft change (final + live partial), reflect the dictated delta into the
  /// chat input — appended to whatever the input held before this mic turn.
  void _onVoiceUpdate() {
    if (_draftSnapshot == null) {
      notify(); // still refresh the mic button colour
      return;
    }
    _captureDeltaIntoBuffer();
    final shown = _composeInput();
    if (shown != controller.text) {
      _applyingVoiceText = true;
      controller.value = TextEditingValue(
        text: shown,
        selection: TextSelection.collapsed(offset: shown.length),
      );
      _applyingVoiceText = false;
      autoScroll?.call();
    }
    notify();
  }
}
