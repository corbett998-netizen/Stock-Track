import 'dart:async';

import '../models/product.dart';
import 'seed_data.dart';

/// The ONLY boundary the UI uses to read/write inventory. The whole app talks
/// to this interface and never to a concrete data source — so a
/// `FirebaseInventoryRepository implements InventoryRepository` can be swapped
/// in later (one line in main.dart) WITHOUT touching any screen or widget.
abstract interface class InventoryRepository {
  /// Live stream of all products. (Mock: a broadcast of in-memory state.
  /// Firebase: a Firestore `products` snapshot listener.)
  Stream<List<Product>> watchProducts();

  /// One-shot read of the current products.
  Future<List<Product>> getProducts();

  /// Barcode lookup for the Scan flow. Returns null if no product matches.
  Future<Product?> findByBarcode(String barcode);

  /// Apply a stock delta (positive = stock-in / restock, negative = scan-out).
  /// Returns the updated product.
  Future<Product> adjustQuantity({
    required String productId,
    required int delta,
  });
}

/// In-memory mock. Seeded from [kSeedProducts]; backed by a broadcast stream so
/// edits propagate live to every screen (demonstrating the real-time pattern
/// without any cloud). Data resets on app restart.
class MockInventoryRepository implements InventoryRepository {
  MockInventoryRepository() : _products = List.of(kSeedProducts);

  final List<Product> _products;
  final StreamController<List<Product>> _controller =
      StreamController<List<Product>>.broadcast();

  List<Product> get _snapshot => List.unmodifiable(_products);

  @override
  Stream<List<Product>> watchProducts() async* {
    // Emit the current state to a new listener, then forward every update.
    yield _snapshot;
    yield* _controller.stream;
  }

  @override
  Future<List<Product>> getProducts() async => _snapshot;

  @override
  Future<Product?> findByBarcode(String barcode) async {
    final code = barcode.trim();
    for (final p in _products) {
      if (p.barcode == code || p.sku == code) return p;
    }
    return null;
  }

  @override
  Future<Product> adjustQuantity({
    required String productId,
    required int delta,
  }) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) {
      throw StateError('No product with id "$productId"');
    }
    final current = _products[index];
    final newQty = (current.quantity + delta).clamp(0, 1 << 30);
    final updated = current.copyWith(quantity: newQty);
    _products[index] = updated;
    _controller.add(_snapshot);
    return updated;
  }
}
