import 'package:flutter/material.dart';

import '../models/report_filter.dart';
import 'report_common.dart';

/// The horizontal filter chips over the report queue. Ported from Blueprint's
/// `ReportFilterBar`, trimmed to the Stock-Track filter set.
class ReportFilterBar extends StatelessWidget {
  const ReportFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ReportFilter selected;
  final void Function(ReportFilter) onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          for (final f in ReportFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.label),
                selected: f == selected,
                onSelected: (_) => onSelected(f),
                selectedColor: kReportAccent.withValues(alpha: 0.25),
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(
                  color: f == selected
                      ? kReportAccent
                      : Colors.white.withValues(alpha: 0.12),
                ),
                labelStyle: TextStyle(
                  color: f == selected ? kReportAccent : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
