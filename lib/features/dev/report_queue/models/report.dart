/// Report model — a thin read view over a `stockIssueReports` doc. Ported from
/// Blueprint's `Report`, trimmed to the Stock-Track slice and made backend-agnostic
/// ([fromMap] takes a plain map + id) so the Firebase and Mock repositories build
/// it identically. Tolerant of missing additive fields (older reports simply lack
/// title/recommendedFix/etc.).
class Report {
  Report({
    required this.id,
    required this.createdAtMs,
    required this.area,
    required this.status,
    required this.note,
    required this.screenshots,
    required this.comments,
    required this.flaggedForOrchestrator,
    required this.manualResolved,
    required this.recommendedFix,
    required this.triageDecision,
  });

  final String id;
  final int createdAtMs;
  final String area;
  final String status;
  final String note;
  final List<String> screenshots; // download urls
  final List<Map<String, dynamic>> comments;
  final bool flaggedForOrchestrator;
  final bool manualResolved;

  /// Owner-triage system ("nothing sits at 'new'"): the orchestrator writes a
  /// one-line recommended fix. Empty → the row shows "Awaiting recommendation…".
  final String? recommendedFix;

  /// Owner's per-row triage call — `'execute'` or `'discuss'`; null = undecided.
  final String? triageDecision;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  String get displayRecommendation => (recommendedFix ?? '').trim();

  String get displayTitle {
    final raw = _firstLine(note);
    return raw.isNotEmpty ? _clip(raw) : '(no note)';
  }

  /// Status shown on the chip. A manual-resolved tick reads as 'fixed'.
  String get effectiveStatus =>
      (manualResolved && status != 'fixed' && status != 'wont_fix')
          ? 'fixed'
          : status;

  static String _firstLine(String s) => s
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');

  static String _clip(String s, [int max = 80]) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  /// Build from a plain map (Firestore doc data OR mock state). [createdAtMs] is
  /// pre-resolved by the caller (Firestore Timestamp → millis; mock passes it
  /// directly). Screenshots are resolved to a flat list of download URLs.
  static Report fromMap(String id, Map<String, dynamic> d, {required int createdAtMs}) {
    final shotsRaw = d['screenshots'];
    final shots = <String>[];
    if (shotsRaw is List) {
      for (final s in shotsRaw) {
        if (s is Map && s['url'] is String && (s['url'] as String).isNotEmpty) {
          shots.add(s['url'] as String);
        } else if (s is String && s.isNotEmpty) {
          shots.add(s);
        }
      }
    }
    final commentsRaw = d['comments'];
    final comments = <Map<String, dynamic>>[];
    if (commentsRaw is List) {
      for (final c in commentsRaw) {
        if (c is Map) comments.add(Map<String, dynamic>.from(c));
      }
    }
    return Report(
      id: id,
      createdAtMs: createdAtMs,
      area: (d['area'] as String?)?.trim().isNotEmpty == true
          ? (d['area'] as String).trim()
          : 'general',
      status: (d['status'] as String?) ?? 'new',
      note: (d['note'] as String?) ?? '',
      screenshots: shots,
      comments: comments,
      flaggedForOrchestrator: d['flaggedForOrchestrator'] == true,
      manualResolved: d['manualResolved'] == true,
      recommendedFix: d['recommendedFix'] as String?,
      triageDecision: d['triageDecision'] as String?,
    );
  }
}
