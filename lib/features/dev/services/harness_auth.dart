import 'package:firebase_auth/firebase_auth.dart';

import '../dev_gate.dart';

/// The owner-identity seam for the harness.
///
/// PORT NOTE (thin-seam #2): Blueprint resolved the owner UID via its own
/// `AuthService.currentUser?.uid`. On the Stock-Track port that BP coupling is
/// STRIPPED. Stock-Track has no login UX, so the harness signs in ANONYMOUSLY —
/// Firebase Auth mints a stable per-install UID that keys the chat thread and the
/// report docs, and scopes the security rules (`request.auth.uid == <owner>`),
/// with no login screen.
///
/// Two impls behind one interface (mirrors Stock-Track's Mock↔Firebase repository
/// seam): [FirebaseHarnessAuth] against easy-stock-track, [MockHarnessAuth] for the
/// zero-dependency demo.
abstract interface class HarnessAuth {
  /// Ensure an owner identity exists and return its UID. Idempotent — a second
  /// call returns the already-signed-in UID.
  Future<String> ensureSignedIn();

  /// The current UID if already signed in, else null.
  String? get currentUid;
}

/// Anonymous Firebase Auth against Brandon's project (easy-stock-track).
class FirebaseHarnessAuth implements HarnessAuth {
  FirebaseHarnessAuth({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  String? get currentUid => _auth.currentUser?.uid;

  @override
  Future<String> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing.uid;
    // Throws FirebaseAuthException(code: 'operation-not-allowed' /
    // 'admin-restricted-operation') until Brandon enables Anonymous Auth in the
    // console — the harness UI surfaces that as an actionable "backend not enabled"
    // state rather than crashing (see HarnessBackendGate).
    final cred = await _auth.signInAnonymously();
    final uid = cred.user?.uid;
    if (uid == null) {
      throw StateError('Anonymous sign-in returned no UID.');
    }
    return uid;
  }
}

/// In-memory owner identity for the Rung-0 mock demo (no Firebase).
class MockHarnessAuth implements HarnessAuth {
  // Mock mode's whole in-memory identity IS the owner, so it's pinned to
  // kOwnerUid — the FAB cluster's owner-uid gate (HarnessFabCluster) matches
  // in mock mode the same way it does in firebase mode.
  static const String _uid = kOwnerUid;

  @override
  String? get currentUid => _uid;

  @override
  Future<String> ensureSignedIn() async => _uid;
}
