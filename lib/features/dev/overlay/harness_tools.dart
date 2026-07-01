import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/screens/orchestrator_chat_screen.dart';
import '../dogfood/ready_to_test_sheet.dart';
import '../harness_connectivity.dart';
import '../harness_home_screen.dart';
import '../report_capture/screens/report_capture_screen.dart';
import '../report_queue/screens/report_queue_screen.dart';
import '../services/harness_providers.dart';
import '../voice/harness_voice_button.dart';
import 'harness_tool_spec.dart';
import 'single_instance_launcher.dart';

/// THE config-driven tool set for the floating dev cluster — the ONLY place the
/// concrete Stock-Track tools are named. The cluster + button + launcher are all
/// generic; adding/removing a tool is a one-line edit here. Every launch goes
/// through the ROOT navigator (via [SingleInstanceLauncher]), never the cluster's
/// own context, because the cluster sits above the Navigator at the builder seam.
///
/// Each tool opens its surface DIRECTLY over the current screen (a full tool as a
/// `fullscreenDialog` route on the root navigator; ready-to-test as a bottom sheet;
/// poke inline) and returns to the exact same screen on close — there is no
/// intermediate command-center page in the path.
final List<HarnessToolSpec> kHarnessTools = <HarnessToolSpec>[
  // MIC — a STATEFUL in-place tool (renders its own widget, no launch). Talk while
  // dogfooding ON the screen being tested: dictation streams into the shared report
  // DRAFT (with the screen frozen at mic-start), then "File a report" hydrates from
  // it. App-owned native recognizer (runs while navigating), NOT a focused-field
  // keyboard mic. Long-press A/Bs the engine (phone vs bundled offline).
  HarnessToolSpec(
    key: 'voice_mic',
    icon: Icons.mic_none, // used only for the semantic label; builder owns render
    label: 'Dictate a report',
    builder: () => const HarnessVoiceButton(bare: true),
  ),

  // Orchestrator chat — exclusive (one dev surface at a time). Badge intentionally
  // omitted: the honest "what needs me" here is UNREAD orchestrator messages, which
  // are not tracked yet; surfacing open-report counts on chat would misread.
  HarnessToolSpec(
    key: 'orchestrator_chat',
    icon: Icons.chat_bubble_outline,
    label: 'Orchestrator chat',
    exclusive: true,
    launch: (rootCtx, uid) {
      SingleInstanceLauncher.pushRoute<void>(
        'orchestrator_chat',
        MaterialPageRoute<void>(
          builder: (_) => OrchestratorChatScreen(uid: uid),
          fullscreenDialog: true,
        ),
        exclusive: true,
        fallbackContext: rootCtx,
      );
    },
  ),

  // Report queue — exclusive. Badge = open (unresolved) reports.
  HarnessToolSpec(
    key: 'report_queue',
    icon: Icons.list_alt,
    label: 'Report queue',
    exclusive: true,
    badgeCount: _openReportsBadge,
    launch: (rootCtx, uid) {
      SingleInstanceLauncher.pushRoute<void>(
        'report_queue',
        MaterialPageRoute<void>(
          builder: (_) => ReportQueueScreen(uid: uid),
          fullscreenDialog: true,
        ),
        exclusive: true,
        fallbackContext: rootCtx,
      );
    },
  ),

  // File a report — not exclusive (capture can sit over anything).
  HarnessToolSpec(
    key: 'report_capture',
    icon: Icons.bug_report_outlined,
    label: 'File a report',
    launch: (rootCtx, uid) {
      SingleInstanceLauncher.pushRoute<void>(
        'report_capture',
        MaterialPageRoute<void>(
          builder: (_) => ReportCaptureScreen(uid: uid),
          fullscreenDialog: true,
        ),
        fallbackContext: rootCtx,
      );
    },
  ),

  // Ready to test — a bottom SHEET over the current screen (opened on the ROOT
  // navigator context, which has the Overlay ancestor the cluster context lacks).
  // Badge = check-items awaiting verification.
  HarnessToolSpec(
    key: 'ready_to_test',
    icon: Icons.fact_check_outlined,
    label: 'Ready to test',
    badgeCount: _readyToTestBadge,
    launch: (rootCtx, uid) {
      SingleInstanceLauncher.guard<void>(
        'ready_to_test',
        () => showReadyToTestSheet(rootCtx, uid: uid),
      );
    },
  ),

  // Poke the orchestrator — inline, NO route. A deliberate low-emphasis utility
  // (muted colour) so it never competes with the core report/mic/chat stack; kept
  // because a manual "check the queue now" nudge is still wanted. Honest per
  // connectivity: in local preview nothing is delivered, so the confirmation says so.
  HarnessToolSpec(
    key: 'poke',
    icon: Icons.notifications_active_outlined,
    label: 'Nudge orchestrator now',
    color: const Color(0xFF5A6472), // muted slate — de-emphasised utility
    launch: (rootCtx, uid) {
      final conn = resolveHarnessConn();
      final container = ProviderScope.containerOf(rootCtx, listen: false);
      unawaited(
        container
            .read(reportRepositoryProvider)
            .pokeOrchestrator(note: 'owner poke')
            .catchError((_) {}),
      );
      ScaffoldMessenger.maybeOf(rootCtx)?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            conn == HarnessConn.localPreview
                ? 'Saved locally — no orchestrator to poke.'
                : 'Poked — the orchestrator will check the queue.',
          ),
        ),
      );
    },
  ),

  // Command center — OPTIONAL home page (still available, but no longer THE entry;
  // the buttons above ARE the menu). Not exclusive, no badge.
  HarnessToolSpec(
    key: 'command_center',
    icon: Icons.dashboard_customize_outlined,
    label: 'Command center',
    launch: (rootCtx, uid) {
      SingleInstanceLauncher.pushRoute<void>(
        'command_center',
        MaterialPageRoute<void>(builder: (_) => const HarnessHomeScreen()),
        fallbackContext: rootCtx,
      );
    },
  ),
];

/// Badge: open (unresolved, non-check-item) reports for [uid].
int _openReportsBadge(WidgetRef ref, String uid) {
  return ref
      .watch(ownerReportsProvider(uid))
      .maybeWhen(
        data: (reports) => reports
            .where(
              (r) =>
                  r.status != 'fixed' &&
                  r.status != 'wont_fix' &&
                  !r.manualResolved,
            )
            .length,
        orElse: () => 0,
      );
}

/// Badge: dogfood check-items awaiting the owner's verify for [uid].
int _readyToTestBadge(WidgetRef ref, String uid) {
  return ref
      .watch(ownerReportsProvider(uid))
      .maybeWhen(
        data: (reports) => reports.where((r) => r.awaitingVerification).length,
        orElse: () => 0,
      );
}
