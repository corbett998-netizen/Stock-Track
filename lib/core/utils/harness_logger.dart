import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Generic, app-agnostic device logger for the owner/operator harness.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — it hardcodes NO project identity,
/// collection name, or owner value. Any app that reuses the harness gets device
/// logs on its reports by calling [harnessLog]; nothing here is Stock-Track-specific.
///
/// Design (mirrors the reference harness logging pattern):
///  - **Release-gated.** Every write is behind `!kReleaseMode`, so in a real release
///    build the body is dead-code-eliminated and logging is zero-cost.
///  - **A few generic categories** (chat / report / system) — enough to triage,
///    without importing an app's domain vocabulary.
///  - **Bounded ring buffer.** At most [_maxEntries] lines are retained; the oldest
///    fall off. This is the buffer a filed report snapshots as `logsInline`.
///  - **`snapshot(percent)`** returns the most-recent `percent`% of the buffer, and
///    [inlineTail] returns a byte-capped, newline-aligned tail for a report doc.
enum HarnessLogCat { chat, report, system }

class HarnessLogger {
  HarnessLogger._();

  /// The process-wide harness log buffer.
  static final HarnessLogger instance = HarnessLogger._();

  /// Ring-buffer cap. Bounded so the buffer can never grow without limit; a filed
  /// report clips this further to a byte budget via [inlineTail].
  static const int _maxEntries = 600;

  /// Default inline tail budget carried on a report doc (~100 KB).
  static const int defaultInlineBytes = 100 * 1024;

  final ListQueue<String> _buffer = ListQueue<String>();

  /// Master gate — logging is compiled-in for dev/dogfood, inert (and tree-shaken)
  /// in a real release build.
  bool get enabled => !kReleaseMode;

  /// Record one line under [cat]. No-op in release.
  void log(HarnessLogCat cat, String message) {
    if (!enabled) return;
    final line = '${DateTime.now().toIso8601String()} [${cat.name}] $message';
    _buffer.addLast(line);
    while (_buffer.length > _maxEntries) {
      _buffer.removeFirst();
    }
    if (kDebugMode) {
      // Also echo to the console in a debug run; silent in profile/release.
      debugPrint(line);
    }
  }

  // Category convenience wrappers.
  void chat(String message) => log(HarnessLogCat.chat, message);
  void report(String message) => log(HarnessLogCat.report, message);
  void system(String message) => log(HarnessLogCat.system, message);

  /// Number of retained lines.
  int get length => _buffer.length;

  /// The most-recent [percent]% of the buffer (1..100), oldest→newest, as one
  /// newline-joined string. `percent<=0` → empty; `percent>=100` → the whole buffer.
  String snapshot([int percent = 100]) {
    if (_buffer.isEmpty || percent <= 0) return '';
    final p = percent > 100 ? 100 : percent;
    final all = _buffer.toList(growable: false);
    final take = (all.length * p / 100).ceil().clamp(1, all.length);
    return all.sublist(all.length - take).join('\n');
  }

  /// The most-recent slice of the buffer clipped to at most [maxBytes] UTF-8 bytes,
  /// aligned to a newline boundary (drop a partial leading line). This is what a
  /// filed report stores as `logsInline`.
  String inlineTail({int maxBytes = defaultInlineBytes}) {
    final s = snapshot(100);
    if (s.isEmpty) return '';
    final bytes = utf8.encode(s);
    if (bytes.length <= maxBytes) return s;
    final cut = utf8.decode(
      bytes.sublist(bytes.length - maxBytes),
      allowMalformed: true,
    );
    final nl = cut.indexOf('\n');
    return nl >= 0 ? cut.substring(nl + 1) : cut;
  }

  /// Testing/hygiene hook — clear the buffer.
  @visibleForTesting
  void clear() => _buffer.clear();
}

/// Process-wide accessor — `harnessLog.chat('…')`, `harnessLog.report('…')`, etc.
HarnessLogger get harnessLog => HarnessLogger.instance;
