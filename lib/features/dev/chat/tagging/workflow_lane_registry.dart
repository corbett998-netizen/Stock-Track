import 'dart:convert';

import '../../../../harness/harness_config.g.dart';
import '../models/workflow_tag.dart';

/// The config-driven work-lane registry — dimension (a) STRUCTURE (HI-11).
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK. The lane SET is read from THIS app's own
/// config (`HarnessConfig.laneNamesJson`, sourced from `project.config.json:lanes.names`)
/// — NEVER a hardcoded list and NEVER the reference app's lanes. A port supplies its own
/// lanes in config; this code is identity-free.
///
/// GATING: the whole dimension is inert unless [HarnessConfig.taggingWorkflowEnabled]
/// (derived: `lanes.count > 1`). On this single-lane port the registry still parses (so
/// the structure is present + testable), but the picker never surfaces the workflow
/// section — see [WorkflowLaneRegistry.enabled].
class WorkflowLaneRegistry {
  const WorkflowLaneRegistry._();

  /// Whether the internal work-lane ROUTING dimension is active for this app. Mirrors
  /// the generated gate, which mirrors [workflowDimensionActive] over the lane count —
  /// so a single-lane port can never surface a routing dimension that routes nowhere.
  static bool get enabled => HarnessConfig.taggingWorkflowEnabled;

  /// The app's declared lane set, resolved to renderable [WorkflowDef]s (id + label +
  /// deterministic colour). Derived from the config lane names — id is the kebab of the
  /// name, colour is the deterministic swatch. Defensive: a malformed JSON blob yields
  /// an empty set (never throws). This is the STRUCTURE dimension (a) uses; it exists
  /// even while [enabled] is false so enabling is a config change, not a rebuild.
  static List<WorkflowDef> lanes() {
    final raw = HarnessConfig.laneNamesJson;
    List<dynamic> names;
    try {
      final decoded = jsonDecode(raw);
      names = decoded is List ? decoded : const <dynamic>[];
    } catch (_) {
      return const <WorkflowDef>[];
    }
    final out = <WorkflowDef>[];
    final seen = <String>{};
    for (final n in names) {
      final label = n?.toString() ?? '';
      if (label.isEmpty) continue;
      final id = ChatTagPalette.idForLabel(label);
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(
        WorkflowDef(
          id: id,
          label: label,
          color: ChatTagPalette.defaultColorFor(id.toUpperCase()),
        ),
      );
    }
    return out;
  }

  /// Lane defs keyed by id (read-only lookup for chip resolution).
  static Map<String, WorkflowDef> lanesById() => <String, WorkflowDef>{
    for (final w in lanes()) w.id: w,
  };
}
