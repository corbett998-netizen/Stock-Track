import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Customers tab. Stub for slice 2 — no data wiring yet.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'Customers',
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
              Icons.people_outline,
              size: 48,
              color: AppColors.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}
