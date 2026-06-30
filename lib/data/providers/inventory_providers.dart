import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/stock_status.dart';
import '../models/product.dart';
import 'repository_providers.dart';

/// Live products stream (from whichever repository is wired in main.dart).
final productsProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchProducts();
});

/// Convenience: the current product list (empty while loading).
final _productListProvider = Provider<List<Product>>((ref) {
  return ref.watch(productsProvider).valueOrNull ?? const [];
});

// ---- Dashboard metrics (derived, no I/O) ----

final productCountProvider = Provider<int>((ref) {
  return ref.watch(_productListProvider).length;
});

final totalUnitsProvider = Provider<int>((ref) {
  return ref.watch(_productListProvider).fold<int>(0, (sum, p) => sum + p.quantity);
});

final lowStockProductsProvider = Provider<List<Product>>((ref) {
  return ref
      .watch(_productListProvider)
      .where((p) => p.status.isLow)
      .toList();
});

// ---- Inventory screen UI state ----

final inventorySearchProvider = StateProvider<String>((ref) => '');
final inventoryLowFilterProvider = StateProvider<bool>((ref) => false);

/// The list actually rendered by the Inventory screen (search + Low filter).
final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(_productListProvider);
  final query = ref.watch(inventorySearchProvider).trim().toLowerCase();
  final lowOnly = ref.watch(inventoryLowFilterProvider);

  return products.where((p) {
    if (lowOnly && !p.status.isLow) return false;
    if (query.isEmpty) return true;
    return p.name.toLowerCase().contains(query) ||
        p.barcode.toLowerCase().contains(query) ||
        p.sku.toLowerCase().contains(query) ||
        p.category.toLowerCase().contains(query);
  }).toList();
});
