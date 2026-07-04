import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/stock_status.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/stock_level_bar.dart';
import '../../data/models/product.dart';
import '../../data/providers/inventory_providers.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/firebase_inventory_repository.dart';

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
  XFile? _pickedPhoto;
  bool _photoExpanded = false;

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

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80);
    if (file != null) setState(() => _pickedPhoto = file);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(inventoryRepositoryProvider);
    final fbRepo = repo is FirebaseInventoryRepository ? repo : null;
    final quantity =
        int.tryParse(_quantityController.text.trim()) ?? widget.product.quantity;
    final minStock =
        int.tryParse(_minStockController.text.trim()) ?? widget.product.minStock;
    final description = _descriptionController.text.trim();

    if (widget.isNew) {
      // Generate a doc id first so we can use it for the photo path.
      final tempId = 'p_${DateTime.now().microsecondsSinceEpoch}';
      String? photoUrl;
      if (_pickedPhoto != null && fbRepo != null) {
        photoUrl = await fbRepo.uploadPhoto(
          productId: tempId,
          file: File(_pickedPhoto!.path),
        );
      }
      await repo.addProduct(
        widget.product.copyWith(
          id: tempId,
          name: _nameController.text.trim(),
          description: description.isEmpty ? null : description,
          category: _categoryController.text.trim(),
          location: _locationController.text.trim(),
          unit: _unitController.text.trim(),
          minStock: minStock,
          quantity: quantity,
          photoUrl: photoUrl,
        ),
      );
    } else {
      // Upload new photo if one was picked.
      String? photoUrl = widget.product.photoUrl;
      if (_pickedPhoto != null && fbRepo != null) {
        photoUrl = await fbRepo.uploadPhoto(
          productId: widget.product.id,
          file: File(_pickedPhoto!.path),
        );
      }
      // Persist full updated product.
      final updated = widget.product.copyWith(
        name: _nameController.text.trim(),
        description: description.isEmpty ? null : description,
        category: _categoryController.text.trim(),
        location: _locationController.text.trim(),
        unit: _unitController.text.trim(),
        minStock: minStock,
        quantity: quantity,
        photoUrl: photoUrl,
      );
      if (fbRepo != null) {
        await fbRepo.updateProduct(updated);
      } else {
        final delta = quantity - widget.product.quantity;
        if (delta != 0) {
          await repo.adjustQuantity(
              productId: widget.product.id, delta: delta);
        }
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

            if (widget.product.photoUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  widget.product.photoUrl!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
            ],

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
            // Keyboard dismiss + photo row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => FocusScope.of(context).unfocus(),
                  icon: const Icon(Icons.keyboard_hide, size: 18),
                  label: const Text('Hide keyboard'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _pickPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(
                    _pickedPhoto == null ? 'Add photo' : 'Change photo',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),

            if (_pickedPhoto != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _photoExpanded = !_photoExpanded),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  height: _photoExpanded ? 260 : 90,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_photoExpanded ? 14 : 10),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(_pickedPhoto!.path),
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PhotoChip(
                              icon: _photoExpanded
                                  ? Icons.unfold_less
                                  : Icons.unfold_more,
                              onTap: () => setState(
                                  () => _photoExpanded = !_photoExpanded),
                            ),
                            const SizedBox(width: 6),
                            _PhotoChip(
                              icon: Icons.close,
                              onTap: () => setState(() {
                                _pickedPhoto = null;
                                _photoExpanded = false;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            if (widget.isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Barcode: ${widget.product.barcode}',
                  style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
              ),
            _NameAutocomplete(controller: _nameController),
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
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _editing = false),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
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

// Small overlay chip used on the photo thumbnail for collapse/close actions.
class _PhotoChip extends StatelessWidget {
  const _PhotoChip({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}

// Name field with autocomplete dropdown populated from existing inventory.
class _NameAutocomplete extends ConsumerWidget {
  const _NameAutocomplete({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final existingNames = ref
        .watch(productsProvider)
        .valueOrNull
        ?.map((p) => p.name)
        .toSet()
        .toList() ?? const [];

    return Autocomplete<String>(
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (value) {
        if (value.text.isEmpty) return existingNames;
        return existingNames.where(
          (n) => n.toLowerCase().contains(value.text.toLowerCase()),
        );
      },
      onSelected: (value) => controller.text = value,
      fieldViewBuilder: (ctx, fieldController, focusNode, onSubmitted) {
        // Keep our controller in sync with the autocomplete's internal one.
        fieldController.addListener(() {
          if (controller.text != fieldController.text) {
            controller.text = fieldController.text;
          }
        });
        return TextField(
          controller: fieldController,
          focusNode: focusNode,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Name'),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, i) {
                final name = options.elementAt(i);
                return ListTile(
                  dense: true,
                  title: Text(name,
                      style: const TextStyle(color: AppColors.textPrimary)),
                  onTap: () => onSelected(name),
                );
              },
            ),
          ),
        ),
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
