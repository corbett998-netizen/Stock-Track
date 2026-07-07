import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/work_order.dart';
import '../../data/providers/work_order_providers.dart';
import 'new_work_order_screen.dart';

/// Work Orders tab — live list of orders (newest first) + "New" FAB.
class WorkOrdersScreen extends ConsumerWidget {
  const WorkOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(workOrdersProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const Text(
              'Work Orders',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ordersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  'Could not load work orders: $e',
                  style: const TextStyle(color: AppColors.lowOrange),
                ),
              ),
              data: (orders) => orders.isEmpty
                  ? const _EmptyState()
                  : Column(
                      children: [
                        for (final o in orders) ...[
                          _WorkOrderCard(order: o),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Work Order'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NewWorkOrderScreen()),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(Icons.assignment_outlined, size: 48, color: AppColors.textFaint),
          SizedBox(height: 12),
          Text(
            'No work orders yet',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({required this.order});

  final WorkOrder order;

  static String _fmtDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Expanded(
                child: Text(
                  order.customerName?.isNotEmpty == true
                      ? order.customerName!
                      : order.address,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  order.reason.label,
                  style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (order.customerName?.isNotEmpty == true) ...[
            const SizedBox(height: 2),
            Text(
              order.address,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${order.installerName} · '
            '${order.installDate != null ? 'Install ${_fmtDate(order.installDate!)}' : 'Not scheduled'}'
            '${order.items.isNotEmpty ? ' · ${order.items.length} item${order.items.length == 1 ? '' : 's'}' : ''}',
            style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
