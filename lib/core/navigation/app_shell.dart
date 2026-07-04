import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/customers/customers_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/scan/scan_screen.dart';
import '../../features/work_orders/work_orders_screen.dart';
import '../theme/app_colors.dart';
import '../utils/current_screen_tracker.dart';
import 'nav_providers.dart';

/// Bottom-nav shell hosting the slice-1 tabs (Dashboard · Inventory · Work Orders ·
/// Customers). Scan is reached via the AppBar action instead of a tab. Tabs live
/// in an [IndexedStack] so each keeps its state (and its live stream subscription)
/// when switching.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _tabs = [
    DashboardScreen(),
    InventoryScreen(),
    WorkOrdersScreen(),
    CustomersScreen(),
  ];

  /// App-layer label map for screen-context capture. ST nav is an [IndexedStack] of
  /// tabs (not Navigator routes), so the shell feeds the current tab label to the
  /// generic [CurrentScreenTracker]; the harness stays app-agnostic.
  static const _tabLabels = <String>[
    'Dashboard',
    'Inventory',
    'Work Orders',
    'Customers',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    // Runs on first build + every tab switch (index is watched). Pure static set —
    // no rebuild side effect. A filed report reads this as its screen-context.
    if (index >= 0 && index < _tabLabels.length) {
      CurrentScreenTracker.update(_tabLabels[index]);
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const _StockTrackBrand(),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScanScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FooterCue(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) =>
                ref.read(selectedTabProvider.notifier).state = i,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: 'Inventory',
              ),
              NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment),
                label: 'Work Orders',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Customers',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The StockTrack brand lockup (blue tile + name + "Warehouse"), as in the refs.
class _StockTrackBrand extends StatelessWidget {
  const _StockTrackBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.warehouse_outlined, size: 20, color: Colors.white),
        ),
        const SizedBox(width: 10),
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'StockTrack',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            Text(
              'Warehouse',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.1),
            ),
          ],
        ),
      ],
    );
  }
}

class _FooterCue extends StatelessWidget {
  const _FooterCue();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: const Text(
        'v1.0  ·  Real-time sync',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textFaint, fontSize: 11),
      ),
    );
  }
}
