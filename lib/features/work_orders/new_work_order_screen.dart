import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/work_order.dart';
import '../../data/providers/work_order_providers.dart';
import 'sections/who_section.dart';
import 'sections/where_section.dart';
import 'sections/what_section.dart';
import 'sections/when_section.dart';
import 'sections/why_section.dart';

/// The New-Work-Order form: the five W's, each its own section panel, all
/// writing into [workOrderDraftProvider]. "Create" stamps createdAt and saves.
class NewWorkOrderScreen extends ConsumerStatefulWidget {
  const NewWorkOrderScreen({super.key});

  @override
  ConsumerState<NewWorkOrderScreen> createState() => _NewWorkOrderScreenState();
}

class _NewWorkOrderScreenState extends ConsumerState<NewWorkOrderScreen> {
  bool _saving = false;

  Future<void> _create() async {
    final draft = ref.read(workOrderDraftProvider);
    if (!draft.isValid) return;
    setState(() => _saving = true);
    final order = WorkOrder(
      id: '',
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
      createdAt: DateTime.now(),
      installDate: draft.installDate,
      scheduleNotes:
          draft.scheduleNotes.trim().isEmpty ? null : draft.scheduleNotes.trim(),
      reason: draft.reason!,
    );
    try {
      await ref.read(workOrderRepositoryProvider).addWorkOrder(order);
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
        title: const Text('New Work Order'),
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
            onPressed: draft.isValid && !_saving ? _create : null,
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
                : const Text('Create Work Order'),
          ),
        ),
      ),
    );
  }
}
