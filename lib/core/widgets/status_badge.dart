import 'package:flutter/material.dart';

import '../utils/stock_status.dart';

/// In-stock (green) / Low-stock (orange) pill. Colour comes from the status —
/// never hardcoded at the call site.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    final filled = status.isLow; // low/out get a solid amber chip, like the refs
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.5)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: filled ? const Color(0xFF1A1206) : color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
