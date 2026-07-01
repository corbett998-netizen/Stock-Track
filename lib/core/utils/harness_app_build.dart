import 'package:package_info_plus/package_info_plus.dart';

/// Generic, app-agnostic build/version resolver for the harness.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — it reads whatever host app it is
/// compiled into (via `package_info_plus`), so it carries NO project-specific
/// identity. Any app that reuses the harness answers "which build produced this
/// bug / is the owner on the fix?" through this one helper.
///
/// Returns a display string like `1.0.0 (1)` (versionName + build number). On a
/// platform where the plugin channel is unavailable (e.g. a pure widget test), it
/// degrades to `'unknown'` rather than throwing, so a report can always be filed.
Future<String> resolveHarnessAppBuild() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final v = info.version.trim();
    final b = info.buildNumber.trim();
    if (v.isEmpty && b.isEmpty) return 'unknown';
    if (b.isEmpty) return v;
    return '$v ($b)';
  } catch (_) {
    return 'unknown';
  }
}
