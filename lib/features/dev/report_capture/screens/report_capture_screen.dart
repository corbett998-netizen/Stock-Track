import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../harness_theme.dart';
import '../../services/harness_providers.dart';

/// File-a-report CAPTURE (harness point 2) — a note + optional screenshots →
/// writes `stockIssueReports` (with screenshots to Storage) in easy-stock-track.
/// Ported from Blueprint's `mobile_issue_report_screen`, trimmed to the Stock-Track
/// slice (BP's voice dictation, route-region tagging + log upload are DEFERRED).
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

  static const int _maxShots = 4;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
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
    setState(() => _submitting = true);
    try {
      await ref
          .read(reportRepositoryProvider)
          .fileReport(
            uid: widget.uid,
            note: note,
            screenshots: List<XFile>.unmodifiable(_shots),
          );
      if (!mounted) return;
      _snack('Report filed.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        _snack("Couldn't file the report: $e");
      }
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HarnessTheme.background,
      // Keyboard (note field) shrinks the body; the bottom SafeArea keeps the
      // File-report button clear of the Android nav bar (§7).
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
            const Text(
              'What happened?',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
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
