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
    this.logsInline,
    this.deviceInfo,
    this.appBuild,
    this.awaitingVerification = false,
    this.region,
    this.verifiedByUser = false,
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

  /// Device-log tail captured at submit (logs-first triage). Null/empty on older
  /// reports filed before the logger existed.
  final String? logsInline;

  /// Capture context: `{platform: 'android' | 'iOS' | …}`. Additive/tolerant.
  final Map<String, dynamic>? deviceInfo;

  /// App build/version that produced the report (e.g. `1.0.0 (1)`).
  final String? appBuild;

  /// Dogfood verify loop: an operator "announce build" check-item the owner must
  /// verify (Works / Still-broken). True → shows under "Ready to test".
  final bool awaitingVerification;

  /// Which screen/area to test the check-item on (falls back to [area] / [platform]
  /// when route capture hasn't run). "Which screen was I on" is the fastest signal.
  final String? region;

  /// Set when the owner confirmed a fix via the dogfood "Works" gate.
  final bool verifiedByUser;

  /// The capture platform, if recorded.
  String? get platform => deviceInfo?['platform'] as String?;

  /// The best "test on this screen" label for the ready-to-test checklist.
  String get testOnLabel {
    final r = (region ?? '').trim();
    if (r.isNotEmpty) return r;
    return area.isNotEmpty ? area : 'general';
  }

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

  /// JSON for the durable local store (mock/local path). Writes EVERY field so a
  /// round-trip is lossless — crucially [createdAtMs] (which [fromMap] does NOT read
  /// from the map, so the load path must pass it back explicitly), plus the dogfood
  /// verify fields (awaitingVerification / verifiedByUser) so the ready-to-test loop
  /// survives restart, and the triage state (status / comments / flag / region).
  /// Screenshots are written as the flat `List<String>` that [fromMap] round-trips
  /// (`s is String`). Additive/nullable fields are omitted when empty.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'createdAtMs': createdAtMs,
    'area': area,
    'status': status,
    'note': note,
    'screenshots': screenshots,
    'comments': comments,
    'flaggedForOrchestrator': flaggedForOrchestrator,
    'manualResolved': manualResolved,
    'awaitingVerification': awaitingVerification,
    'verifiedByUser': verifiedByUser,
    if (recommendedFix != null) 'recommendedFix': recommendedFix,
    if (triageDecision != null) 'triageDecision': triageDecision,
    if (logsInline != null) 'logsInline': logsInline,
    if (deviceInfo != null) 'deviceInfo': deviceInfo,
    if (appBuild != null) 'appBuild': appBuild,
    if (region != null) 'region': region,
  };

  /// Build from a plain map (Firestore doc data OR mock state). [createdAtMs] is
  /// pre-resolved by the caller (Firestore Timestamp → millis; mock/store passes it
  /// directly). Screenshots are resolved to a flat list of download URLs.
  static Report fromMap(
    String id,
    Map<String, dynamic> d, {
    required int createdAtMs,
  }) {
    final shotsRaw = d['screenshots'];
    final shots = <String>[];
    if (shotsRaw is List) {
      for (final s in shotsRaw) {
        if (s is Map && s['url'] is String && (s['url'] as String).isNotEmpty) {
          shots.add(s['url'] as String);
        } else if (s is Map &&
            s['localPath'] is String &&
            (s['localPath'] as String).isNotEmpty) {
          // Storage-off / mock capture — a local file path, rendered on-device.
          shots.add(s['localPath'] as String);
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
    final deviceRaw = d['deviceInfo'];
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
      logsInline: d['logsInline'] as String?,
      deviceInfo: deviceRaw is Map
          ? Map<String, dynamic>.from(deviceRaw)
          : null,
      appBuild: d['appBuild'] as String?,
      awaitingVerification: d['awaitingVerification'] == true,
      region: d['region'] as String?,
      verifiedByUser: d['verifiedByUser'] == true,
    );
  }
}
