import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected bottom-nav tab (0 = Dashboard, 1 = Inventory, 2 = Scan). Held in a
/// provider so a deep action (e.g. the Dashboard "View all →" on low stock) can
/// switch tabs.
final selectedTabProvider = StateProvider<int>((ref) => 0);
