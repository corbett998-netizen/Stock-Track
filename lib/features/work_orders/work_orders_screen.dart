import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Work Orders tab. Stub for slice 2 — no data wiring yet.
class WorkOrdersScreen extends StatelessWidget {
  const WorkOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'Work Orders',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Coming soon',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Center(
            child: Icon(
              Icons.assignment_outlined,
              size: 48,
              color: AppColors.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}
