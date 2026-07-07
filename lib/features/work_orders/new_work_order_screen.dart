import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/customer.dart';
import '../../data/models/work_order.dart';
import '../../data/providers/customer_providers.dart';
import '../../data/providers/work_order_providers.dart';
import 'sections/who_section.dart';
import 'sections/where_section.dart';
import 'sections/what_section.dart';
import 'sections/when_section.dart';
import 'sections/why_section.dart';

/// The work-order form: the five W's, each its own section panel, all writing
/// into [workOrderDraftProvider]. Creates a new order, or — when [existing]
/// is passed — edits it in place (same form, draft seeded from the order).
class NewWorkOrderScreen extends ConsumerStatefulWidget {
  const NewWorkOrderScreen({super.key, this.existing});

  final WorkOrder? existing;

  @override
  ConsumerState<NewWorkOrderScreen> createState() => _NewWorkOrderScreenState();
}

class _NewWorkOrderScreenState extends ConsumerState<NewWorkOrderScreen> {
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final order = widget.existing;
    if (order == null) return;
    // Re-attach the linked customer profile if the stream has it; otherwise
    // reconstruct enough of one that the Where section shows the link and the
    // customerId survives the save.
    Customer? customer;
    if (order.customerId != null) {
      customer = ref
              .read(customersProvider)
              .valueOrNull
              ?.where((c) => c.id == order.customerId)
              .firstOrNull ??
          Customer(
            id: order.customerId!,
            address: order.address,
            name: order.customerName ?? '',
            phone: '',
          );
    }
    ref.read(workOrderDraftProvider.notifier).hydrateFromOrder(
          order,
          customer: customer,
          roster: ref.read(installersProvider),
        );
  }

  Future<void> _save() async {
    final draft = ref.read(workOrderDraftProvider);
    if (!draft.isValid) return;
    setState(() => _saving = true);
    final order = WorkOrder(
      id: widget.existing?.id ?? '',
      installerName: draft.installer!.name,
      installerLicense: draft.installer!.license,
      customerId: draft.customer?.id,
      address: draft.address.trim(),
      customerName:
          draft.customer?.name.isNotEmpty == true ? draft.customer!.name : null,
      items: draft.items,
      equipmentNotes: draft.equipmentNotes.trim().isEmpty
          ? null
          : draft.equipmentNotes.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      installDate: draft.installDate,
      scheduleNotes:
          draft.scheduleNotes.trim().isEmpty ? null : draft.scheduleNotes.trim(),
      reason: draft.reason!,
      quote: widget.existing?.quote,
    );
    try {
      final repo = ref.read(workOrderRepositoryProvider);
      if (_isEdit) {
        await repo.updateWorkOrder(order);
      } else {
        await repo.addWorkOrder(order);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save work order: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(workOrderDraftProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Work Order' : 'New Work Order'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: const [
            WhoSection(),
            SizedBox(height: 12),
            WhereSection(),
            SizedBox(height: 12),
            WhatSection(),
            SizedBox(height: 12),
            WhenSection(),
            SizedBox(height: 12),
            WhySection(),
            SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: draft.isValid && !_saving ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEdit ? 'Save Changes' : 'Create Work Order'),
          ),
        ),
      ),
    );
  }
}
