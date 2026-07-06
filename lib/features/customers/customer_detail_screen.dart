import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/customer.dart';
import '../../data/providers/customer_providers.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.customer,
    this.isNew = false,
  });

  final Customer customer;
  final bool isNew;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  late bool _editing = widget.isNew;

  late final _nameController =
      TextEditingController(text: widget.customer.name);
  late final _addressController =
      TextEditingController(text: widget.customer.address);
  late final _phoneController =
      TextEditingController(text: widget.customer.phone);
  late final _notesController =
      TextEditingController(text: widget.customer.notes ?? '');

  bool _saving = false;
  final Set<String> _expandedIds = {};

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(customerRepositoryProvider);
    final updated = widget.customer.copyWith(
      name: _nameController.text.trim(),
      address: _addressController.text.trim(),
      phone: _phoneController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    if (widget.isNew) {
      await repo.addCustomer(updated);
    } else {
      await repo.updateCustomer(updated);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _addUnitPhoto(Customer customer) async {
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
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80);
    if (file == null || !mounted) return;

    // Collect equipment details.
    final details = await _showUnitDetailsDialog();
    if (details == null || !mounted) return;

    setState(() => _saving = true);
    final repo = ref.read(customerRepositoryProvider);
    final unitId = 'u_${DateTime.now().microsecondsSinceEpoch}';

    final photoUrl = await repo.uploadUnitPhoto(
      customerId: customer.id,
      unitId: unitId,
      file: File(file.path),
    );

    final newUnit = InstalledUnit(
      id: unitId,
      productName: details['name']!,
      installedAt: DateTime.now(),
      photoUrl: photoUrl,
      serialNumber: details['serial']!.isEmpty ? null : details['serial'],
      barcode: details['barcode']!.isEmpty ? null : details['barcode'],
      category: details['category']!.isEmpty ? null : details['category'],
      warehouseLocation:
          details['location']!.isEmpty ? null : details['location'],
      quantityInstalled:
          int.tryParse(details['qty']!) ?? 1,
      sortOrder: customer.installedUnits.length,
    );

    final updatedUnits = [...customer.installedUnits, newUnit];
    await repo.updateCustomer(customer.copyWith(installedUnits: updatedUnits));
    if (!mounted) return;
    setState(() => _saving = false);
  }

  Future<Map<String, String>?> _showUnitDetailsDialog() async {
    final nameCtrl = TextEditingController();
    final serialCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Equipment details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(label: 'Equipment name *', controller: nameCtrl),
              const SizedBox(height: 10),
              _DialogField(label: 'Serial number', controller: serialCtrl),
              const SizedBox(height: 10),
              _DialogField(label: 'Barcode', controller: barcodeCtrl),
              const SizedBox(height: 10),
              _DialogField(label: 'Category', controller: categoryCtrl),
              const SizedBox(height: 10),
              _DialogField(
                  label: 'Warehouse location', controller: locationCtrl),
              const SizedBox(height: 10),
              _DialogField(
                label: 'Qty installed',
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop({
                'name': nameCtrl.text.trim(),
                'serial': serialCtrl.text.trim(),
                'barcode': barcodeCtrl.text.trim(),
                'category': categoryCtrl.text.trim(),
                'location': locationCtrl.text.trim(),
                'qty': qtyCtrl.text.trim(),
              });
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _reorder(
      Customer customer, int oldIndex, int newIndex) async {
    final units = List<InstalledUnit>.from(customer.installedUnits);
    if (newIndex > oldIndex) newIndex--;
    final item = units.removeAt(oldIndex);
    units.insert(newIndex, item);
    // Re-stamp sortOrder.
    final reindexed = [
      for (var i = 0; i < units.length; i++)
        units[i].copyWith(sortOrder: i),
    ];
    final repo = ref.read(customerRepositoryProvider);
    await repo.updateCustomer(
        customer.copyWith(installedUnits: reindexed));
  }

  @override
  Widget build(BuildContext context) {
    final live = ref
        .watch(customersProvider)
        .valueOrNull
        ?.where((c) => c.id == widget.customer.id)
        .firstOrNull;
    final customer = live ?? widget.customer;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isNew
              ? 'New Customer'
              : (customer.address.isEmpty ? 'Customer' : customer.address),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _editing = true),
            ),
        ],
      ),
      body: _editing
          ? _EditForm(
              nameController: _nameController,
              addressController: _addressController,
              phoneController: _phoneController,
              notesController: _notesController,
              saving: _saving,
              isNew: widget.isNew,
              onSave: _save,
              onCancel: () => setState(() => _editing = false),
            )
          : _DetailView(
              customer: customer,
              saving: _saving,
              onAddUnit: () => _addUnitPhoto(customer),
              onReorder: (o, n) => _reorder(customer, o, n),
              expandedIds: _expandedIds,
              onToggleExpand: (id) => setState(() {
                if (_expandedIds.contains(id)) {
                  _expandedIds.remove(id);
                } else {
                  _expandedIds.add(id);
                }
              }),
            ),
    );
  }
}

