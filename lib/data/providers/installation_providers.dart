import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/installation.dart';
import 'repository_providers.dart';

/// Live install-records stream.
final installationsProvider = StreamProvider<List<Installation>>((ref) {
  return ref.watch(installationRepositoryProvider).watchInstallations();
});

final _installationListProvider = Provider<List<Installation>>((ref) {
  return ref.watch(installationsProvider).valueOrNull ?? const [];
});

/// Records sorted most-recent-first (Dashboard "Recent Installations").
final recentInstallationsProvider = Provider<List<Installation>>((ref) {
  final records = [...ref.watch(_installationListProvider)];
  records.sort((a, b) => b.installedAt.compareTo(a.installedAt));
  return records;
});

/// Count of installs whose date is today (Dashboard "Installed Today").
final installedTodayCountProvider = Provider<int>((ref) {
  final now = DateTime.now();
  return ref.watch(_installationListProvider).where((r) {
    final d = r.installedAt;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }).length;
});
