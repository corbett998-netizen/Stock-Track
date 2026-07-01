import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../harness_theme.dart';
import '../../services/harness_providers.dart';

/// Read-only workflow dashboard — the operator's at-a-glance "current state +
/// evidence + waiting-on-owner" panel, read from the published
/// `system/workflowContext` projection. Honest about staleness: a "nothing
/// published" empty state and a stale banner when the projection is old.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic; reads the generic
/// `workflowContextProvider`, theme via the `HarnessTheme` seam. No app identity.
Future<void> showWorkflowDashboardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: HarnessTheme.panel,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _WorkflowDashboardSheet(),
  );
}

/// How old a projection can be before it reads as stale.
const Duration _staleAfter = Duration(hours: 6);

class _WorkflowDashboardSheet extends ConsumerWidget {
  const _WorkflowDashboardSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(workflowContextProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.dashboard_outlined, color: HarnessTheme.accent),
              const SizedBox(width: 8),
              const Text(
                'Workflow dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white54),
                tooltip: 'Refresh',
                onPressed: () => ref.invalidate(workflowContextProvider),
              ),
            ],
          ),
          const SizedBox(height: 8),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _empty('Couldn\'t read the projection.\n$e'),
            data: (ctx) => (ctx == null || ctx.isEmpty)
                ? _empty(
                    'No workflow context published yet.\n'
                    'The operator publishes it from the CLI '
                    '(system/workflowContext).',
                  )
                : _body(ctx),
          ),
        ],
      ),
    );
  }

  Widget _body(Map<String, dynamic> ctx) {
    final staleBanner = _staleBanner(ctx['updatedAt']);
    final rows = <Widget>[
      if (staleBanner != null) staleBanner,
      _kv('Lane', ctx['lane']),
      _kv('Build', ctx['build']),
      _kv('State', ctx['state']),
      _kv('Waiting on owner', ctx['waitingOnOwner']),
      _kv('Updated', ctx['updatedAt']),
    ];
    // Any additional published keys, generically.
    const known = {'lane', 'build', 'state', 'waitingOnOwner', 'updatedAt'};
    for (final e in ctx.entries) {
      if (!known.contains(e.key)) rows.add(_kv(e.key, e.value));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget? _staleBanner(Object? updatedAt) {
    final ts = _parseTime(updatedAt);
    if (ts == null) return null;
    final age = DateTime.now().difference(ts);
    if (age <= _staleAfter) return null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.amber,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Stale — last published ${age.inHours}h ago.',
              style: const TextStyle(color: Colors.amber, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  static DateTime? _parseTime(Object? v) {
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  Widget _kv(String k, Object? v) {
    final value = (v == null || '$v'.trim().isEmpty) ? '—' : '$v';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String message) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white54, height: 1.4),
    ),
  );
}
