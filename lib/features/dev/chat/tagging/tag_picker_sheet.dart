import 'package:flutter/material.dart';

import '../controllers/chat_tagging_controller.dart';
import '../models/workflow_tag.dart';
import '../services/chat_tag_store.dart';
import 'workflow_lane_registry.dart';

/// Tag picker for the CURRENT multi-selection (HI-11). Reached from the multi-select
/// selection-bar Tag/Label action (no intermediate popup). Tap a conversation label /
/// workflow to apply/remove it across EVERY selected message; `+ New …` creates one
/// (name + colour) and applies it to all. A chip reads "selected" only when ALL selected
/// messages already carry it (set-intersection) — so a SINGLE selected message OR
/// MULTIPLE are handled identically.
///
/// TWO sections:
///  - "Conversation label" (dimension b) — ACTIVE. The owner's own free-form labels.
///  - "Internal workflow" (dimension a) — only rendered when [WorkflowLaneRegistry.enabled]
///    (config gate: lanes.count > 1). INERT / absent on this single-lane port.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — accent passed in; no app identity.
void showTagPickerSheet(
  BuildContext context, {
  required List<String> selectedIds,
  required Color accent,
  required ChatTagStore store,
  required ChatTaggingController tagging,
  required VoidCallback onChanged,
}) {
  final ids = selectedIds;
  if (ids.isEmpty) return;
  // Checked state per DIMENSION = the (kind,id)s EVERY selected message already carries,
  // filtered to that kind, so the two sections never cross-check.
  final selectedLabels = commonTagIds(<Set<String>>[
    for (final id in ids) tagging.tagIdsOfKind(id, 'chatgpt'),
  ]);
  final selectedWorkflow = commonTagIds(<Set<String>>[
    for (final id in ids) tagging.tagIdsOfKind(id, 'workflow'),
  ]);
  final title = ids.length == 1 ? 'Tag this message' : 'Tag ${ids.length} messages';

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1E1E20),
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final labels = store.pickerLabels();
          final workflows = store.pickerWorkflows();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      ids.length == 1
                          ? 'Label which conversation this message belongs to.'
                          : 'Label which conversation all ${ids.length} selected '
                                'messages belong to.',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Conversation label (dimension b, ACTIVE) ──
                            const Text(
                              'Conversation label',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 2, bottom: 8),
                              child: Text(
                                'Your own labels — mark which conversation this '
                                'message is for. The chip stays on the message so '
                                'you can see at a glance which one it belongs to.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (labels.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'No labels yet — create one below.',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final a in labels)
                                    _tagPickerChip(
                                      a,
                                      selectedLabels.contains(a.id),
                                      () async {
                                        if (selectedLabels.contains(a.id)) {
                                          selectedLabels.remove(a.id);
                                          await tagging.removeLabelFromAll(
                                            ids,
                                            a.id,
                                          );
                                        } else {
                                          selectedLabels.add(a.id);
                                          await tagging.applyLabelToAll(
                                            ids,
                                            a.id,
                                            a.label,
                                          );
                                        }
                                        setSheet(() {});
                                      },
                                    ),
                                ],
                              ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => _promptNew(
                                  ctx,
                                  dialogTitle: 'New label',
                                  hint: 'Conversation name (e.g. Blue, Strategy)',
                                  accent: accent,
                                  onCreate: (def) async {
                                    store.addLabel(def);
                                    onChanged();
                                    selectedLabels.add(def.id);
                                    await tagging.applyLabelToAll(
                                      ids,
                                      def.id,
                                      def.label,
                                    );
                                    setSheet(() {});
                                  },
                                ),
                                icon: Icon(Icons.add, color: accent),
                                label: Text(
                                  'New label',
                                  style: TextStyle(color: accent),
                                ),
                              ),
                            ),

                            // ── Internal workflow (dimension a, GATED) ──
                            // Only rendered when the app declares >1 lane
                            // (WorkflowLaneRegistry.enabled). INERT/absent here.
                            if (WorkflowLaneRegistry.enabled) ...[
                              const Divider(color: Colors.white12, height: 20),
                              const Text(
                                'Internal workflow (optional)',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final w in workflows)
                                    _tagPickerChip(
                                      w,
                                      selectedWorkflow.contains(w.id),
                                      () async {
                                        if (selectedWorkflow.contains(w.id)) {
                                          selectedWorkflow.remove(w.id);
                                          await tagging.removeWorkflowFromAll(
                                            ids,
                                            w.id,
                                          );
                                        } else {
                                          selectedWorkflow.add(w.id);
                                          await tagging.applyWorkflowToAll(
                                            ids,
                                            w.id,
                                          );
                                        }
                                        setSheet(() {});
                                      },
                                      secondary: true,
                                    ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => _promptNew(
                                    ctx,
                                    dialogTitle: 'New workflow',
                                    hint: 'Workflow name',
                                    accent: accent,
                                    onCreate: (def) async {
                                      store.upsertWorkflow(def);
                                      onChanged();
                                      selectedWorkflow.add(def.id);
                                      await tagging.applyWorkflowToAll(
                                        ids,
                                        def.id,
                                      );
                                      setSheet(() {});
                                    },
                                  ),
                                  icon: Icon(Icons.add, color: accent),
                                  label: Text(
                                    'New workflow',
                                    style: TextStyle(color: accent),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _tagPickerChip(
  WorkflowDef w,
  bool selected,
  VoidCallback onTap, {
  bool secondary = false,
}) {
  final c = w.color ?? Colors.white24;
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: selected ? 0.35 : (secondary ? 0.08 : 0.12)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: secondary && !selected ? c.withValues(alpha: 0.45) : c,
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            Icon(Icons.check, size: 13, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            w.label,
            style: TextStyle(
              color: secondary ? c.withValues(alpha: 0.7) : c,
              fontSize: secondary ? 11 : 12,
              fontWeight: secondary ? FontWeight.w600 : FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Name it + pick a colour (reusing the palette swatches), then hand back a [WorkflowDef]
/// (stable kebab id). Shared by "+ New label" and "+ New workflow".
Future<void> _promptNew(
  BuildContext context, {
  required String dialogTitle,
  required String hint,
  required Color accent,
  required Future<void> Function(WorkflowDef def) onCreate,
}) async {
  final controller = TextEditingController();
  var chosen = ChatTagPalette.swatches.first;
  final create = await showDialog<bool>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setDialog) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: Text(dialogTitle, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white38),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final c in ChatTagPalette.swatches)
                  GestureDetector(
                    onTap: () => setDialog(() => chosen = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c.toARGB32() == chosen.toARGB32()
                              ? Colors.white
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text('Create', style: TextStyle(color: accent)),
          ),
        ],
      ),
    ),
  );
  if (create != true) return;
  final name = controller.text.trim();
  if (name.isEmpty) return;
  final id = ChatTagPalette.idForLabel(name);
  if (id.isEmpty) return;
  await onCreate(WorkflowDef(id: id, label: name, color: chosen));
}
