import '../models/chat_item.dart';

/// Paste-ready export frames for the owner↔orchestrator chat — the "run the build
/// from your phone" lever: copy a curated, paste-ready context to hand an external
/// LLM.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — pure formatting, app-agnostic. It takes
/// the thread + an optional published workflow-context map and the host app's name /
/// build as plain values, so it hardcodes NO project identity. Degrades gracefully
/// when no workflow context is published (the block simply omits that section).
class ChatExport {
  ChatExport._();

  static const String _owner = 'Owner';
  static const String _orchestrator = 'Orchestrator';

  static String _who(ChatItem m, String ownerRole) =>
      m.role == ownerRole ? _owner : _orchestrator;

  static String _time(int ms) {
    if (ms <= 0) return '--:--';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  static String _line(ChatItem m, String ownerRole) =>
      '[${_time(m.createdAtMs)}] ${_who(m, ownerRole)}: ${m.text}';

  /// One bubble → a single labelled line.
  static String oneBubble(ChatItem m, {required String ownerRole}) =>
      _line(m, ownerRole);

  /// A block of the selected/visible messages — no preamble (the "copy work-area"
  /// lever: grab the conversation to paste elsewhere).
  static String threadBlock(List<ChatItem> items, {required String ownerRole}) {
    if (items.isEmpty) return '(no messages)';
    return items.map((m) => _line(m, ownerRole)).join('\n');
  }

  /// The workflow-context header, or an empty string if nothing is published.
  static String contextHeader(Map<String, dynamic>? ctx) {
    if (ctx == null || ctx.isEmpty) return '';
    final b = StringBuffer('--- Workflow state ---\n');
    void kv(String key, String label) {
      final v = ctx[key];
      if (v != null && '$v'.trim().isNotEmpty) b.writeln('$label: $v');
    }

    kv('lane', 'Lane');
    kv('build', 'Build');
    kv('state', 'State');
    kv('waitingOnOwner', 'Waiting on owner');
    kv('updatedAt', 'Updated');
    // Surface any additional published keys generically (app-agnostic).
    for (final e in ctx.entries) {
      const known = {'lane', 'build', 'state', 'waitingOnOwner', 'updatedAt'};
      if (!known.contains(e.key) && '${e.value}'.trim().isNotEmpty) {
        b.writeln('${e.key}: ${e.value}');
      }
    }
    return b.toString().trimRight();
  }

  /// The FULL paste-ready frame: a short preamble + workflow context (if any) + the
  /// whole thread.
  static String fullFrame({
    required List<ChatItem> items,
    required String projectName,
    required String ownerRole,
    String? build,
    Map<String, dynamic>? context,
  }) {
    final b = StringBuffer();
    b.writeln('=== $projectName owner↔orchestrator context ===');
    if (build != null && build.trim().isNotEmpty) {
      b.writeln('App build: $build');
    }
    b.writeln('Exported: ${DateTime.now().toIso8601String()}');
    final ctx = contextHeader(context);
    if (ctx.isNotEmpty) {
      b.writeln();
      b.writeln(ctx);
    }
    b.writeln();
    b.writeln('--- Conversation (oldest→newest) ---');
    b.writeln(threadBlock(items, ownerRole: ownerRole));
    return b.toString().trimRight();
  }

  /// The RECENT frame: same shape as [fullFrame] but only messages strictly after
  /// [afterMs] (the last-export cursor). Empty-honest when nothing is new.
  static String recentFrame({
    required List<ChatItem> items,
    required int afterMs,
    required String projectName,
    required String ownerRole,
    String? build,
    Map<String, dynamic>? context,
  }) {
    final recent = items.where((m) => m.createdAtMs > afterMs).toList();
    if (recent.isEmpty) {
      return '=== $projectName — no new messages since the last export ===';
    }
    return fullFrame(
      items: recent,
      projectName: projectName,
      ownerRole: ownerRole,
      build: build,
      context: context,
    );
  }
}
