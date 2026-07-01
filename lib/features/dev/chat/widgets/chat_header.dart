import 'package:flutter/material.dart';

/// The chat AppBar command buttons — the operator's "run the build from your phone"
/// controls: copy a paste-ready context (full / recent), copy the raw conversation,
/// and open the workflow dashboard.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic; callbacks + accent passed
/// in. A single widget so it drops straight into `AppBar(actions: [ChatHeaderActions])`.
enum ChatCopyAction { fullContext, recent, thread }

class ChatHeaderActions extends StatelessWidget {
  const ChatHeaderActions({
    super.key,
    required this.onCopy,
    required this.onDashboard,
    required this.accent,
  });

  final void Function(ChatCopyAction action) onCopy;
  final VoidCallback onDashboard;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.dashboard_outlined),
          tooltip: 'Workflow dashboard',
          onPressed: onDashboard,
        ),
        PopupMenuButton<ChatCopyAction>(
          icon: const Icon(Icons.copy_all_outlined),
          tooltip: 'Copy context for ChatGPT',
          onSelected: onCopy,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: ChatCopyAction.fullContext,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.file_copy_outlined),
                title: Text('Copy FULL context'),
                subtitle: Text('Workflow state + whole thread'),
              ),
            ),
            PopupMenuItem(
              value: ChatCopyAction.recent,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history),
                title: Text('Copy RECENT'),
                subtitle: Text('Only since the last export'),
              ),
            ),
            PopupMenuItem(
              value: ChatCopyAction.thread,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.forum_outlined),
                title: Text('Copy conversation'),
                subtitle: Text('Raw thread, no preamble'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
