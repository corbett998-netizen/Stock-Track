import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/navigation/nav_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/metric_card.dart';
import '../../core/widgets/section_panel.dart';
import '../../core/widgets/stock_level_bar.dart';
import '../../data/models/installation.dart';
import '../../data/models/product.dart';
import '../../data/providers/installation_providers.dart';
import '../../data/providers/inventory_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productCount = ref.watch(productCountProvider);
    final totalUnits = ref.watch(totalUnitsProvider);
    final lowStock = ref.watch(lowStockProductsProvider);
    final installedToday = ref.watch(installedTodayCountProvider);
    final recent = ref.watch(recentInstallationsProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'Warehouse Dashboard',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Real-time stock overview',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // 4 metric cards (2x2 grid on phone).
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              MetricCard(
                label: 'Products',
                value: '$productCount',
                caption: 'SKUs in warehouse',
                icon: Icons.inventory_2_outlined,
              ),
              MetricCard(
                label: 'Total Units',
                value: '$totalUnits',
                caption: 'across all items',
                icon: Icons.widgets_outlined,
              ),
              MetricCard(
                label: 'Low Stock',
                value: '${lowStock.length}',
                caption: 'need reordering',
                icon: Icons.warning_amber_rounded,
                highlight: true,
              ),
              MetricCard(
                label: 'Installed Today',
                value: '$installedToday',
                caption: 'scan-outs today',
                icon: Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Low Stock Alerts panel.
          SectionPanel(
            title: 'Low Stock Alerts',
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.lowOrange,
            onViewAll: () {
              ref.read(inventoryLowFilterProvider.notifier).state = true;
              ref.read(selectedTabProvider.notifier).state = 1;
            },
            children: lowStock.isEmpty
                ? const [_EmptyRow('No low-stock items')]
                : [
                    for (var i = 0; i < lowStock.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      _LowStockRow(product: lowStock[i]),
                    ],
                  ],
          ),
          const SizedBox(height: 14),

          // Recent Installations panel.
          SectionPanel(
            title: 'Recent Installations',
            icon: Icons.assignment_outlined,
            iconColor: AppColors.primaryBlue,
            onViewAll: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Installation History arrives in the next slice.'),
              ),
            ),
            children: recent.isEmpty
                ? const [_EmptyRow('No installations yet')]
                : [
                    for (var i = 0; i < recent.take(5).length; i++) ...[
                      if (i > 0) const Divider(height: 18, color: AppColors.surfaceBorder),
                      _RecentInstallRow(record: recent[i]),
                    ],
                  ],
          ),
        ],
      ),
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.lowOrange),
              ),
              child: Text(
                '${product.quantity} ${product.unit}',
                style: const TextStyle(
                  color: AppColors.lowOrange,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StockLevelBar(
                quantity: product.quantity,
                minStock: product.minStock,
                isLow: true,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'min ${product.minStock}',
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentInstallRow extends StatelessWidget {
  const _RecentInstallRow({required this.record});
  final Installation record;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy-MM-dd').format(record.installedAt);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.productName,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                record.address,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              record.installerName,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              date,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textFaint, fontSize: 13),
      ),
    );
  }
}
