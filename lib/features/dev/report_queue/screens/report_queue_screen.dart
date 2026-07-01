import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../harness_theme.dart';
import '../../services/harness_providers.dart';
import '../models/report.dart';
import '../models/report_filter.dart';
import '../widgets/report_card.dart';
import '../widgets/report_filter_bar.dart';

/// The owner REPORT QUEUE (harness point 3) — reads/triages the owner's own
/// reports. Ported from Blueprint's report-queue screen, trimmed to the Stock-Track
/// slice. A complete owner loop client-side: it works even before the orchestrator
/// can reply (the owner files, reads, and triages their own reports).
class ReportQueueScreen extends ConsumerStatefulWidget {
  const ReportQueueScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<ReportQueueScreen> createState() => _ReportQueueScreenState();
}

class _ReportQueueScreenState extends ConsumerState<ReportQueueScreen> {
  ReportFilter _filter = ReportFilter.all;
  bool _poked = false;

  Future<void> _poke() async {
    setState(() => _poked = true);
    try {
      await ref.read(reportRepositoryProvider).pokeOrchestrator();
    } catch (_) {}
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _poked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(ownerReportsProvider(widget.uid));
    return Scaffold(
      backgroundColor: HarnessTheme.background,
      // Keyboard (comment composer inside a card) shrinks the body; the bottom
      // SafeArea keeps the last card + composer clear of the Android nav bar (§7).
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Report queue'),
        backgroundColor: HarnessTheme.panel,
        actions: [
          TextButton.icon(
            onPressed: _poked ? null : _poke,
            icon: Icon(
              _poked ? Icons.check : Icons.notifications_active_outlined,
              size: 18,
              color: HarnessTheme.accent,
            ),
            label: Text(
              _poked ? 'Poked' : 'Poke',
              style: TextStyle(color: HarnessTheme.accent),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            ReportFilterBar(
              selected: _filter,
              onSelected: (f) => setState(() => _filter = f),
            ),
            Expanded(
              child: reportsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _errorState(e),
                data: (reports) => _list(reports),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<Report> all) {
    final reports = all.where(_filter.matches).toList();
    if (reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            all.isEmpty
                ? 'No reports yet.\nFile one from the command center.'
                : 'No reports match "${_filter.label}".',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: reports.length,
      itemBuilder: (_, i) => ReportCard(report: reports[i]),
    );
  }

  // (report stream comes from ownerReportsProvider in harness_providers.dart)

  Widget _errorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Colors.white38, size: 40),
            const SizedBox(height: 12),
            const Text(
              "Couldn't load reports.",
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
