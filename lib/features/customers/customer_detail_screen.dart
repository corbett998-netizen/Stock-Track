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

  Future<void> _saveNotes(String notes) async {
    final repo = ref.read(customerRepositoryProvider);
    final live = ref
            .read(customersProvider)
            .valueOrNull
            ?.where((c) => c.id == widget.customer.id)
            .firstOrNull ??
        widget.customer;
    await repo.updateCustomer(
      live.copyWith(notes: notes.trim().isEmpty ? null : notes.trim()),
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
              customer: customer,
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
              onSaveNotes: _saveNotes,
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
    required this.onSaveNotes,
  });

  final Customer customer;
  final bool saving;
  final VoidCallback onAddUnit;
  final void Function(int, int) onReorder;
  final Set<String> expandedIds;
  final void Function(String id) onToggleExpand;
  final Future<void> Function(String notes) onSaveNotes;

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
              proxyDecorator: (child, index, animation) => Material(
                elevation: 0,
                color: Colors.transparent,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.35),
                    BlendMode.darken,
                  ),
                  child: child,
                ),
              ),
              itemBuilder: (context, index) {
                final unit = customer.installedUnits[index];
                return Padding(
                  key: ValueKey(unit.id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _UnitCard(
                    unit: unit,
                    index: index,
                    expanded: expandedIds.contains(unit.id),
                    onToggle: () => onToggleExpand(unit.id),
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
              _NotesBox(
                customer: customer,
                onSave: onSaveNotes,
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
    required this.index,
    required this.expanded,
    required this.onToggle,
  });

  final InstalledUnit unit;
  final int index;
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
          // Name + drag handle row.
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
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_handle,
                      color: AppColors.textFaint,
                      size: 22,
                    ),
                  ),
                ),
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

// ── Notes box — tap to expand, own edit pencil ───────────────────────────────

class _NotesBox extends StatefulWidget {
  const _NotesBox({required this.customer, required this.onSave});
  final Customer customer;
  final Future<void> Function(String) onSave;

  @override
  State<_NotesBox> createState() => _NotesBoxState();
}

class _NotesBoxState extends State<_NotesBox> {
  bool _expanded = false;
  bool _editing = false;
  bool _saving = false;
  late final _controller =
      TextEditingController(text: widget.customer.notes ?? '');

  @override
  void didUpdateWidget(_NotesBox old) {
    super.didUpdateWidget(old);
    if (!_editing &&
        old.customer.notes != widget.customer.notes) {
      _controller.text = widget.customer.notes ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave(_controller.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasNotes = widget.customer.notes?.isNotEmpty == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row — always visible, tap to expand.
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Text(
                  'Notes',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: AppColors.textFaint,
                ),
                const Spacer(),
                if (_expanded && !_editing)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 18, color: AppColors.textFaint),
                    onPressed: () => setState(() => _editing = true),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Collapsed preview — one line.
        if (!_expanded)
          Text(
            hasNotes ? widget.customer.notes! : 'Tap to add notes…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  hasNotes ? AppColors.textSecondary : AppColors.textFaint,
              fontSize: 13,
            ),
          ),

        // Expanded content.
        if (_expanded)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 120),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: _editing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _controller,
                        maxLines: null,
                        autofocus: true,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        decoration: const InputDecoration.collapsed(
                            hintText: 'Add notes…'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _editing = false),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(40),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(40),
                              ),
                              child:
                                  Text(_saving ? 'Saving…' : 'Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Text(
                    hasNotes ? widget.customer.notes! : 'No notes.',
                    style: TextStyle(
                      color: hasNotes
                          ? AppColors.textPrimary
                          : AppColors.textFaint,
                      fontSize: 14,
                    ),
                  ),
          ),
      ],
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
    required this.customer,
  });

  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController notesController;
  final bool saving;
  final bool isNew;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final Customer customer;

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
        // Same notes widget as detail view — updates the controller so
        // the parent Save picks it up with the rest of the fields.
        _NotesBox(
          customer: customer.copyWith(notes: notesController.text),
          onSave: (text) async => notesController.text = text,
        ),
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
