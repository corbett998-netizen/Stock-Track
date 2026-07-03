import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workflow_tag.dart';
import '../tagging/workflow_lane_registry.dart';

/// Device-side registry for chat tags (HI-11) — the owner's free-form conversation
/// LABELS (dimension b) plus optional workflow-lane overrides/ad-hoc lanes (dimension a).
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic: it persists id→(name+colour)
/// records under generic, `harness_`-prefixed [SharedPreferences] keys and hardcodes NO
/// project identity. Mirrors the reference harness idiom (in-memory model, load at open,
/// write-through on mutate). Non-fatal everywhere: any prefs failure degrades to defaults
/// so tagging can never crash the chat.
///
/// The free-form label DIMENSION needs zero config — a label is whatever the owner types,
/// carried on the message; this store just remembers his reusable names + chosen colours
/// so they survive a restart. The workflow DIMENSION seeds from the config lane registry
/// ([WorkflowLaneRegistry]) and is only surfaced when that dimension is enabled.
class ChatTagStore {
  ChatTagStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const String _kLabelsKey = 'harness_chat_tag_labels';
  static const String _kWorkflowsKey = 'harness_chat_tag_workflows';

  SharedPreferences? _prefs;

  /// Owner free-form conversation labels (dimension b), id → def.
  final Map<String, WorkflowDef> _labels = <String, WorkflowDef>{};

  /// Workflow-lane overrides (recolour / rename / ad-hoc), id → def (dimension a).
  final Map<String, WorkflowDef> _workflowOverrides = <String, WorkflowDef>{};

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Warm the in-memory model from prefs. Idempotent; safe to await in `initState`.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      _readInto(p.getString(_kLabelsKey), _labels);
      _readInto(p.getString(_kWorkflowsKey), _workflowOverrides);
    } catch (_) {
      /* non-fatal — defaults */
    }
    _loaded = true;
  }

  static void _readInto(String? raw, Map<String, WorkflowDef> into) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((k, v) {
        if (v is! Map) return;
        final label = v['label']?.toString() ?? k.toString();
        final colorInt = v['color'];
        into[k.toString()] = WorkflowDef(
          id: k.toString(),
          label: label,
          color: colorInt is int ? Color(colorInt) : null,
          archived: v['archived'] == true,
        );
      });
    } catch (_) {
      /* corrupt blob → ignore */
    }
  }

  static Map<String, dynamic> _encode(Map<String, WorkflowDef> m) =>
      <String, dynamic>{
        for (final e in m.entries)
          e.key: <String, dynamic>{
            'label': e.value.label,
            if (e.value.color != null) 'color': e.value.color!.toARGB32(),
            if (e.value.archived) 'archived': true,
          },
      };

  Future<void> _persist(String key, Map<String, WorkflowDef> m) async {
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode(_encode(m)));
    } catch (_) {
      /* non-fatal — in-memory model already updated */
    }
  }

  // ---- Free-form conversation labels (dimension b) --------------------------

  /// The labels shown in the picker's conversation section: EXACTLY the owner's own
  /// persisted free-form labels (no preset taxonomy), sorted by label.
  List<WorkflowDef> pickerLabels() {
    final list = _labels.values.where((a) => !a.archived).toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  }

  /// Register a free-form conversation label (name + colour the owner chose) and PERSIST
  /// so his reused label + colour survive a restart.
  void addLabel(WorkflowDef def) {
    _labels[def.id] = def;
    _persist(_kLabelsKey, _labels);
  }

  /// Resolve a chatgpt-label id → its def. Priority: the owner's persisted label ??
  /// the free-form [carriedLabel] riding on the message element (so a fresh device still
  /// shows his exact label) ?? a raw-id fallback. NO preset seed — labels are entirely
  /// owner-defined.
  WorkflowDef resolveLabel(String id, {String? carriedLabel}) {
    final override = _labels[id];
    if (override != null) return override;
    return WorkflowDef(
      id: id,
      label: (carriedLabel != null && carriedLabel.isNotEmpty)
          ? carriedLabel
          : id,
      color: ChatTagPalette.defaultColorFor('LABEL-$id'.toUpperCase()),
    );
  }

  // ---- Internal workflow lanes (dimension a — gated) ------------------------

  /// The workflow lanes shown in the picker: the config lane set ∪ the owner's overrides,
  /// deduped by id, archived hidden, sorted by label.
  List<WorkflowDef> pickerWorkflows() {
    final byId = <String, WorkflowDef>{
      for (final w in WorkflowLaneRegistry.lanes()) w.id: w,
    };
    byId.addAll(_workflowOverrides);
    final list = byId.values.where((w) => !w.archived).toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  }

  /// Create/update a workflow override (recolour a config lane OR add an ad-hoc one) and
  /// persist. One write → every tagged bubble re-resolves.
  void upsertWorkflow(WorkflowDef def) {
    _workflowOverrides[def.id] = def;
    _persist(_kWorkflowsKey, _workflowOverrides);
  }

  /// Resolve a workflow id → its def (override → config lane → synthetic fallback so an
  /// unknown/ad-hoc id still renders a labelled chip with a deterministic colour).
  WorkflowDef resolveWorkflow(String id) {
    return _workflowOverrides[id] ??
        WorkflowLaneRegistry.lanesById()[id] ??
        WorkflowDef(
          id: id,
          label: id,
          color: ChatTagPalette.defaultColorFor(id.toUpperCase()),
        );
  }

  /// Resolve every tag on a message into its (chatgpt, workflow) chip def lists, split by
  /// dimension. chatgpt chips carry the free-form label (owner override or carried);
  /// workflow chips resolve from the registry. Used by the bubble to render the two chip
  /// rows + the stripe.
  ({List<WorkflowDef> chatgpt, List<WorkflowDef> workflow}) resolveTags(
    Iterable<WorkflowTag> tags,
  ) {
    final chatgpt = <WorkflowDef>[];
    final workflow = <WorkflowDef>[];
    for (final t in tags) {
      if (t.kind == 'chatgpt') {
        chatgpt.add(resolveLabel(t.id, carriedLabel: t.label));
      } else {
        workflow.add(resolveWorkflow(t.id));
      }
    }
    return (chatgpt: chatgpt, workflow: workflow);
  }
}
