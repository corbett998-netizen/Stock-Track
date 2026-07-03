import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../harness/harness_config.g.dart';
import '../../harness_mode_banner.dart';
import '../../harness_theme.dart';
import '../../services/harness_providers.dart';
import '../controllers/chat_compose_controller.dart';
import '../controllers/chat_message_controller.dart';
import '../controllers/chat_tagging_controller.dart';
import '../models/chat_item.dart';
import '../models/workflow_tag.dart';
import '../services/chat_export.dart';
import '../services/chat_tag_store.dart';
import '../tagging/tag_picker_sheet.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_header.dart';
import '../widgets/chat_new_messages_pill.dart';
import '../widgets/chat_selection_bar.dart';
import '../widgets/workflow_dashboard_sheet.dart';

/// The in-app owner↔orchestrator chat screen (harness point 1). Chunk 4 adds the
/// operator surface: per-bubble copy, multi-select + bulk copy, ChatGPT-context
/// export (full / recent-since-last-export), copy-conversation, and a read-only
/// workflow dashboard — the daily "run the build from your phone" controls.
class OrchestratorChatScreen extends ConsumerStatefulWidget {
  const OrchestratorChatScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<OrchestratorChatScreen> createState() =>
      _OrchestratorChatScreenState();
}

class _OrchestratorChatScreenState extends ConsumerState<OrchestratorChatScreen>
    with WidgetsBindingObserver {
  late final ChatMessageController _messages;
  late final ChatComposeController _compose;
  late final ChatTaggingController _tagging;
  final ChatTagStore _tagStore = ChatTagStore();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  final Set<String> _selected = <String>{};
  static const String _prefLastExportMs = 'harness_chat_last_export_ms';
  int _lastExportMs = 0;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages = ChatMessageController(
      repository: ref.read(chatRepositoryProvider),
      notify: _safeNotify,
      isNearBottom: _isNearBottom,
      autoScroll: _autoScroll,
    );
    _compose = ChatComposeController(
      repository: ref.read(chatRepositoryProvider),
      uid: widget.uid,
      controller: _input,
      notify: _safeNotify,
      snack: _snack,
      autoScroll: _autoScroll,
    );
    _tagging = ChatTaggingController(
      repository: ref.read(chatRepositoryProvider),
      uid: widget.uid,
      currentTagsOf: _messages.tagsOf,
      hasDurableDoc: _messages.hasDurableDoc,
      pollOnce: () => _messages.pollOnce(widget.uid),
      snack: _snack,
    );
    _messages.attach(widget.uid);
    _loadExportCursor();
    // Warm the device-side tag registry (owner labels + colours) so the picker shows his
    // reusable labels; a re-render surfaces them once loaded. Non-fatal.
    _tagStore.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Open the tag/label picker for the current multi-selection (HI-11).
  void _openTagPicker() {
    final ids = _orderedSelection.map((m) => m.id).toList();
    if (ids.isEmpty) return;
    showTagPickerSheet(
      context,
      selectedIds: ids,
      accent: HarnessTheme.accent,
      store: _tagStore,
      tagging: _tagging,
      onChanged: _safeNotify,
    );
  }

  /// Whether the Tag/Label affordance surfaces at all — true when EITHER tagging
  /// dimension is enabled by config (labels on by default; workflow gated on lanes>1).
  static final bool _taggingEnabled =
      HarnessConfig.taggingLabelsEnabled || HarnessConfig.taggingWorkflowEnabled;

  Future<void> _loadExportCursor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_prefLastExportMs);
      if (v != null && mounted) setState(() => _lastExportMs = v);
    } catch (_) {}
  }

  Future<void> _saveExportCursor(int ms) async {
    _lastExportMs = ms;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefLastExportMs, ms);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _messages.resume();
    } else if (state == AppLifecycleState.paused) {
      _messages.pauseBackground();
    }
  }

  void _safeNotify() {
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isNearBottom() {
    if (!_scroll.hasClients) return true;
    return _scroll.position.pixels >= _scroll.position.maxScrollExtent - 120;
  }

  /// Re-jump to the bottom across 3 frames so variable-height / image bubbles that
  /// grow after the first layout still land at the true bottom.
  void _autoScroll() {
    var frames = 0;
    void jump() {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      if (++frames < 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) => jump());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => jump());
  }

  // ----- Selection + copy -----
  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _clearSelect() => setState(_selected.clear);

  List<ChatItem> get _orderedSelection =>
      _messages.items.where((m) => _selected.contains(m.id)).toList();

  void _copyOne(ChatItem m) {
    // No snackbar here: the bubble itself gives the copy confirm (fades to gray +
    // a "copied ✓" badge), so a snackbar would be duplicate feedback. Bulk copy
    // and the header context-copies keep their snackbars (no per-bubble confirm).
    Clipboard.setData(
      ClipboardData(
        text: ChatExport.oneBubble(m, ownerRole: HarnessConfig.ownerRole),
      ),
    );
  }

  void _copySelected() {
    final block = ChatExport.threadBlock(
      _orderedSelection,
      ownerRole: HarnessConfig.ownerRole,
    );
    Clipboard.setData(ClipboardData(text: block));
    final n = _selected.length;
    _clearSelect();
    _snack('Copied $n message${n == 1 ? '' : 's'}');
  }

  Future<void> _copyContext(ChatCopyAction action) async {
    final items = _messages.items;
    if (action == ChatCopyAction.thread) {
      Clipboard.setData(
        ClipboardData(
          text: ChatExport.threadBlock(
            items,
            ownerRole: HarnessConfig.ownerRole,
          ),
        ),
      );
      _snack('Conversation copied');
      return;
    }

    // full / recent need the build + published workflow context.
    final build = await ref.read(harnessAppBuildProvider.future);
    Map<String, dynamic>? ctx;
    try {
      ctx = await ref.read(chatRepositoryProvider).readWorkflowContext();
    } catch (_) {
      ctx = null;
    }
    final String text;
    if (action == ChatCopyAction.recent) {
      text = ChatExport.recentFrame(
        items: items,
        afterMs: _lastExportMs,
        projectName: HarnessConfig.projectName,
        ownerRole: HarnessConfig.ownerRole,
        build: build,
        context: ctx,
      );
    } else {
      text = ChatExport.fullFrame(
        items: items,
        projectName: HarnessConfig.projectName,
        ownerRole: HarnessConfig.ownerRole,
        build: build,
        context: ctx,
      );
    }
    Clipboard.setData(ClipboardData(text: text));
    if (items.isNotEmpty) {
      await _saveExportCursor(items.last.createdAtMs);
    }
    if (mounted) {
      _snack(
        action == ChatCopyAction.recent
            ? 'Recent context copied'
            : 'Full context copied',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messages.dispose();
    _compose.dispose();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HarnessTheme.background,
      resizeToAvoidBottomInset: true,
      appBar: _selecting
          ? ChatSelectionBar(
              count: _selected.length,
              onCopy: _copySelected,
              onClear: _clearSelect,
              onTag: _taggingEnabled ? _openTagPicker : null,
              background: HarnessTheme.panel,
              accent: HarnessTheme.accent,
            )
          : AppBar(
              title: const Text('Orchestrator chat'),
              backgroundColor: HarnessTheme.panel,
              actions: [
                ChatHeaderActions(
                  onCopy: _copyContext,
                  onDashboard: () => showWorkflowDashboardSheet(context),
                  accent: HarnessTheme.accent,
                ),
              ],
            ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Honest mode banner — tells the owner whether a message will actually
            // reach an orchestrator (local preview / not-reading-yet / connected).
            const HarnessModeBanner(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _body()),
                  if (_messages.hasUnreadBelow)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      child: Center(
                        child: ChatNewMessagesPill(
                          accent: HarnessTheme.accent,
                          onTap: () {
                            _messages.clearUnread();
                            _autoScroll();
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ChatComposer(
              compose: _compose,
              controller: _input,
              focusNode: _focus,
              accent: HarnessTheme.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_messages.loadError != null && !_messages.loaded) {
      return _errorState(_messages.loadError!);
    }
    if (!_messages.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _messages.items;
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No messages yet.\nSend the first message to the orchestrator.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        // Resolve this message's tags → chip defs (HI-11). The internal-workflow group
        // is suppressed unless that dimension is enabled (gated on lanes>1) so it stays
        // truly inert on this single-lane port.
        final resolved = _tagStore.resolveTags(it.tags);
        return ChatBubble(
          // Bind the bubble's (transient) copied-confirm state to the message id so
          // it follows the correct message when the list grows/reorders.
          key: ValueKey(it.id),
          text: it.text,
          isOwner: it.role == HarnessConfig.ownerRole,
          accent: HarnessTheme.accent,
          imageUrl: it.imageUrl,
          selectionMode: _selecting,
          selected: _selected.contains(it.id),
          chatgptDefs: resolved.chatgpt,
          workflowDefs: HarnessConfig.taggingWorkflowEnabled
              ? resolved.workflow
              : const <WorkflowDef>[],
          onCopy: () => _copyOne(it),
          onLongPress: () => _toggleSelect(it.id),
          onTap: _selecting ? () => _toggleSelect(it.id) : null,
        );
      },
    );
  }

  Widget _errorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Colors.white38, size: 40),
            const SizedBox(height: 12),
            const Text(
              "Couldn't load the chat.",
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
