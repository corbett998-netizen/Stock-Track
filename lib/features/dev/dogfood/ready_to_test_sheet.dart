import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../harness_theme.dart';
import '../report_queue/models/report.dart';
import '../services/harness_providers.dart';

/// The in-app "Ready to test" checklist — the CONSUMPTION half of the dogfood verify
/// loop. Without it, every operator "announce build" check-item is a dead write and
/// the "owner tests from his phone" premise fails.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic: it reads the generic owner
/// reports stream, filters to `awaitingVerification`, and closes each item through
/// the repository's canonical resolved/reopened writes. It hardcodes no project id /
/// collection / owner value; theme comes from the `HarnessTheme` seam.
Future<void> showReadyToTestSheet(BuildContext context, {required String uid}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: HarnessTheme.panel,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ReadyToTestSheet(uid: uid),
  );
}

class ReadyToTestSheet extends ConsumerStatefulWidget {
  const ReadyToTestSheet({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<ReadyToTestSheet> createState() => _ReadyToTestSheetState();
}

class _ReadyToTestSheetState extends ConsumerState<ReadyToTestSheet> {
  String? _busyId;

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() => _busyId = id);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(ownerReportsProvider(widget.uid));
    final items = reportsAsync.maybeWhen(
      data: (r) => r.where((x) => x.awaitingVerification).toList(),
      orElse: () => const <Report>[],
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _grip(),
            _header(items.length),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: reportsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _message('Couldn\'t load: $e'),
                data: (_) => items.isEmpty
                    ? _message(
                        'Nothing to test right now.\nShipped fixes show up here to verify.',
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _item(items[i]),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _grip() => Center(
    child: Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _header(int count) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: Row(
      children: [
        Icon(Icons.fact_check_outlined, color: HarnessTheme.accent, size: 20),
        const SizedBox(width: 8),
        const Text(
          'Ready to test',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: HarnessTheme.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: HarnessTheme.accent.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: HarnessTheme.accent,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _item(Report r) {
    final busy = _busyId == r.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.displayTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 13,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 4),
              Text(
                'Test on: ${r.testOnLabel}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              if ((r.appBuild ?? '').isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  'build ${r.appBuild}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(
                          r.id,
                          () => ref
                              .read(reportRepositoryProvider)
                              .markVerifiedWorks(r.id),
                        ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Works'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(
                          r.id,
                          () => ref
                              .read(reportRepositoryProvider)
                              .markStillBroken(r.id),
                        ),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Still broken'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF9A9A),
                    side: const BorderSide(color: Color(0x55EF9A9A)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, height: 1.4),
      ),
    ),
  );
}
