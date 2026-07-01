import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// THE durable-local-store seam for the harness — one interface, two impls,
/// mirroring the reference harness idiom (an interface + an in-memory test impl +
/// a durable impl, with the service holding the canonical in-memory model and
/// WRITING THROUGH to the store on every mutation).
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic: it hardcodes NO project
/// id, collection name, or owner value. A "collection" is just a namespaced bucket
/// of id → JSON records; the caller (the mock repositories) decides what goes in it.
/// Identity/namespacing flows in from config via the caller (see lib/main.dart),
/// never from a literal here.
///
/// Why it exists: the mock/local harness path (chat, reports, the queue, and the
/// derived dogfood/ready-to-test state) was pure in-memory, so every app restart
/// reset it to seeds. This seam makes the mock path SURVIVE restart. The
/// Firebase-mode path is untouched (Firestore already persists server-side).
///
/// [loadAll] is SYNCHRONOUS so a mock repository constructor can hydrate itself
/// without an await — the durable impl warms an in-memory cache at boot (mirrors
/// the reference "open the boxes at boot so providers read synchronously" pattern),
/// and every [put]/[delete]/[clear] updates that cache synchronously before the
/// best-effort disk write, so a fresh repository built over the same store instance
/// always sees the latest state (this is exactly how a real restart is simulated in
/// tests via [InMemoryHarnessLocalStore]).
abstract interface class HarnessLocalStore {
  /// All records in [collection] as `id → json map`. Synchronous (cache-backed).
  /// Returns fresh top-level maps so a caller can never mutate the store in place.
  Map<String, Map<String, dynamic>> loadAll(String collection);

  /// Upsert one record. The in-memory view updates synchronously; the durable
  /// write is best-effort (tolerates no-store, e.g. tests / a locked prefs file).
  Future<void> put(String collection, String id, Map<String, dynamic> json);

  /// Remove one record by id (no-op if absent).
  Future<void> delete(String collection, String id);

  /// Drop every record in [collection] (the "reset harness data" affordance).
  Future<void> clear(String collection);
}

/// Generic, well-known collection names for the harness store. Deliberately
/// `harness_`-prefixed so they can never collide with an app-domain store; the
/// caller further namespaces them per-app (see lib/main.dart). Not app nouns.
class HarnessStoreKeys {
  const HarnessStoreKeys._();

  static const String chat = 'harness_chat';
  static const String reports = 'harness_reports';
}

/// In-memory store — the test/default impl (mirrors the reference in-memory store).
///
/// Two uses: (1) a zero-dependency fallback so a mock repository built with no
/// store still works; (2) restart-survival is unit-testable by loading a FRESH
/// mock repository over the SAME store instance (a "restart" without any plugin).
class InMemoryHarnessLocalStore implements HarnessLocalStore {
  final Map<String, Map<String, Map<String, dynamic>>> _data =
      <String, Map<String, Map<String, dynamic>>>{};

  @override
  Map<String, Map<String, dynamic>> loadAll(String collection) {
    final coll = _data[collection];
    if (coll == null) return <String, Map<String, dynamic>>{};
    return <String, Map<String, dynamic>>{
      for (final e in coll.entries) e.key: Map<String, dynamic>.from(e.value),
    };
  }

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> json) async {
    (_data[collection] ??= <String, Map<String, dynamic>>{})[id] =
        Map<String, dynamic>.from(json);
  }

  @override
  Future<void> delete(String collection, String id) async {
    _data[collection]?.remove(id);
  }

  @override
  Future<void> clear(String collection) async {
    _data[collection] = <String, Map<String, dynamic>>{};
  }
}

/// Durable store backed by [SharedPreferences] (already a harness dependency — no
/// new package to add). Each collection is one JSON-encoded `{id: json}` blob under
/// a namespaced key. A tiny dev harness holds only a handful of records, so a
/// per-mutation re-encode of one collection is cheap; a per-record store (e.g. an
/// untyped Hive box) is a drop-in swap behind [HarnessLocalStore] if that ever
/// changes — the seam is what matters, not the backend.
class SharedPrefsHarnessLocalStore implements HarnessLocalStore {
  SharedPrefsHarnessLocalStore._(this._prefs, this._namespace, this._cache);

  final SharedPreferences _prefs;
  final String _namespace;
  final Map<String, Map<String, Map<String, dynamic>>> _cache;

  /// Open the store and WARM the in-memory cache for [collections] so [loadAll] is
  /// synchronous afterwards. Called once at boot (mock mode only). [namespace]
  /// comes from config (per-app) so multi-app installs never collide.
  static Future<SharedPrefsHarnessLocalStore> create({
    required String namespace,
    required List<String> collections,
    SharedPreferences? prefs,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final cache = <String, Map<String, Map<String, dynamic>>>{};
    for (final c in collections) {
      cache[c] = _read(p, _key(namespace, c));
    }
    return SharedPrefsHarnessLocalStore._(p, namespace, cache);
  }

  static String _key(String namespace, String collection) =>
      '$namespace.$collection';

  /// Defensive decode: a stored value is `Map<String, dynamic>`; each record is a
  /// nested `Map` (from jsonDecode). Skip anything that isn't a map so a corrupt /
  /// hand-edited blob can never crash boot.
  static Map<String, Map<String, dynamic>> _read(
    SharedPreferences p,
    String key,
  ) {
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return <String, Map<String, dynamic>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Map<String, dynamic>>{};
      final out = <String, Map<String, dynamic>>{};
      decoded.forEach((k, v) {
        if (v is Map) out[k.toString()] = Map<String, dynamic>.from(v);
      });
      return out;
    } catch (_) {
      return <String, Map<String, dynamic>>{};
    }
  }

  @override
  Map<String, Map<String, dynamic>> loadAll(String collection) {
    final coll = _cache[collection];
    if (coll == null) return <String, Map<String, dynamic>>{};
    return <String, Map<String, dynamic>>{
      for (final e in coll.entries) e.key: Map<String, dynamic>.from(e.value),
    };
  }

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> json) async {
    (_cache[collection] ??= <String, Map<String, dynamic>>{})[id] =
        Map<String, dynamic>.from(json);
    await _persist(collection);
  }

  @override
  Future<void> delete(String collection, String id) async {
    _cache[collection]?.remove(id);
    await _persist(collection);
  }

  @override
  Future<void> clear(String collection) async {
    _cache[collection] = <String, Map<String, dynamic>>{};
    await _persist(collection);
  }

  /// Best-effort flush of one collection — a failed write (locked file, no store)
  /// must never break the in-memory session (the cache is already updated).
  Future<void> _persist(String collection) async {
    try {
      await _prefs.setString(
        _key(_namespace, collection),
        jsonEncode(_cache[collection] ?? <String, Map<String, dynamic>>{}),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('HarnessLocalStore persist failed: $e');
    }
  }
}
