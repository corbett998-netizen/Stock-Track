import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_panel.dart';
import '../../../data/models/work_order.dart';
import '../../../data/providers/work_order_providers.dart';

/// "Why" section of the New-Work-Order form: the reason the order exists
/// ([WorkOrderReason] — new install, replace old, warranty, upgrades).
class WhySection extends ConsumerWidget {
  const WhySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = ref.watch(
      workOrderDraftProvider.select((d) => d.reason),
    );

    return SectionPanel(
      title: 'Why',
      icon: Icons.help_outline,
      iconColor: AppColors.inStockGreen,
      children: [
        const SizedBox(height: 4),
        DropdownButtonFormField<WorkOrderReason>(
          initialValue: reason,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          iconEnabledColor: AppColors.textSecondary,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
          ),
          hint: const Text(
            'Select a reason',
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 14,
            ),
          ),
          decoration: InputDecoration(
            labelText: 'Reason',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceAlt,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
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
          ),
          items: [
            for (final r in WorkOrderReason.values)
              DropdownMenuItem<WorkOrderReason>(
                value: r,
                child: Text(
                  r.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (r) =>
              ref.read(workOrderDraftProvider.notifier).setReason(r),
        ),
      ],
    );
  }
}
