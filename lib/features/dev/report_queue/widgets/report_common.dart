import 'package:flutter/material.dart';

import '../../harness_theme.dart';

/// The single accent threaded through the report-queue panel. Ported from
/// Blueprint's `report_common`; the BP `IntakeCardStyling.primaryOrange` coupling
/// is STRIPPED — this reads Stock-Track's [HarnessTheme.accent].
const Color kReportAccent = HarnessTheme.accent;

/// Status → chip colour. Pure.
Color reportStatusColor(String status) {
  switch (status) {
    case 'fixed':
      return const Color(0xFF4CAF50);
    case 'wont_fix':
      return Colors.grey;
    case 'in_progress':
      return kReportAccent;
    case 'awaiting_decision':
      return Colors.amber;
    case 'new':
    case 'queued':
    default:
      return const Color(0xFF42A5F5);
  }
}

/// A coarse "x ago" string. Pure.
String relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// The coloured status pill on a collapsed card.
class ReportStatusChip extends StatelessWidget {
  const ReportStatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = reportStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A tiny icon + label meta chip (area / time / flagged).
class ReportMetaChip extends StatelessWidget {
  const ReportMetaChip(this.icon, this.text, {super.key, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white.withValues(alpha: 0.55);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: c)),
      ],
    );
  }
}

/// Placeholder for a missing / loading screenshot thumbnail.
class ReportThumbPlaceholder extends StatelessWidget {
  const ReportThumbPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.image_outlined,
          size: 20, color: Colors.white.withValues(alpha: 0.3)),
    );
  }
}
