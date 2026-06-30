import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Horizontal stock-level bar. Blue when healthy, orange when low. The fill is
/// quantity against a "full shelf" reference of ~3× the minimum threshold, so
/// healthy items read near-full and low items read visibly low (matching the
/// reference screenshots).
class StockLevelBar extends StatelessWidget {
  const StockLevelBar({
    super.key,
    required this.quantity,
    required this.minStock,
    required this.isLow,
  });

  final int quantity;
  final int minStock;
  final bool isLow;

  @override
  Widget build(BuildContext context) {
    final reference = (minStock <= 0 ? quantity : minStock * 3).toDouble();
    final fraction =
        reference <= 0 ? 0.0 : (quantity / reference).clamp(0.04, 1.0);
    final color = isLow ? AppColors.lowOrange : AppColors.primaryBlue;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 6,
        backgroundColor: AppColors.surfaceBorder,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
