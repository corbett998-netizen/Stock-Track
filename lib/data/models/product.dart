import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/stock_status.dart';

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.sku,
    required this.category,
    required this.location,
    required this.quantity,
    required this.unit,
    required this.minStock,
    this.serial,
    this.description,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String barcode;
  final String sku;
  final String? serial;
  final String? description;
  final String? photoUrl;
  final String category;
  final String location;
  final int quantity;
  final String unit;
  final int minStock;

  StockStatus get status =>
      stockStatusFor(quantity: quantity, minStock: minStock);

  factory Product.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Product(
      id: doc.id,
      name: d['name'] as String? ?? '',
      barcode: d['barcode'] as String? ?? '',
      sku: d['sku'] as String? ?? '',
      serial: d['serial'] as String?,
      description: d['description'] as String?,
      photoUrl: d['photoUrl'] as String?,
      category: d['category'] as String? ?? '',
      location: d['location'] as String? ?? '',
      quantity: (d['quantity'] as num?)?.toInt() ?? 0,
      unit: d['unit'] as String? ?? 'units',
      minStock: (d['minStock'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'barcode': barcode,
        'sku': sku,
        if (serial != null) 'serial': serial,
        if (serial != null) 'serial': serial,
        if (description != null) 'description': description,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'category': category,
        'location': location,
        'quantity': quantity,
        'unit': unit,
        'minStock': minStock,
      };

  Product copyWith({
    String? id,
    String? name,
    String? barcode,
    String? sku,
    String? serial,
    String? category,
    String? location,
    int? quantity,
    String? unit,
    int? minStock,
    String? description,
    String? photoUrl,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        sku: sku ?? this.sku,
        serial: serial ?? this.serial,
        category: category ?? this.category,
        location: location ?? this.location,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        minStock: minStock ?? this.minStock,
        description: description ?? this.description,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}
