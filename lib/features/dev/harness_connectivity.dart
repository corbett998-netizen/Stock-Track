import '../../harness/harness_config.g.dart';
import 'dev_gate.dart';

/// The honest connectivity state of the owner↔orchestrator harness.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — a pure, widget-free, unit-testable
/// resolver so any surface (chat, command center, poke) can render an HONEST signal
/// of what a message/poke will actually do. The port added two states Blueprint
/// never had (a mock/local sandbox, and a "saved but nobody reading" backend), and
/// neither must be presented as a live channel.
enum HarnessConn {
  /// Mock/local mode — nothing is written anywhere an operator could read; messages
  /// and pokes stay on this device.
  localPreview,

  /// Firebase mode, bridge declared OFF — writes land in the backend, but no
  /// operator loop is reading yet, so replies may be delayed.
  backendOnly,

  /// Firebase mode, bridge declared LIVE — an operator loop is polling.
  live,
}

/// Resolve the current connectivity state from the compile-time mode + config.
///
/// mock                    → [HarnessConn.localPreview]
/// firebase + bridge 'live'→ [HarnessConn.live]
/// firebase + bridge else  → [HarnessConn.backendOnly]
HarnessConn resolveHarnessConn() {
  if (kHarnessMode == HarnessMode.mock) return HarnessConn.localPreview;
  return HarnessConfig.orchestratorBridge == 'live'
      ? HarnessConn.live
      : HarnessConn.backendOnly;
}

/// Generic, config-driven banner copy for [conn]. Uses only generic labels
/// ([HarnessConfig.backendLabel]) — never a hardcoded app noun. `live` returns an
/// empty string (the banner renders nothing when connected).
String harnessConnMessage(HarnessConn conn) {
  switch (conn) {
    case HarnessConn.localPreview:
      return 'Local preview — orchestrator not connected. '
          'Your messages and pokes stay on this device.';
    case HarnessConn.backendOnly:
      return 'Saved to ${HarnessConfig.backendLabel}. '
          "Orchestrator isn't reading yet — replies may be delayed.";
    case HarnessConn.live:
      return '';
  }
}

/// A one-line backend descriptor for a compact key/value row (command center),
/// config-driven and mode-aware.
String harnessBackendLine(HarnessConn conn) {
  switch (conn) {
    case HarnessConn.localPreview:
      return 'in-memory · local preview';
    case HarnessConn.backendOnly:
      return '${HarnessConfig.backendLabel} · not reading yet';
    case HarnessConn.live:
      return '${HarnessConfig.backendLabel} · orchestrator connected';
  }
}

/// Whether a poke/message is actually delivered to a place an operator could read.
/// False only in [HarnessConn.localPreview] (stays on-device).
bool get harnessConnDelivers => resolveHarnessConn() != HarnessConn.localPreview;
