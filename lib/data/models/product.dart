import '../../core/utils/stock_status.dart';

/// A product / inventory item — the source of truth for a SKU's on-hand stock.
///
/// Dumb + immutable. In this slice it is built from the mock repository; a
/// later `Product.fromFirestore(...)` constructor is the only thing a Firebase
/// repository adds (the rest of the app is identical).
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
  });

  final String id;
  final String name;
  final String barcode;
  final String sku;
  final String? serial;
  final String? description;

  /// Category name (e.g. "Electrical"). Kept as a plain name in slice 1; a
  /// Firebase repository would resolve a `categoryId` ref to this name.
  final String category;

  /// Shelf / bin name (e.g. "Shelf C1").
  final String location;

  final int quantity;

  /// "units" / "rolls" / "lengths".
  final String unit;

  final int minStock;

  /// Derived — never stored as a separate hand-set field. Single source.
  StockStatus get status =>
      stockStatusFor(quantity: quantity, minStock: minStock);

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
      );
}
