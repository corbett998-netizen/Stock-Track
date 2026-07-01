import 'package:flutter/material.dart';

import '../../services/harness_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/report.dart';
import 'report_common.dart';
import 'report_detail.dart';
import 'report_triage_block.dart';

/// One report card — collapsed summary; expands to the triage detail with the
/// write controls. Ported from Blueprint's `ReportCard`, trimmed to the Stock-Track
/// slice (BP's nested follow-ups + clarification block are DEFERRED). Holds its own
/// expand + optimistic decision state; all writes go through the [ReportRepository]
/// via Riverpod.
class ReportCard extends ConsumerStatefulWidget {
  const ReportCard({super.key, required this.report});

  final Report report;

  @override
  ConsumerState<ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<ReportCard> {
  bool _expanded = false;
  bool _saving = false;
  String? _pendingDecision;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<bool> _runWrite(Future<void> Function() write) async {
    setState(() => _saving = true);
    try {
      await write();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setTriage(String? decision) async {
    final prev = _pendingDecision;
    setState(() => _pendingDecision = decision);
    final ok = await _runWrite(() => ref
        .read(reportRepositoryProvider)
        .setTriageDecision(widget.report.id, decision: decision));
    if (!ok && mounted) setState(() => _pendingDecision = prev);
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    final ok = await _runWrite(() => ref
        .read(reportRepositoryProvider)
        .addComment(widget.report.id, text: text));
    if (ok && mounted) _commentCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summary(r),
          ReportTriageBlock(
            report: r,
            decision: _pendingDecision ?? r.triageDecision,
            saving: _saving,
            onExecute: () => _setTriage('execute'),
            onDiscuss: () => _setTriage('discuss'),
            onUndo: () => _setTriage(null),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            ReportDetail(
              report: r,
              saving: _saving,
              commentController: _commentCtrl,
              onAddComment: _addComment,
              onStatusChanged: (s) => _runWrite(() => ref
                  .read(reportRepositoryProvider)
                  .updateStatus(r.id, status: s)),
              onResolvedToggle: (v) => _runWrite(() => ref
                  .read(reportRepositoryProvider)
                  .setManualResolved(r.id, value: v)),
              onFlagToggle: (v) => _runWrite(() =>
                  ref.read(reportRepositoryProvider).setFlagged(r.id, v)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(Report r) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.screenshots.isNotEmpty) ...[
              _thumb(r.screenshots.first, r.screenshots.length),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ReportStatusChip(r.effectiveStatus),
                      ReportMetaChip(Icons.place_outlined, r.area),
                      ReportMetaChip(Icons.schedule, relativeTime(r.createdAt)),
                      if (r.flaggedForOrchestrator)
                        const ReportMetaChip(Icons.flag, 'flagged',
                            color: kReportAccent),
                    ],
                  ),
                ],
              ),
            ),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _thumb(String url, int count) {
    if (!url.startsWith('http')) return const ReportThumbPlaceholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ReportThumbPlaceholder(),
        loadingBuilder: (c, child, p) =>
            p == null ? child : const ReportThumbPlaceholder(),
      ),
    );
  }
}
