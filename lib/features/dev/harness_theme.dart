import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The harness accent seam.
///
/// PORT NOTE (thin-seam #1): Blueprint's harness threaded its brand accent through
/// the dev surfaces via `IntakeCardStyling.primaryOrange` (a BP-only constant). On
/// the Stock-Track port that BP coupling is STRIPPED and replaced by this one
/// project-owned constant, sourced from Stock-Track's own palette
/// ([AppColors.primaryBlue]). Every ported dev surface reads [HarnessTheme.accent]
/// so no BP colour constant survives the copy.
class HarnessTheme {
  const HarnessTheme._();

  /// Stock-Track brand accent for the harness surfaces (was BP's primaryOrange).
  static const Color accent = AppColors.primaryBlue;

  /// Panel background used across the harness surfaces (Stock-Track dark palette).
  static const Color panel = AppColors.surface;
  static const Color background = AppColors.bgDark;
}
