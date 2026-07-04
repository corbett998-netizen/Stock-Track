import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/product.dart';
import 'inventory_repository.dart';

/// Live Firestore-backed inventory repository.
///
/// Collection: `products` (default Firestore database).
/// Photos: Firebase Storage at `inventory/{id}/photo.jpg`.
class FirebaseInventoryRepository implements InventoryRepository {
  FirebaseInventoryRepository()
      : _col = FirebaseFirestore.instance.collection('products'),
        _storage = FirebaseStorage.instance;

  final CollectionReference<Map<String, dynamic>> _col;
  final FirebaseStorage _storage;

  @override
  Stream<List<Product>> watchProducts() {
    return _col.orderBy('name').snapshots().map(
          (snap) => snap.docs
              .map((d) => Product.fromFirestore(
                    d as DocumentSnapshot<Map<String, dynamic>>,
                  ))
              .toList(),
        );
  }

  @override
  Future<List<Product>> getProducts() async {
    final snap = await _col.orderBy('name').get();
    return snap.docs
        .map((d) => Product.fromFirestore(
              d as DocumentSnapshot<Map<String, dynamic>>,
            ))
        .toList();
  }

  @override
  Future<Product?> findByBarcode(String barcode) async {
    final code = barcode.trim();
    // Try barcode field first, then sku.
    for (final field in ['barcode', 'sku']) {
      final snap =
          await _col.where(field, isEqualTo: code).limit(1).get();
      if (snap.docs.isNotEmpty) {
        return Product.fromFirestore(
          snap.docs.first as DocumentSnapshot<Map<String, dynamic>>,
        );
      }
    }
    return null;
  }

  @override
  Future<Product> adjustQuantity({
    required String productId,
    required int delta,
  }) async {
    final ref = _col.doc(productId);
    late Product updated;
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref as DocumentReference<Map<String, dynamic>>);
      if (!snap.exists) throw StateError('No product with id "$productId"');
      final current = Product.fromFirestore(snap);
      final newQty = (current.quantity + delta).clamp(0, 1 << 30);
      updated = current.copyWith(quantity: newQty);
      tx.update(ref, {'quantity': newQty});
    });
    return updated;
  }

  @override
  Future<Product> addProduct(Product product) async {
    final docRef = product.id.isEmpty ? _col.doc() : _col.doc(product.id);
    final withId = product.copyWith(id: docRef.id);
    await docRef.set(withId.toMap());
    return withId;
  }

  /// Upload a photo file and return the download URL.
  Future<String> uploadPhoto({
    required String productId,
    required File file,
  }) async {
    final ref = _storage.ref('inventory/$productId/photo.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Update an existing product's fields (used after editing).
  Future<void> updateProduct(Product product) async {
    await _col.doc(product.id).set(product.toMap());
  }
}
