import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_panel.dart';
import '../../../data/models/work_order.dart';
import '../../../data/providers/work_order_providers.dart';

/// "Who" section of the New-Work-Order form: assigns an installer from the
/// roster ([installersProvider]).
///
/// Purely roster-driven — when employee login profiles land and the roster
/// becomes a Firestore-backed stream, this widget needs no change: it only
/// reads the provider's list and writes the selection into the draft.
class WhoSection extends ConsumerWidget {
  const WhoSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installers = ref.watch(installersProvider);
    final draftInstaller = ref.watch(
      workOrderDraftProvider.select((d) => d.installer),
    );

    // Match by license (the stable identifier) rather than trusting reference
    // equality, so the dropdown's value is always one of its own items.
    Installer? selected;
    if (draftInstaller != null) {
      for (final installer in installers) {
        if (installer.license == draftInstaller.license) {
          selected = installer;
          break;
        }
      }
    }

    return SectionPanel(
      title: 'Who',
      icon: Icons.person_outline,
      iconColor: AppColors.primaryBlue,
      children: [
        const SizedBox(height: 4),
        DropdownButtonFormField<Installer>(
          initialValue: selected,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          iconEnabledColor: AppColors.textSecondary,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            labelText: 'Installer',
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
            for (final installer in installers)
              DropdownMenuItem<Installer>(
                value: installer,
                child: Text(
                  installer.displayLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (installer) =>
              ref.read(workOrderDraftProvider.notifier).setInstaller(installer),
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Licence # ${selected.license}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