// ── Detail view ───────────────────────────────────────────────────────────────

class _DetailView extends StatelessWidget {
  const _DetailView({
    required this.customer,
    required this.saving,
    required this.onAddUnit,
    required this.onReorder,
    required this.expandedIds,
    required this.onToggleExpand,
  });

  final Customer customer;
  final bool saving;
  final VoidCallback onAddUnit;
  final void Function(int, int) onReorder;
  final Set<String> expandedIds;
  final void Function(String id) onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Address heading.
              Text(
                customer.address,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),

              // Name + phone card.
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
                    Text(
                      customer.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (customer.phone.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _PhoneButton(
                              icon: Icons.call_outlined,
                              label: 'Call',
                              color: AppColors.inStockGreen,
                              onTap: () => launchUrl(
                                Uri(scheme: 'tel', path: customer.phone),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PhoneButton(
                              icon: Icons.message_outlined,
                              label: 'Message',
                              color: AppColors.primaryBlue,
                              onTap: () => launchUrl(
                                Uri(scheme: 'sms', path: customer.phone),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        customer.phone,
                        style: const TextStyle(
                            color: AppColors.textFaint, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Equipment header.
              Row(
                children: [
                  const Text(
                    'Installed Equipment',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: saving ? null : onAddUnit,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                    label: const Text('Add photo'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryBlue),
                  ),
                ],
              ),

              if (customer.installedUnits.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No equipment recorded yet.',
                    style:
                        TextStyle(color: AppColors.textFaint, fontSize: 13),
                  ),
                ),
            ]),
          ),
        ),

        // Reorderable equipment list.
        if (customer.installedUnits.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverReorderableList(
              itemCount: customer.installedUnits.length,
              onReorder: onReorder,
              itemBuilder: (context, index) {
                final unit = customer.installedUnits[index];
                return ReorderableDragStartListener(
                  key: ValueKey(unit.id),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _UnitCard(
                      unit: unit,
                      expanded: expandedIds.contains(unit.id),
                      onToggle: () => onToggleExpand(unit.id),
                    ),
                  ),
                );
              },
            ),
          ),

        // Notes section.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const Text(
                'Notes',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 120),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Text(
                  customer.notes?.isNotEmpty == true
                      ? customer.notes!
                      : 'No notes.',
                  style: TextStyle(
                    color: customer.notes?.isNotEmpty == true
                        ? AppColors.textPrimary
                        : AppColors.textFaint,
                    fontSize: 14,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ── Unit card ─────────────────────────────────────────────────────────────────

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.expanded,
    required this.onToggle,
  });

  final InstalledUnit unit;
  final bool expanded;
  final VoidCallback onToggle;

  String _formatDate(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatDate(unit.installedAt);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle + name row.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    unit.productName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.drag_handle,
                    color: AppColors.textFaint, size: 20),
              ],
            ),
          ),

          // Photo.
          if (unit.photoUrl != null)
            GestureDetector(
              onTap: onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                height: expanded ? 280 : 120,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(unit.photoUrl!, fit: BoxFit.cover),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onToggle,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            expanded
                                ? Icons.unfold_less
                                : Icons.unfold_more,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Date — always visible below photo.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text(
              dateLabel,
              style: const TextStyle(
                  color: AppColors.textFaint, fontSize: 12),
            ),
          ),

          // Expanded details.
          if (expanded) ...[
            const Divider(height: 20, indent: 14, endIndent: 14),
            _DetailRow('Qty installed', '${unit.quantityInstalled}'),
            if (unit.serialNumber != null)
              _DetailRow('Serial number', unit.serialNumber!),
            if (unit.barcode != null)
              _DetailRow('Barcode', unit.barcode!),
            if (unit.category != null)
              _DetailRow('Category', unit.category!),
            if (unit.warehouseLocation != null)
              _DetailRow('Warehouse location', unit.warehouseLocation!),
            const SizedBox(height: 10),
          ] else
            const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ── Phone button ──────────────────────────────────────────────────────────────

class _PhoneButton extends StatelessWidget {
  const _PhoneButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ── Edit form ─────────────────────────────────────────────────────────────────

class _EditForm extends StatelessWidget {
  const _EditForm({
    required this.nameController,
    required this.addressController,
    required this.phoneController,
    required this.notesController,
    required this.saving,
    required this.isNew,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController notesController;
  final bool saving;
  final bool isNew;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Field(label: 'Address', controller: addressController),
        const SizedBox(height: 12),
        _Field(label: 'Name', controller: nameController),
        const SizedBox(height: 12),
        _Field(
            label: 'Phone',
            controller: phoneController,
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _Field(label: 'Notes', controller: notesController, maxLines: 5),
        const SizedBox(height: 24),
        Row(
          children: [
            if (!isNew) ...[
              Expanded(
                child: FilledButton(
                  onPressed: saving ? null : onCancel,
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
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
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
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
      ),
    );
  }
}
