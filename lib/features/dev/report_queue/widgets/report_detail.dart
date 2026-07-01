import 'package:flutter/material.dart';

import '../models/report.dart';
import 'report_common.dart';

/// The expanded report detail — status dropdown, resolved / flag toggles, the
/// comment thread + composer, and any screenshots. Ported from Blueprint's
/// `ReportDetail`, trimmed to the Stock-Track slice. Stateless; the owning card
/// supplies the controllers + callbacks.
class ReportDetail extends StatelessWidget {
  const ReportDetail({
    super.key,
    required this.report,
    required this.saving,
    required this.commentController,
    required this.onAddComment,
    required this.onStatusChanged,
    required this.onResolvedToggle,
    required this.onFlagToggle,
  });

  final Report report;
  final bool saving;
  final TextEditingController commentController;
  final VoidCallback onAddComment;
  final void Function(String status) onStatusChanged;
  final void Function(bool value) onResolvedToggle;
  final void Function(bool value) onFlagToggle;

  static const _statuses = <String>[
    'new',
    'queued',
    'in_progress',
    'awaiting_decision',
    'fixed',
    'wont_fix',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.note.isNotEmpty) ...[
            Text(
              report.note,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (report.screenshots.isNotEmpty) ...[
            _screenshots(),
            const SizedBox(height: 10),
          ],
          if ((report.appBuild ?? '').isNotEmpty ||
              (report.platform ?? '').isNotEmpty) ...[
            _metaLine(),
            const SizedBox(height: 8),
          ],
          if ((report.logsInline ?? '').isNotEmpty) ...[
            _deviceLogTail(),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              const Text(
                'Status',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(width: 10),
              _statusDropdown(),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: kReportAccent,
                  title: const Text(
                    'Resolved',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  value: report.manualResolved,
                  onChanged: saving ? null : onResolvedToggle,
                ),
              ),
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: kReportAccent,
                  title: const Text(
                    'Flag',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  value: report.flaggedForOrchestrator,
                  onChanged: saving ? null : onFlagToggle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (report.comments.isNotEmpty) ...[
            const Text(
              'COMMENTS',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final c in report.comments) _comment(c),
            const SizedBox(height: 6),
          ],
          _commentComposer(),
        ],
      ),
    );
  }

  Widget _statusDropdown() {
    return DropdownButton<String>(
      value: _statuses.contains(report.status) ? report.status : 'new',
      dropdownColor: HarnessPanelColor.value,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      underline: const SizedBox.shrink(),
      onChanged: saving
          ? null
          : (v) {
              if (v != null) onStatusChanged(v);
            },
      items: [
        for (final s in _statuses) DropdownMenuItem(value: s, child: Text(s)),
      ],
    );
  }

  /// Capture context — the build that produced the report + the platform. Answers
  /// "which build / device is this bug on?" at a glance.
  Widget _metaLine() {
    final parts = <String>[
      if ((report.appBuild ?? '').isNotEmpty) 'build ${report.appBuild}',
      if ((report.platform ?? '').isNotEmpty) report.platform!,
    ];
    return Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 13,
          color: Colors.white.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            parts.join('  ·  '),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// Expandable device-log tail — the logs-first triage surface. Diagnose from the
  /// evidence the report carried, in-app, without asking for a capture.
  Widget _deviceLogTail() {
    final logs = report.logsInline ?? '';
    return Theme(
      // Strip the ExpansionTile's default dividers so it sits flush in the card.
      data: ThemeData.dark().copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        iconColor: kReportAccent,
        collapsedIconColor: Colors.white38,
        title: Row(
          children: [
            Icon(Icons.terminal, size: 14, color: kReportAccent),
            const SizedBox(width: 6),
            const Text(
              'DEVICE LOG TAIL',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                logs,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _screenshots() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: report.screenshots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final url = report.screenshots[i];
          if (!url.startsWith('http')) return const ReportThumbPlaceholder();
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ReportThumbPlaceholder(),
              loadingBuilder: (c, child, p) =>
                  p == null ? child : const ReportThumbPlaceholder(),
            ),
          );
        },
      ),
    );
  }

  Widget _comment(Map<String, dynamic> c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 12,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${c['text'] ?? ''}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentComposer() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: commentController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add a comment…',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.send, size: 18, color: kReportAccent),
          onPressed: saving ? null : onAddComment,
        ),
      ],
    );
  }
}

/// Small indirection so the dropdown menu background matches the harness panel
/// without importing the theme in a const position.
class HarnessPanelColor {
  static const Color value = Color(0xFF111827);
}
