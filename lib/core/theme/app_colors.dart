import 'package:flutter/material.dart';

/// Dark "warehouse admin" palette, tuned against the StockTrack reference
/// screenshots. Semantic colour decisions (low = orange, in-stock = green,
/// accent = blue) are defined ONCE here and consumed by the shared widgets so
/// no screen hardcodes a colour decision.
class AppColors {
  AppColors._();

  /// App background — deep navy.
  static const Color bgDark = Color(0xFF0A0E1A);

  /// Card / panel background — slightly lifted navy.
  static const Color surface = Color(0xFF111827);

  /// Secondary surface (search fields, chips).
  static const Color surfaceAlt = Color(0xFF0F1626);

  /// Hairline border on cards / panels.
  static const Color surfaceBorder = Color(0xFF1F2A3C);

  /// Brand accent — active nav, links ("View all →"), normal stock bar, ×qty badge.
  static const Color primaryBlue = Color(0xFF3B82F6);

  /// Low-stock / alert — Low badge, low stock bar, LOW STOCK card highlight.
  static const Color lowOrange = Color(0xFFF59E0B);

  /// In-stock badge / healthy stock.
  static const Color inStockGreen = Color(0xFF22C55E);

  /// Headings / values — near white.
  static const Color textPrimary = Color(0xFFF1F5F9);

  /// Sub-labels / captions — muted slate.
  static const Color textSecondary = Color(0xFF94A3B8);

  /// Even fainter text (footnotes, "min N").
  static const Color textFaint = Color(0xFF64748B);
}
