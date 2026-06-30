import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/stock_status.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/stock_level_bar.dart';
import '../../data/models/product.dart';
import '../../data/providers/inventory_providers.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(productsProvider);
    final filtered = ref.watch(filteredProductsProvider);
    final lowOnly = ref.watch(inventoryLowFilterProvider);
    final totalCount = all.valueOrNull?.length ?? 0;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Inventory',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '$totalCount products',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _comingSoon(context, 'Add product'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) =>
                            ref.read(inventorySearchProvider.notifier).state = v,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search, color: AppColors.textFaint),
                          hintText: 'Search name, barcode…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _LowFilterChip(
                      active: lowOnly,
                      onTap: () => ref
                          .read(inventoryLowFilterProvider.notifier)
                          .state = !lowOnly,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const _EmptyInventory()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _ProductRow(product: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

void _comingSoon(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — coming in the inventory-CRUD slice.')),
  );
}

class _LowFilterChip extends StatelessWidget {
  const _LowFilterChip({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.lowOrange : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: active
              ? AppColors.lowOrange.withValues(alpha: 0.14)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? AppColors.lowOrange : AppColors.surfaceBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: color),
            const SizedBox(width: 6),
            Text('Low', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final isLow = product.status.isLow;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  product.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(status: product.status),
              const Spacer(),
              _RowActions(product: product),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${product.barcode}   ·   ${product.category}   ·   ${product.location}',
            style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StockLevelBar(
                  quantity: product.quantity,
                  minStock: product.minStock,
                  isLow: isLow,
                ),
              ),
              const SizedBox(width: 12),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${product.quantity} ${product.unit}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: '  / min ${product.minStock}',
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconBtn(context, Icons.autorenew, AppColors.inStockGreen, 'Restock'),
        _iconBtn(context, Icons.edit_outlined, AppColors.textSecondary, 'Edit'),
        _iconBtn(context, Icons.delete_outline, AppColors.lowOrange, 'Delete'),
      ],
    );
  }

  Widget _iconBtn(BuildContext context, IconData icon, Color color, String label) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      iconSize: 18,
      color: color,
      onPressed: () => _comingSoon(context, '$label ${product.name}'),
      icon: Icon(icon),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 40, color: AppColors.textFaint),
            SizedBox(height: 12),
            Text(
              'No products match your search / filter.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
