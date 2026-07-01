import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../harness/harness_config.g.dart';
import 'chat/screens/orchestrator_chat_screen.dart';
import 'dev_gate.dart';
import 'harness_theme.dart';
import 'report_capture/screens/report_capture_screen.dart';
import 'report_queue/screens/report_queue_screen.dart';
import 'services/harness_providers.dart';

/// The owner COMMAND CENTER (harness point 4) — the active control surface for the
/// ported harness. Not a passive screen: it resolves the owner identity, shows the
/// live backend/mode + report counts, and routes to every owner control (chat,
/// file-report, queue, poke). Ported from Blueprint's dev-status surface, trimmed
/// to the Stock-Track slice.
class HarnessHomeScreen extends ConsumerWidget {
  const HarnessHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uidAsync = ref.watch(ownerUidProvider);
    return Scaffold(
      backgroundColor: HarnessTheme.background,
      appBar: AppBar(
        title: const Text('Stock-Track Harness'),
        backgroundColor: HarnessTheme.panel,
      ),
      body: uidAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _BackendNotReady(error: e, onRetry: () => ref.invalidate(ownerUidProvider)),
        data: (uid) => _CommandCenter(uid: uid),
      ),
    );
  }
}

class _CommandCenter extends ConsumerWidget {
  const _CommandCenter({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(ownerReportsProvider(uid));
    final openCount = reportsAsync.maybeWhen(
      data: (r) => r.where((x) =>
          x.status != 'fixed' && x.status != 'wont_fix' && !x.manualResolved).length,
      orElse: () => null,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusCard(context, openCount),
        const SizedBox(height: 16),
        const Text('OWNER CONTROLS',
            style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _tile(
          context,
          icon: Icons.forum_outlined,
          title: 'Orchestrator chat',
          subtitle: 'Message the orchestrator; see replies live.',
          onTap: () => _push(context, OrchestratorChatScreen(uid: uid)),
        ),
        _tile(
          context,
          icon: Icons.bug_report_outlined,
          title: 'File a report',
          subtitle: 'Note + optional screenshots → the queue.',
          onTap: () => _push(context, ReportCaptureScreen(uid: uid)),
        ),
        _tile(
          context,
          icon: Icons.inbox_outlined,
          title: 'Report queue',
          subtitle: openCount == null
              ? 'Read + triage your reports.'
              : '$openCount open · read + triage.',
          onTap: () => _push(context, ReportQueueScreen(uid: uid)),
        ),
        _PokeTile(uid: uid),
        const SizedBox(height: 20),
        _separationFooter(),
      ],
    );
  }

  Widget _statusCard(BuildContext context, int? openCount) {
    final mode = kHarnessMode == HarnessMode.firebase ? 'Firebase' : 'Mock';
    final shortUid = uid.length > 12 ? '${uid.substring(0, 12)}…' : uid;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HarnessTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HarnessTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, size: 18, color: HarnessTheme.accent),
              const SizedBox(width: 8),
              Text('${HarnessConfig.projectName} owner harness',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          _kv('Backend', '$mode · ${HarnessConfig.reportsCollection} in easy-stock-track'),
          _kv('Owner role', HarnessConfig.ownerRole),
          Row(
            children: [
              Expanded(child: _kv('Owner UID', shortUid)),
              IconButton(
                tooltip: 'Copy full UID',
                icon: Icon(Icons.copy, size: 16, color: HarnessTheme.accent),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: uid));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Owner UID copied')),
                  );
                },
              ),
            ],
          ),
          if (openCount != null) _kv('Open reports', '$openCount'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(k,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Colors.white.withValues(alpha: 0.04),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        leading: Icon(icon, color: HarnessTheme.accent),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing:
            const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }

  Widget _separationFooter() {
    return Center(
      child: Text(
        'Harness instance: ${HarnessConfig.projectName} · easy-stock-track\n'
        'Separate from any other app — its own Firebase, its own data.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white24, fontSize: 10, height: 1.4),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _PokeTile extends ConsumerStatefulWidget {
  const _PokeTile({required this.uid});
  final String uid;

  @override
  ConsumerState<_PokeTile> createState() => _PokeTileState();
}

class _PokeTileState extends ConsumerState<_PokeTile> {
  bool _poked = false;

  Future<void> _poke() async {
    setState(() => _poked = true);
    try {
      await ref.read(reportRepositoryProvider).pokeOrchestrator(note: 'owner poke');
    } catch (_) {}
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _poked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withValues(alpha: 0.04),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        leading: Icon(_poked ? Icons.check_circle : Icons.notifications_active_outlined,
            color: HarnessTheme.accent),
        title: Text(_poked ? 'Poked' : 'Poke the orchestrator',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: const Text('Bump system/orchestratorPoke — wake the loop now.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        onTap: _poked ? null : _poke,
      ),
    );
  }
}

/// Shown when Firebase Anonymous Auth / Firestore isn't enabled yet in
/// easy-stock-track — an actionable state, not a crash. Names the exact Brandon
/// setup and points at the checklist doc.
class _BackendNotReady extends StatelessWidget {
  const _BackendNotReady({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.settings_suggest_outlined,
                color: Colors.white38, size: 44),
            const SizedBox(height: 14),
            const Text('Backend not enabled yet',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              'The harness needs Firestore + Anonymous Auth turned on in the '
              'easy-stock-track Firebase project. See '
              'docs/FOR_BRANDON_harness_backend.md for the exact steps.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 10),
            Text('$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 11)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: HarnessTheme.accent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
