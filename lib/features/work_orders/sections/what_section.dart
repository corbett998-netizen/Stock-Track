import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_panel.dart';
import '../../../data/models/product.dart';
import '../../../data/models/work_order.dart';
import '../../../data/providers/inventory_providers.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/providers/work_order_providers.dart';

/// "WHAT" section of the New-Work-Order form — the equipment required,
/// picked from the live inventory database plus a free-text notes field for
/// consumables / special equipment that isn't stocked.
class WhatSection extends ConsumerStatefulWidget {
  const WhatSection({super.key});

  @override
  ConsumerState<WhatSection> createState() => _WhatSectionState();
}

class _WhatSectionState extends ConsumerState<WhatSection> {
  final _searchController = TextEditingController();
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(
      text: ref.read(workOrderDraftProvider).equipmentNotes,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textFaint),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
      );

  List<Product> _matches(List<Product> products, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return products
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q))
        .take(6)
        .toList();
  }

  void _onSuggestionTap(Product product) {
    ref.read(workOrderDraftProvider.notifier).addItem(product);
    _searchController.clear();
    setState(() {});
  }

  bool _quickAdding = false;

  /// Keyboard done/enter commits the typed text: an exact inventory match is
  /// added directly; anything else is auto-saved as a new out-of-stock item.
  Future<void> _onSubmitted(String value) async {
    final name = value.trim();
    if (name.isEmpty) return;
    final products = ref.read(productsProvider).valueOrNull ?? const [];
    final exact = products
        .where((p) => p.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (exact != null) {
      _onSuggestionTap(exact);
    } else {
      await _onQuickAdd(name);
    }
  }

  /// The typed item isn't stocked — save it to inventory at quantity 0 (shows
  /// as "Out of stock" on the Inventory tab so it lands on the order list),
  /// then put it on this work order.
  Future<void> _onQuickAdd(String name) async {
    if (_quickAdding) return;
    setState(() => _quickAdding = true);
    try {
      final saved = await ref.read(inventoryRepositoryProvider).addProduct(
            Product(
              id: 'p_${DateTime.now().microsecondsSinceEpoch}',
              name: name,
              barcode: '',
              sku: '',
              category: 'Uncategorized',
              location: '',
              quantity: 0,
              unit: 'units',
              minStock: 1,
            ),
          );
      ref.read(workOrderDraftProvider.notifier).addItem(saved);
      _searchController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$name" added to inventory as out of stock'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _quickAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(workOrderDraftProvider);
    final notifier = ref.read(workOrderDraftProvider.notifier);
    final products = ref.watch(productsProvider);

    final query = _searchController.text;
    final suggestions = _matches(products.valueOrNull ?? const [], query);
    final addedIds = {for (final i in draft.items) i.productId};

    return SectionPanel(
      title: 'What',
      icon: Icons.hvac_outlined,
      iconColor: AppColors.lowOrange,
      children: [
        // ── Selected equipment ──
        if (draft.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No equipment added yet',
                style: TextStyle(color: AppColors.textFaint, fontSize: 13),
              ),
            ),
          )
        else
          for (final item in draft.items)
            _SelectedItemRow(
              item: item,
              onDecrement: () =>
                  notifier.setItemQuantity(item.productId, item.quantity - 1),
              onIncrement: () =>
                  notifier.setItemQuantity(item.productId, item.quantity + 1),
              onRemove: () => notifier.removeItem(item.productId),
            ),
        const SizedBox(height: 10),

        // ── Inventory search ──
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.done,
          onSubmitted: _onSubmitted,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: _decoration('Type equipment — matches inventory as you type…')
              .copyWith(
            prefixIcon:
                const Icon(Icons.search, size: 20, color: AppColors.textFaint),
            isDense: true,
          ),
        ),
        if (query.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              children: [
                for (final product in suggestions)
                  _SuggestionRow(
                    product: product,
                    alreadyAdded: addedIds.contains(product.id),
                    onTap: addedIds.contains(product.id)
                        ? null
                        : () => _onSuggestionTap(product),
                  ),
                // Nothing stocked matches — done/enter (or a tap here) saves
                // the typed name as a new out-of-stock item.
                if (suggestions.isEmpty)
                  _QuickAddRow(
                    name: query.trim(),
                    busy: _quickAdding,
                    onTap: () => _onQuickAdd(query.trim()),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),

        // ── Consumables / special equipment notes ──
        TextField(
          controller: _notesController,
          onChanged: notifier.setEquipmentNotes,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration:
              _decoration('Consumables & special equipment not listed…'),
        ),
      ],
    );
  }
}

/// One selected-equipment line: name, quantity stepper, remove button.
class _SelectedItemRow extends StatelessWidget {
  const _SelectedItemRow({
    required this.item,
    required this.onDecrement,
    required this.onIncrement,
    required this.onRemove,
  });

  final WorkOrderItem item;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.productName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            onPressed: onDecrement,
            icon: const Icon(Icons.remove, size: 16),
            color: AppColors.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            visualDensity: VisualDensity.compact,
            tooltip: 'Decrease quantity',
          ),
          SizedBox(
            width: 26,
            child: Text(
              '${item.quantity}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onIncrement,
            icon: const Icon(Icons.add, size: 16),
            color: AppColors.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            visualDensity: VisualDensity.compact,
            tooltip: 'Increase quantity',
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
            color: AppColors.textFaint,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

/// Bottom row of the suggestion list: save the typed name as a brand-new
/// inventory item (quantity 0 → "Out of stock") and add it to the order.
class _QuickAddRow extends StatelessWidget {
  const _QuickAddRow({
    required this.name,
    required this.busy,
    required this.onTap,
  });

  final String name;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.add_circle_outline,
                  size: 16, color: AppColors.primaryBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Not in inventory — done adds "$name" as out of stock',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One search-suggestion line: name + on-hand count, check icon if already
/// on the order.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.product,
    required this.alreadyAdded,
    required this.onTap,
  });

  final Product product;
  final bool alreadyAdded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${product.quantity} ${product.unit} on hand',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (alreadyAdded) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check,
                  size: 16, color: AppColors.inStockGreen),
            ],
          ],
        ),
      ),
    );
  }
}
