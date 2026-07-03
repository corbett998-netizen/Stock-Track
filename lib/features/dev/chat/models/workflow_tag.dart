import 'package:flutter/material.dart';

/// The GENERIC chat message-tagging core (HI-11 — see docs/harness/TAGGING_REVIEW.md).
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic: it hardcodes NO project id,
/// collection name, owner value, or work-lane name. The lane SET flows in from config
/// (`HarnessConfig.laneNamesJson`), never from a literal here. Pure + Firebase-free so
/// the parse / dedup / fingerprint / gate logic is unit-testable without a device.
///
/// Two orthogonal tag DIMENSIONS ride on one additive `tags[]` array per message:
///  - `kind:'chatgpt'` — the owner's FREE-FORM "which external-LLM conversation is this
///    for" LABEL. No taxonomy, no registry: the display [label] + colour ride on the
///    message element itself, so a fresh device reads the exact label with zero config.
///    This is dimension (b) — ACTIVE by default.
///  - `kind:'workflow'` — an INTERNAL work-lane ROUTING tag whose [id] resolves against
///    the config-driven lane registry. This is dimension (a) — STRUCTURALLY GATED behind
///    `lanes.count > 1` (`HarnessConfig.taggingWorkflowEnabled`); INERT on a single-lane
///    port.

/// True when the internal work-lane ROUTING dimension should surface, given how many
/// work-lanes the app declares. GATE: a single-lane app has nothing to route to, so the
/// routing dimension stays inert; it lights up only once a second lane exists. Pure so
/// the gate is directly unit-testable and stays the single source of truth the generated
/// [HarnessConfig.taggingWorkflowEnabled] mirrors.
bool workflowDimensionActive(int laneCount) => laneCount > 1;

/// Out-of-box swatch palette for tag chips. Generic colours — carries NO app identity
/// (an app noun would leak; a hex swatch does not). A new/unseen tag is auto-assigned
/// one deterministically (stable across restarts, before any owner override).
class ChatTagPalette {
  const ChatTagPalette._();

  static const List<Color> swatches = <Color>[
    Color(0xFF4FC3F7), // sky
    Color(0xFF81C784), // green
    Color(0xFFFFB74D), // orange
    Color(0xFFBA68C8), // purple
    Color(0xFFE57373), // red
    Color(0xFF4DB6AC), // teal
    Color(0xFFF06292), // pink
    Color(0xFFAED581), // lime
    Color(0xFF9575CD), // indigo
    Color(0xFFFFD54F), // amber
    Color(0xFF7986CB), // blue-grey
    Color(0xFFA1887F), // brown
  ];

  /// Deterministic default colour for [key] (stable hash → swatch index) so an
  /// un-overridden tag keeps the same colour every launch.
  static Color defaultColorFor(String key) {
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return swatches[h % swatches.length];
  }

  /// Stable lower-kebab id from a free-form display name (collapse non-alnum to a
  /// single `-`, trim edge dashes). `'Blue Strategy'` → `blue-strategy`.
  static String idForLabel(String label) => label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// One STRUCTURED tag carried on a chat message. ADDITIVE + optional — a message with
/// no `tags` renders exactly as the text-only path always did (old docs unaffected).
@immutable
class WorkflowTag {
  const WorkflowTag({
    required this.id,
    this.kind = 'workflow',
    this.label,
    this.addedBy,
    this.addedAtMs,
  });

  /// Stable lower-kebab id. For `workflow` it resolves against the lane registry; for
  /// `chatgpt` it is the id of the owner's free-form label.
  final String id;

  /// Routing DIMENSION: `'workflow'` (internal lane routing) or `'chatgpt'` (owner
  /// free-form conversation label). Absent/empty/`'workflow'` normalises to
  /// `'workflow'`; any OTHER non-empty kind normalises to `'chatgpt'` — zero migration.
  final String kind;

  /// FREE-FORM display label — only set for a `'chatgpt'` tag (the owner's own
  /// conversation name). It rides on the message element so a fresh device + the
  /// operator read the exact label with no registry. Null for workflow tags (whose
  /// label resolves from the registry).
  final String? label;

  /// Who applied the tag (provenance) — the owner-role value for a manual owner tap,
  /// never the auto-classifier. Nullable on old/partial docs.
  final String? addedBy;

  /// When the tag was applied, epoch-ms. Nullable.
  ///
  /// ⚠ PORTABILITY LANDMINE: a Firestore `serverTimestamp()` is ILLEGAL inside an array
  /// element, so the writer stamps a CONCRETE client timestamp
  /// (`DateTime.now().millisecondsSinceEpoch`) — surfaced here as plain millis. Never
  /// put a server timestamp inside a `tags[]` element.
  final int? addedAtMs;

