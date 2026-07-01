import 'package:flutter/foundation.dart';

/// Dev-gating for the owner/operator harness (ported from Blueprint Fitness,
/// re-instantiated for Stock-Track / easy-stock-track).
///
/// The harness surfaces (owner↔orchestrator chat, report capture, report queue,
/// command center) are DEV-ONLY: they render only when [kHarnessEnabled] is true.
/// In a release build they are compiled-in but hidden (mirrors BP's `!kReleaseMode`
/// gate). Flip nothing to ship a clean release — the FAB simply never mounts.
const bool kHarnessEnabled = !kReleaseMode;

/// The data-source mode for the harness — the ONE switch (mirrors Stock-Track's
/// inventory Mock↔Firebase seam). `firebase` persists to easy-stock-track (the
/// owner-facing proof, "Rung 1"); `mock` runs the ported surfaces against seeded
/// in-memory data with ZERO backend dependency ("Rung 0" demo).
///
/// Default = firebase so the built APK is the real client-persisted proof. Switch
/// to [HarnessMode.mock] for a zero-dependency demo before Brandon enables the
/// backend. The choice is applied by the provider overrides in `lib/main.dart`.
enum HarnessMode { firebase, mock }

const HarnessMode kHarnessMode = HarnessMode.firebase;
