import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_panel.dart';
import '../../../data/models/customer.dart';
import '../../../data/providers/customer_providers.dart';
import '../../../data/providers/work_order_providers.dart';
import '../../customers/customer_detail_screen.dart';

/// "Where" section of the New-Work-Order form — the job address, tied to the
/// customer database. Typing filters existing customer profiles by address or
/// name; picking one attaches that [Customer] to the draft. Unknown addresses
/// offer a jump into the create-new-customer flow.
class WhereSection extends ConsumerStatefulWidget {
  const WhereSection({super.key});

  @override
  ConsumerState<WhereSection> createState() => _WhereSectionState();
}

class _WhereSectionState extends ConsumerState<WhereSection> {
  late final TextEditingController _addressController = TextEditingController(
    text: ref.read(workOrderDraftProvider).address,
  );

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _selectCustomer(Customer customer) {
    ref.read(workOrderDraftProvider.notifier).selectCustomer(customer);
    // Programmatic controller updates don't fire onChanged, so the selected
    // customer isn't immediately dropped by setAddress.
    _addressController.text = customer.address;
  }

  void _clearSelection() {
    ref.read(workOrderDraftProvider.notifier).setAddress('');
    _addressController.clear();
  }

  Future<void> _createNewCustomer(String typedAddress) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerDetailScreen(
          customer: Customer(
            id: '',
            address: typedAddress,
            name: '',
            phone: '',
          ),
          isNew: true,
        ),
      ),
    );
    if (!mounted) return;

    // If a profile was just saved for the typed address, attach it.
    final saved = ref
        .read(customersProvider)
        .valueOrNull
        ?.where((c) =>
            c.address.trim().toLowerCase() ==
            typedAddress.trim().toLowerCase())
        .firstOrNull;
    if (saved != null) _selectCustomer(saved);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(workOrderDraftProvider);
    final customersAsync = ref.watch(customersProvider);

    final query = _addressController.text.trim().toLowerCase();
    final showSuggestions = draft.customer == null && query.isNotEmpty;

    // Loading → no suggestions yet; error → just skip suggestions.
    final customers = customersAsync.valueOrNull ?? const <Customer>[];
    final matches = showSuggestions
        ? customers
            .where((c) =>
                c.address.toLowerCase().contains(query) ||
                c.name.toLowerCase().contains(query))
            .take(5)
            .toList()
        : const <Customer>[];

    return SectionPanel(
      title: 'Where',
      icon: Icons.place_outlined,
      iconColor: AppColors.inStockGreen,
      children: [
        // TODO(google-places): autocomplete new addresses via Places API once an API key is provisioned.
        TextField(
          controller: _addressController,
          onChanged: (text) {
            ref.read(workOrderDraftProvider.notifier).setAddress(text);
            setState(() {}); // refresh suggestion list against latest text
          },
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Start typing the address…',
            hintStyle:
                const TextStyle(color: AppColors.textFaint, fontSize: 14),
            filled: true,
            fillColor: AppColors.surfaceAlt,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.surfaceBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryBlue),
            ),
          ),
        ),

        // Selected customer confirmation.
        if (draft.customer != null) ...[
          const SizedBox(height: 10),
          _SelectedCustomerRow(
            customer: draft.customer!,
            onClear: _clearSelection,
          ),
        ],

        // Typeahead suggestions.
        if (showSuggestions && matches.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final customer in matches)
            _SuggestionRow(
              customer: customer,
              onTap: () => _selectCustomer(customer),
            ),
        ],

        // No existing profile matches — offer to create one.
        if (showSuggestions &&
            matches.isEmpty &&
            customersAsync.hasValue) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  _createNewCustomer(_addressController.text.trim()),
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('Create new customer profile'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Suggestion row ────────────────────────────────────────────────────────────

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (customer.name.isNotEmpty) customer.name,
      if (customer.phone.isNotEmpty) customer.phone,
    ].join('  ·  ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              customer.address,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Selected customer confirmation row ────────────────────────────────────────

class _SelectedCustomerRow extends StatelessWidget {
  const _SelectedCustomerRow({required this.customer, required this.onClear});

  final Customer customer;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final label = [
      if (customer.name.isNotEmpty) customer.name,
      if (customer.phone.isNotEmpty) customer.phone,
    ].join('  ·  ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.inStockGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.inStockGreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 18, color: AppColors.inStockGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label.isEmpty ? 'Existing customer selected' : label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                size: 18, color: AppColors.textFaint),
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Clear selection',
          ),
        ],
      ),
    );
  }
}
