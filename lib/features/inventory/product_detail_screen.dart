import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/stock_status.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/stock_level_bar.dart';
import '../../data/models/product.dart';
import '../../data/providers/repository_providers.dart';

/// Product detail / create / edit screen.
///
/// - View mode (default): read-only detail rows + Restock / Delete actions.
/// - [isNew]: a blank-ish [product] (e.g. pre-filled with a scanned barcode)
///   is shown as an editable form; Save calls `addProduct`.
/// - [isEditing]: an existing [product] is shown as an editable form; Save
///   only persists the quantity change (via `adjustQuantity`) — the repo has
///   no update-product method yet, so other field edits are local-only.
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    this.isEditing = false,
    this.isNew = false,
  });

  final Product product;
  final bool isEditing;
  final bool isNew;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  late bool _editing = widget.isNew || widget.isEditing;
  late final _nameController = TextEditingController(text: widget.product.name);
  late final _descriptionController =
      TextEditingController(text: widget.product.description ?? '');
  late final _categoryController =
      TextEditingController(text: widget.product.category);
  late final _locationController =
      TextEditingController(text: widget.product.location);
  late final _unitController = TextEditingController(text: widget.product.unit);
  late final _minStockController =
      TextEditingController(text: widget.product.minStock.toString());
  late final _quantityController =
      TextEditingController(text: widget.product.quantity.toString());

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _locationController.dispose();
    _unitController.dispose();
    _minStockController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(inventoryRepositoryProvider);
    final quantity =
        int.tryParse(_quantityController.text.trim()) ?? widget.product.quantity;
    final minStock =
        int.tryParse(_minStockController.text.trim()) ?? widget.product.minStock;
    final description = _descriptionController.text.trim();

    if (widget.isNew) {
      await repo.addProduct(
        widget.product.copyWith(
          id: 'p_${DateTime.now().microsecondsSinceEpoch}',
          name: _nameController.text.trim(),
          description: description.isEmpty ? null : description,
          category: _categoryController.text.trim(),
          location: _locationController.text.trim(),
          unit: _unitController.text.trim(),
          minStock: minStock,
          quantity: quantity,
        ),
      );
    } else {
      final delta = quantity - widget.product.quantity;
      if (delta != 0) {
        await repo.adjustQuantity(productId: widget.product.id, delta: delta);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isLow = widget.product.status.isLow;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Add Product' : widget.product.name),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!widget.isNew && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _editing = true),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_editing) ...[
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
                      StatusBadge(status: widget.product.status),
                      const Spacer(),
                      Text(
                        '${widget.product.quantity} ${widget.product.unit}',
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
                    quantity: widget.product.quantity,
                    minStock: widget.product.minStock,
                    isLow: isLow,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Min stock: ${widget.product.minStock} ${widget.product.unit}',
                    style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (widget.product.description != null &&
                widget.product.description!.isNotEmpty) ...[
              _DetailSection(
                title: 'Description',
                rows: [_DetailRow('', widget.product.description!)],
              ),
              const SizedBox(height: 16),
            ],

            // Details
            _DetailSection(
              title: 'Product Details',
              rows: [
                _DetailRow('Barcode', widget.product.barcode),
                _DetailRow('Category', widget.product.category),
                _DetailRow('Location', widget.product.location),
                _DetailRow('Unit', widget.product.unit),
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
          ] else ...[
            if (widget.isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Barcode: ${widget.product.barcode}',
                  style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
              ),
            _FormField(label: 'Name', controller: _nameController),
            const SizedBox(height: 12),
            _FormField(
              label: 'Description',
              controller: _descriptionController,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            _FormField(label: 'Category', controller: _categoryController),
            const SizedBox(height: 12),
            _FormField(label: 'Location', controller: _locationController),
            const SizedBox(height: 12),
            _FormField(label: 'Unit', controller: _unitController),
            const SizedBox(height: 12),
            _FormField(
              label: 'Min stock',
              controller: _minStockController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _FormField(
              label: 'Quantity',
              controller: _quantityController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                if (!widget.isNew) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _editing = false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.surfaceBorder),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
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
                    if (r.label.isNotEmpty) ...[
                      Text(r.label,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                      const Spacer(),
                    ],
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
