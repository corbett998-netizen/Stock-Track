import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The single source of truth for stock status. Quantity vs the minimum
/// threshold decides whether an item is healthy, low, or out — and every
/// badge, the Low filter, and the Dashboard low-stock count derive from THIS
/// function so they can never drift.
enum StockStatus { inStock, low, out }

StockStatus stockStatusFor({required int quantity, required int minStock}) {
  if (quantity <= 0) return StockStatus.out;
  if (quantity <= minStock) return StockStatus.low;
  return StockStatus.inStock;
}

extension StockStatusDisplay on StockStatus {
  bool get isLow => this == StockStatus.low || this == StockStatus.out;

  String get label => switch (this) {
        StockStatus.inStock => 'In stock',
        StockStatus.low => 'Low stock',
        StockStatus.out => 'Out of stock',
      };

  /// Semantic colour for this status (green / orange). Defined once.
  Color get color => switch (this) {
        StockStatus.inStock => AppColors.inStockGreen,
        StockStatus.low => AppColors.lowOrange,
        StockStatus.out => AppColors.lowOrange,
      };
}
