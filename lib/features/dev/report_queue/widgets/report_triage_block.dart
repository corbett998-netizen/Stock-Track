import 'package:flutter/material.dart';

import '../models/report.dart';
import 'report_common.dart';

/// The always-visible triage strip — a one-line recommended fix and, until the
/// owner decides, the Execute / Discuss buttons ("nothing sits at 'new'"). Ported
/// from Blueprint's `ReportTriageBlock`, trimmed to the Stock-Track slice.
class ReportTriageBlock extends StatelessWidget {
  const ReportTriageBlock({
    super.key,
    required this.report,
    required this.decision,
    required this.saving,
    required this.onExecute,
    required this.onDiscuss,
    required this.onUndo,
  });

  final Report report;
  final String? decision;
  final bool saving;
  final VoidCallback onExecute;
  final VoidCallback onDiscuss;
  final VoidCallback onUndo;

  bool get _isResolved =>
      report.status == 'fixed' ||
      report.status == 'wont_fix' ||
      report.manualResolved;

  @override
  Widget build(BuildContext context) {
    final rec = report.displayRecommendation;
    final hasRec = rec.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  size: 12, color: kReportAccent.withValues(alpha: 0.8)),
              const SizedBox(width: 4),
              Text(
                'RECOMMENDED FIX',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: kReportAccent.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            hasRec ? rec : 'Awaiting recommendation…',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              fontStyle: hasRec ? FontStyle.normal : FontStyle.italic,
              color: Colors.white.withValues(alpha: hasRec ? 0.85 : 0.45),
            ),
          ),
          const SizedBox(height: 8),
          if (_isResolved)
            _tag('Fixed', Icons.check_circle_outline, Colors.greenAccent)
          else if (decision == null)
            _triageButtons(hasRec)
          else
            _decisionTag(decision!),
        ],
      ),
    );
  }

  Widget _triageButtons(bool hasRec) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (saving || !hasRec) ? null : onExecute,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Execute fix'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kReportAccent,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.3),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: saving ? null : onDiscuss,
            icon: const Icon(Icons.forum_outlined, size: 16),
            label: const Text('Discuss'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.85),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              padding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
      ],
    );
  }

  Widget _decisionTag(String decision) {
    final isExecute = decision == 'execute';
    final color = isExecute ? kReportAccent : Colors.amber;
    return Row(
      children: [
        _tag(isExecute ? 'Executing' : 'In discussion',
            isExecute ? Icons.play_arrow : Icons.forum_outlined, color),
        const Spacer(),
        TextButton(
          onPressed: saving ? null : onUndo,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Undo', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _tag(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
