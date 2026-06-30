import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A titled panel with an icon and an optional "View all →" action — the
/// Dashboard's Low-Stock-Alerts and Recent-Installations containers.
class SectionPanel extends StatelessWidget {
  const SectionPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
    this.onViewAll,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onViewAll != null)
                  TextButton(
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View all  →', style: TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.surfaceBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
