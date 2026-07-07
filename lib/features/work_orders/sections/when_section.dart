import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_panel.dart';
import '../../../data/providers/work_order_providers.dart';

/// "When" section of the New-Work-Order form — created date (display only),
/// install date picker, and scheduling notes.
class WhenSection extends ConsumerStatefulWidget {
  const WhenSection({super.key});

  @override
  ConsumerState<WhenSection> createState() => _WhenSectionState();
}

class _WhenSectionState extends ConsumerState<WhenSection> {
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(
      text: ref.read(workOrderDraftProvider).scheduleNotes,
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  Future<void> _pickInstallDate() async {
    final today = DateTime.now();
    final draft = ref.read(workOrderDraftProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.installDate ?? today,
      firstDate: today.subtract(const Duration(days: 1)),
      lastDate: DateTime(today.year + 2, today.month, today.day),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primaryBlue,
            surface: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      ref.read(workOrderDraftProvider.notifier).setInstallDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(workOrderDraftProvider);
    final installDate = draft.installDate;

    return SectionPanel(
      title: 'When',
      icon: Icons.event_outlined,
      iconColor: AppColors.primaryBlue,
      children: [
        // Row 1 — created date (actual createdAt is stamped at save time).
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const SizedBox(
                width: 110,
                child: Text(
                  'Created',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _formatDate(DateTime.now()),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Row 2 — install date, tappable, with clear button when set.
        InkWell(
          onTap: _pickInstallDate,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 110,
                  child: Text(
                    'Install date',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    installDate != null
                        ? _formatDate(installDate)
                        : 'Not scheduled',
                    style: TextStyle(
                      color: installDate != null
                          ? AppColors.textPrimary
                          : AppColors.textFaint,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (installDate != null)
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
                    tooltip: 'Clear install date',
                    onPressed: () => ref
                        .read(workOrderDraftProvider.notifier)
                        .setInstallDate(null),
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.calendar_month_outlined,
                    size: 20,
                    color: AppColors.primaryBlue,
                  ),
                  tooltip: 'Pick install date',
                  onPressed: _pickInstallDate,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Scheduling notes.
        TextField(
          controller: _notesController,
          maxLines: 3,
          onChanged: (value) =>
              ref.read(workOrderDraftProvider.notifier).setScheduleNotes(value),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Special requests, site access, gate codes…',
            hintStyle:
                const TextStyle(color: AppColors.textFaint, fontSize: 13),
            filled: true,
            fillColor: AppColors.surfaceAlt,
            contentPadding: const EdgeInsets.all(12),
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
        ),
      ],
    );
  }
}
