import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A single Dashboard stat card: small caps label, big value, caption, and an
/// icon. [highlight] draws the orange border used by the LOW STOCK card.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        highlight ? AppColors.lowOrange : AppColors.surfaceBorder;
    final iconColor =
        highlight ? AppColors.lowOrange : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: highlight ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Icon(icon, size: 16, color: iconColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: highlight ? AppColors.lowOrange : AppColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