  /// Parse a stored `tags` array into a typed list, DEFENSIVELY: any malformed /
  /// non-map / id-less entry is skipped (never throws), so a bad write can't crash the
  /// render. Returns an empty list for null/absent. `kind` normalises (see [kind]).
  /// Dedup is on the `(kind, id)` PAIR (first wins), so a double-tag can't render two
  /// identical chips while a `workflow x` and a `chatgpt x` still coexist as two chips.
  static List<WorkflowTag> listFrom(Object? raw) {
    if (raw is! List) return const <WorkflowTag>[];
    final out = <WorkflowTag>[];
    final seen = <String>{};
    for (final e in raw) {
      if (e is! Map) continue;
      final id = e['id'];
      if (id is! String || id.isEmpty) continue;
      final rawKind = e['kind'];
      final kind =
          (rawKind is String && rawKind.isNotEmpty && rawKind != 'workflow')
          ? 'chatgpt'
          : 'workflow';
      if (!seen.add('$kind:$id')) continue;
      final rawLabel = e['label'];
      out.add(
        WorkflowTag(
          id: id,
          kind: kind,
          label: (rawLabel is String && rawLabel.isNotEmpty) ? rawLabel : null,
          addedBy: e['addedBy'] as String?,
          addedAtMs: _toMs(e['addedAt']),
        ),
      );
    }
    return out;
  }

  /// Serialise for the durable store. `addedAt` is a plain int (client millis) — the
  /// Firebase writer converts it to a client `Timestamp`, NEVER a `serverTimestamp()`.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'kind': kind,
    if (label != null && label!.isNotEmpty) 'label': label,
    if (addedBy != null) 'addedBy': addedBy,
    if (addedAtMs != null) 'addedAt': addedAtMs,
  };

  /// Coerce a millis-int / num / Firestore-`Timestamp`-like value to epoch-ms WITHOUT
  /// importing cloud_firestore (this module stays Firebase-free + testable). A
  /// `Timestamp` duck-types via `millisecondsSinceEpoch`.
  static int? _toMs(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    try {
      final ms = (v as dynamic)?.millisecondsSinceEpoch;
      if (ms is int) return ms;
    } catch (_) {
      /* not timestamp-like */
    }
    return null;
  }
}

/// A resolved chip definition — what a [WorkflowTag] renders as (label + colour). For a
/// `workflow` tag it comes from the config-driven lane registry; for a `chatgpt` tag it
/// comes from the owner's persisted label (or the free-form label carried on the
/// message). Pure data so a chip renders in a widget test with mock input.
@immutable
class WorkflowDef {
  const WorkflowDef({
    required this.id,
    required this.label,
    this.color,
    this.archived = false,
  });

  final String id;
  final String label;
  final Color? color;

  /// Retired defs hide from the picker but keep their tagged history.
  final bool archived;

  WorkflowDef copyWith({String? label, Color? color, bool? archived}) =>
      WorkflowDef(
        id: id,
        label: label ?? this.label,
        color: color ?? this.color,
        archived: archived ?? this.archived,
      );
}

/// Order-independent fingerprint of a message's tag `(kind:id)`s (sorted, comma-joined).
/// Empty for an untagged message (so untagged docs keep their original id-only render
/// token — zero behaviour change). Folding this into the render signature makes an
/// IN-PLACE tag edit (same message id) flip the signature → exactly one targeted
/// rebuild, no new message, no scroll-yank. Extracted so it is directly unit-testable.
String workflowTagFingerprint(Iterable<WorkflowTag> tags) {
  final keys = <String>[for (final t in tags) '${t.kind}:${t.id}'];
  if (keys.isEmpty) return '';
  keys.sort();
  return keys.join(',');
}

/// The tag ids of [kind] that EVERY selected message already carries — the "checked"
/// state in the multi-select picker. A chip reads checked ONLY when all selected
/// messages have it (set-intersection), so a SINGLE selected message resolves to its own
/// tags and MULTIPLE resolve to their intersection. Empty input → empty. Pure so the
/// "applies to 1 AND many" semantics are unit-testable without a device.
Set<String> commonTagIds(Iterable<Set<String>> perMessageTagIds) {
  Set<String>? common;
  for (final tags in perMessageTagIds) {
    common = common == null ? <String>{...tags} : common.intersection(tags);
  }
  return common ?? <String>{};
}
