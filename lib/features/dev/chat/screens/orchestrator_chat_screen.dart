import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../harness_theme.dart';
import '../../services/harness_providers.dart';
import '../controllers/chat_compose_controller.dart';
import '../controllers/chat_message_controller.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_composer.dart';

/// The in-app owner↔orchestrator chat screen (harness point 1). Ported from
/// Blueprint's `orchestrator_chat_screen`, trimmed to the Stock-Track slice. Wires
/// the message controller (live listener + foreground poll) and the text composer;
/// the owner UID (anonymous-Auth) is resolved by the caller and passed in.
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
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

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
    );
    _messages.attach(widget.uid);
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

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messages.dispose();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HarnessTheme.background,
      // Keyboard shrinks the body so the composer rides above it (default, set
      // explicitly to document the intent — see HARNESS_PARITY_MAP §7).
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Orchestrator chat'),
        backgroundColor: HarnessTheme.panel,
      ),
      // top:false — the AppBar already consumes the top status-bar inset; only the
      // bottom nav/gesture inset needs padding so the composer clears the Android
      // nav bar (keyboard closed) and sits snug above the keyboard (open, where the
      // bottom SafeArea auto-collapses to 0).
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _body()),
            if (_messages.hasUnreadBelow) _newMessagesPill(),
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
        return ChatBubble(
          text: it.text,
          isOwner: it.role == 'brandon',
          accent: HarnessTheme.accent,
        );
      },
    );
  }

  Widget _newMessagesPill() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TextButton.icon(
        onPressed: () {
          _messages.clearUnread();
          _autoScroll();
        },
        icon: const Icon(Icons.arrow_downward, size: 16),
        label: const Text('New messages'),
        style: TextButton.styleFrom(foregroundColor: HarnessTheme.accent),
      ),
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
