import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Scan direction. Wrong direction corrupts stock, so the UI makes this an
/// explicit, persistent toggle and always shows the resulting quantity before
/// confirm. Default is the safe, additive direction (stock-in).
enum ScanMode { stockIn, scanOut }

extension ScanModeLabel on ScanMode {
  String get label => this == ScanMode.stockIn ? 'Stock-in' : 'Scan-out';
  int get sign => this == ScanMode.stockIn ? 1 : -1;
}

final scanModeProvider = StateProvider<ScanMode>((ref) => ScanMode.stockIn);
