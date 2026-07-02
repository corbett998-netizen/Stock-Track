/// Dev-gating for the owner/operator harness (ported from Blueprint Fitness,
/// re-instantiated for Stock-Track / easy-stock-track).
///
/// The harness surfaces (owner↔orchestrator chat, report capture, report queue,
/// command center) are enabled in ALL build modes, including release — the FAB
/// cluster gates on identity instead (see [kOwnerUid]), so only the pinned owner
/// uid ever sees it, regardless of build mode.
const bool kHarnessEnabled = true;

/// The owner's Firebase Auth UID — the harness FAB cluster only renders for this
/// uid (see [HarnessFabCluster]), so enabling the harness in a release build does
/// not surface it to every installer, only to this one signed-in identity.
const String kOwnerUid = 'L7TFQ17wUOcjUZzlQortVza1iFe2';

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

/// Storage gate for attachment UPLOADS (chat images + report screenshots).
///
/// Firebase Storage is deliberately OFF in easy-stock-track for the first backend
/// proof (Brandon hasn't enabled it). While false, the harness NEVER attempts a
/// Storage upload: attachments are staged + rendered LOCALLY (fully usable in mock
/// mode / on-device this session), and firebase-mode surfaces show a clear
/// "Storage off" state instead of crashing. Flip to true the moment Brandon enables
/// Storage in easy-stock-track (the ONLY switch — the upload seam is already wired).
const bool kHarnessStorageEnabled = false;
