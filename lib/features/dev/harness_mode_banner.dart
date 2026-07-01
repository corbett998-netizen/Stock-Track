import 'package:flutter/material.dart';

import 'harness_connectivity.dart';

/// The honest MODE BANNER — a compact strip that tells the owner what a message /
/// poke will actually do, so a functional-looking but disconnected channel can never
/// mislead a dogfooder.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic. It reads only the pure
/// [resolveHarnessConn] resolver + config-driven copy; it hardcodes no project noun.
/// Renders an amber strip for [HarnessConn.localPreview] / [HarnessConn.backendOnly]
/// and NOTHING when connected ([HarnessConn.live]) — so it disappears the moment the
/// channel is real. Mount it high on any surface that says "message/poke the
/// orchestrator" (chat body, command center).
class HarnessModeBanner extends StatelessWidget {
  const HarnessModeBanner({super.key, this.accent});

  /// Optional accent (falls back to the harness accent). Amber is used for the
  /// warning states regardless, so this is only a hook for future variants.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final conn = resolveHarnessConn();
    final message = harnessConnMessage(conn);
    if (conn == HarnessConn.live || message.isEmpty) {
      return const SizedBox.shrink();
    }

    const amber = Color(0xFFF59E0B);
    final icon = conn == HarnessConn.localPreview
        ? Icons.cloud_off_outlined
        : Icons.schedule_outlined;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        border: Border(
          bottom: BorderSide(color: amber.withValues(alpha: 0.45)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: amber,
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
