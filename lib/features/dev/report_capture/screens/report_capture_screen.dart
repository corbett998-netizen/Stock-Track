import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/current_screen_tracker.dart';
import '../../harness_theme.dart';
import '../../services/harness_providers.dart';
import '../../voice/harness_report_draft.dart';
import '../../voice/harness_voice_service.dart';

/// File-a-report CAPTURE — a note + optional screenshots → writes
/// `stockIssueReports`. The note is backed by the shared [HarnessReportDraft], so
/// a report DICTATED from the floating cluster mic (while dogfooding on another
/// screen) hydrates here, keeping the SCREEN it was started on. Mic dictation uses
/// the app-owned native recognizer ([HarnessVoiceService]) — the reference mic
/// pattern — not a focused-field OS-keyboard seam. Screenshot upload is
/// Storage-gated (renders locally when Storage is off).
class ReportCaptureScreen extends ConsumerStatefulWidget {
  const ReportCaptureScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<ReportCaptureScreen> createState() =>
      _ReportCaptureScreenState();
}

class _ReportCaptureScreenState extends ConsumerState<ReportCaptureScreen> {
  final TextEditingController _note = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _shots = <XFile>[];
  bool _submitting = false;
  bool _listening = false;

  /// Guard so draft→field syncs (mic appends) aren't re-written back to the draft
  /// as if they were keyboard edits (which would loop).
  bool _syncingFromDraft = false;

  static const int _maxShots = 4;

  HarnessReportDraft get _draft => HarnessReportDraft.instance;
  HarnessVoiceService get _voice => HarnessVoiceService.instance;

  @override
  void initState() {
    super.initState();
    // Freeze the screen context at report-open if a floating-mic draft didn't
    // already start one — so a keyboard report also attributes to the right screen.
    if (!_draft.started) {
      _draft.start(screen: CurrentScreenTracker.currentScreen);
    }
    // Hydrate from a mic-dictated (or resumed) draft.
    _note.text = _draft.note;
    _note.selection = TextSelection.collapsed(offset: _note.text.length);
    _draft.addListener(_onDraftChanged);
    _voice.addListener(_onVoiceChanged);
    _listening = _voice.isListening;
  }

  @override
  void dispose() {
    _draft.removeListener(_onDraftChanged);
    _voice.removeListener(_onVoiceChanged);
    // Don't leave a hot mic with no visible control if the owner leaves.
    if (_voice.isListening) _voice.stop();
    _note.dispose();
    super.dispose();
  }

  /// Mic appended a final to the draft → reflect it in the field (guarded so our
  /// own keyboard write-through doesn't recurse).
  void _onDraftChanged() {
    if (_syncingFromDraft) return;
    if (_draft.note == _note.text) return;
    _syncingFromDraft = true;
    _note.text = _draft.note;
    _note.selection = TextSelection.collapsed(offset: _note.text.length);
    _syncingFromDraft = false;
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    final listening = _voice.isListening;
    final err = _voice.error;
    setState(() => _listening = listening);
    if (err != null && err.isNotEmpty) _snack(err);
  }

  /// Keyboard edits write through to the shared draft (so mic + typing mix and the
  /// draft is the single source of truth the report is filed from).
  void _onNoteChanged(String value) {
    if (_syncingFromDraft) return;
    _draft.setNote(value);
  }

  // App-owned continuous dictation into the shared draft — runs even while the
  // note field isn't focused. The service owns start/append/re-arm; we just toggle
  // and reflect its listening state.
  Future<void> _toggleMic() async {
    if (_listening) {
      await _voice.stop();
      return;
    }
    await _voice.start();
    final err = _voice.error;
    if (err != null && err.isNotEmpty) {
      _snack('Mic unavailable — check the microphone permission.');
    }
  }

  Future<void> _pick() async {
    if (_shots.length >= _maxShots) {
      _snack('Max $_maxShots screenshots.');
      return;
    }
    final picked = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked.isEmpty) return;
    setState(() {
      _shots.addAll(picked.take(_maxShots - _shots.length));
    });
  }

  Future<void> _submit() async {
    final note = _note.text.trim();
    if (note.isEmpty) {
      _snack('Add a note describing the issue.');
      return;
    }
    if (_listening) await _voice.stop();
    setState(() => _submitting = true);
    try {
      final id = await ref
          .read(reportRepositoryProvider)
          .fileReport(
            uid: widget.uid,
            note: note,
            screenshots: List<XFile>.unmodifiable(_shots),
            // The FROZEN screen the report was started on (mic-start or report-open)
            // — so a report dictated on another screen attributes there, not here.
            region: _draft.screen,
          );
      if (!mounted) return;
      // Draft filed — clear it so the floating-mic "draft waiting" cue resets.
      _draft.clear();
      await _showFiledDialog(id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        _snack("Couldn't file the report: $e");
      }
    }
  }

  /// Submit-success: show a short, copyable report ID so the owner can reference it
  /// in chat.
  Future<void> _showFiledDialog(String id) {
    final shortId = id.length > 10 ? id.substring(0, 10) : id;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HarnessTheme.panel,
        title: const Text(
          'Report filed',
          style: TextStyle(color: Colors.white),
        ),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ID ', style: TextStyle(color: Colors.white54)),
            SelectableText(
              shortId,
              style: TextStyle(
                color: HarnessTheme.accent,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            IconButton(
              tooltip: 'Copy report ID',
              icon: Icon(Icons.copy, size: 18, color: HarnessTheme.accent),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: id));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Report ID copied')),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final screen = _draft.screen;
    final partial = _voice.liveTranscript.trim();
    return Scaffold(
      backgroundColor: HarnessTheme.background,
      // Keyboard (note field) shrinks the body; the bottom SafeArea keeps the
      // File-report button clear of the Android nav bar.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('File a report'),
        backgroundColor: HarnessTheme.panel,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (screen != null && screen.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Reporting on: $screen',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                const Text(
                  'What happened?',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // App-owned native dictation into the shared draft. Degrades to a
                // snack when the mic/engine is unavailable.
                TextButton.icon(
                  onPressed: _submitting ? null : _toggleMic,
                  icon: Icon(
                    _listening ? Icons.stop_circle : Icons.mic_none,
                    size: 18,
                    color: _listening ? Colors.redAccent : HarnessTheme.accent,
                  ),
                  label: Text(
                    _listening ? 'Stop' : 'Dictate',
                    style: TextStyle(
                      color: _listening
                          ? Colors.redAccent
                          : HarnessTheme.accent,
                    ),
                  ),
                ),
              ],
            ),
            if (_listening)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  partial.isEmpty ? 'Listening…' : partial,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontStyle: partial.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              onChanged: _onNoteChanged,
              minLines: 4,
              maxLines: 10,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Describe the bug or feedback…',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pick,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: const Text('Add screenshot'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_shots.length}/$_maxShots',
                  style: const TextStyle(color: Colors.white38),
                ),
              ],
            ),
            if (_shots.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (int i = 0; i < _shots.length; i++) _thumb(i)],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_submitting ? 'Filing…' : 'File report'),
              style: FilledButton.styleFrom(
                backgroundColor: HarnessTheme.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(int i) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FutureBuilder(
              future: _shots[i].readAsBytes(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return Container(color: Colors.white.withValues(alpha: 0.06));
                }
                return Image.memory(snap.data!, fit: BoxFit.cover);
              },
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const CircleAvatar(
                radius: 11,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
              onPressed: _submitting
                  ? null
                  : () => setState(() => _shots.removeAt(i)),
            ),
          ),
        ],
      ),
    );
  }
}
