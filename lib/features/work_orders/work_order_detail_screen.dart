import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/section_panel.dart';
import '../../data/providers/work_order_providers.dart';
import 'new_work_order_screen.dart';
import 'quote_editor_screen.dart';
import 'quote_pdf.dart';

/// Read-only detail view of one work order — the five W's in full — plus the
/// Quote block (build / edit / share). Watches the orders stream so a quote
/// saved in the editor shows up here immediately.
class WorkOrderDetailScreen extends ConsumerWidget {
  const WorkOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  static final _money = NumberFormat.currency(symbol: r'$');
  static String _fmtDate(DateTime d) => DateFormat('MMMM d, y').format(d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(workOrdersProvider);
    final order = ordersAsync.valueOrNull
        ?.where((o) => o.id == orderId)
        .firstOrNull;

    if (order == null) {
      // Deleted elsewhere or still loading.
      return Scaffold(
        appBar: AppBar(title: const Text('Work Order')),
        body: Center(
          child: ordersAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text('Work order not found',
                  style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Order'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit work order',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => NewWorkOrderScreen(existing: order)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            SectionPanel(
              title: 'Who',
              icon: Icons.person_outline,
              iconColor: AppColors.primaryBlue,
              children: [
                _row('Installer', order.installerName),
                _row('Licence #', order.installerLicense),
              ],
            ),
            const SizedBox(height: 12),
            SectionPanel(
              title: 'Where',
              icon: Icons.place_outlined,
              iconColor: AppColors.inStockGreen,
              children: [
                if (order.customerName?.isNotEmpty == true)
                  _row('Customer', order.customerName!),
                _row('Address', order.address),
              ],
            ),
            const SizedBox(height: 12),
            SectionPanel(
              title: 'What',
              icon: Icons.hvac_outlined,
              iconColor: AppColors.lowOrange,
              children: [
                if (order.items.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No equipment listed',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 13)),
                  ),
                for (final i in order.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(i.productName,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 14)),
                        ),
                        Text('×${i.quantity}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                if (order.equipmentNotes?.isNotEmpty == true)
                  _notes(order.equipmentNotes!),
              ],
            ),
            const SizedBox(height: 12),
            SectionPanel(
              title: 'When',
              icon: Icons.event_outlined,
              iconColor: AppColors.primaryBlue,
              children: [
                _row('Created', _fmtDate(order.createdAt)),
                _row(
                    'Install date',
                    order.installDate != null
                        ? _fmtDate(order.installDate!)
                        : 'Not scheduled'),
                if (order.scheduleNotes?.isNotEmpty == true)
                  _notes(order.scheduleNotes!),
              ],
            ),
            const SizedBox(height: 12),
            SectionPanel(
              title: 'Why',
              icon: Icons.help_outline,
              iconColor: AppColors.inStockGreen,
              children: [_row('Job type', order.reason.label)],
            ),
            const SizedBox(height: 12),

            // ── Quote ──
            SectionPanel(
              title: 'Quote',
              icon: Icons.request_quote_outlined,
              iconColor: AppColors.lowOrange,
              children: [
                if (order.quote == null) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No quote yet',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 13)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue),
                      icon: const Icon(Icons.request_quote_outlined, size: 18),
                      label: const Text('Build Quote'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => QuoteEditorScreen(order: order)),
                      ),
                    ),
                  ),
                ] else ...[
                  _row('Lines', '${order.quote!.lines.length}'),
                  _row('Subtotal', _money.format(order.quote!.subtotal)),
                  _row('HST (13%)', _money.format(order.quote!.tax)),
                  _row('Total', _money.format(order.quote!.total), bold: true),
                  _row('Updated', _fmtDate(order.quote!.updatedAt)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(
                                color: AppColors.surfaceBorder),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('Edit'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    QuoteEditorScreen(order: order)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue),
                          icon: const Icon(Icons.ios_share, size: 17),
                          label: const Text('Share PDF'),
                          onPressed: () => shareQuotePdf(order),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _notes(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.35)),
      ),
    );
  }
}
