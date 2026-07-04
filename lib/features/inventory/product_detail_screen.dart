import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/stock_status.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/stock_level_bar.dart';
import '../../data/models/product.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final isLow = product.status.isLow;

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Edit — coming soon')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status + stock level
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(status: product.status),
                    const Spacer(),
                    Text(
                      '${product.quantity} ${product.unit}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StockLevelBar(
                  quantity: product.quantity,
                  minStock: product.minStock,
                  isLow: isLow,
                ),
                const SizedBox(height: 6),
                Text(
                  'Min stock: ${product.minStock} ${product.unit}',
                  style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Details
          _DetailSection(
            title: 'Product Details',
            rows: [
              _DetailRow('Barcode', product.barcode),
              _DetailRow('Category', product.category),
              _DetailRow('Location', product.location),
              _DetailRow('Unit', product.unit),
            ],
          ),
          const SizedBox(height: 24),

          // Actions
          FilledButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Restock — coming soon')),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.inStockGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.autorenew),
            label: const Text('Restock'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Delete — coming soon')),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.lowOrange,
              side: const BorderSide(color: AppColors.lowOrange),
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete product'),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.rows});
  final String title;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(r.label,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    const Spacer(),
                    Text(r.value,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
}
