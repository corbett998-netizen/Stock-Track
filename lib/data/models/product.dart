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
  });

  final String id;
  final String name;
  final String barcode;
  final String sku;
  final String? serial;

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

  Product copyWith({int? quantity}) => Product(
        id: id,
        name: name,
        barcode: barcode,
        sku: sku,
        serial: serial,
        category: category,
        location: location,
        quantity: quantity ?? this.quantity,
        unit: unit,
        minStock: minStock,
      );
}
