import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/stock_status.dart';

/// Where a physically-scanned unit currently stands.
enum SerialStatus {
  /// Sitting in the warehouse, part of the aggregate [Product.quantity].
  warehouse,

  /// Attached to a work order (see [SerialRecord.workOrderId]) — out for a
  /// job but not yet confirmed installed.
  onWorkOrder,

  /// Confirmed installed. A standalone status, not tied to any specific
  /// work order.
  installed;

  static SerialStatus fromName(String? name) {
    for (final s in SerialStatus.values) {
      if (s.name == name) return s;
    }
    return SerialStatus.warehouse;
  }
}

/// One physically-scanned unit logged against a catalog item, and where it
/// currently stands (still in the warehouse, out on a work order, or
/// installed).
class SerialRecord {
  const SerialRecord({
    required this.serial,
    this.status = SerialStatus.warehouse,
    this.workOrderId,
    this.workOrderLabel,
  });

  final String serial;
  final SerialStatus status;

  /// Set when [status] is [SerialStatus.onWorkOrder].
  final String? workOrderId;

  /// Denormalized work order address/customer, for display without a join.
  final String? workOrderLabel;

  factory SerialRecord.fromMap(Map<String, dynamic> m) => SerialRecord(
    serial: m['serial'] as String? ?? '',
    status: SerialStatus.fromName(m['status'] as String?),
    workOrderId: m['workOrderId'] as String?,
    workOrderLabel: m['workOrderLabel'] as String?,
  );

  /// Accepts either the current map shape or a legacy bare string — serials
  /// were stored as plain strings before per-unit status existed, and old
  /// Firestore docs still have them that way.
  factory SerialRecord.fromDynamic(dynamic v) {
    if (v is String) return SerialRecord(serial: v);
    if (v is Map) return SerialRecord.fromMap(Map<String, dynamic>.from(v));
    return const SerialRecord(serial: '');
  }

  Map<String, dynamic> toMap() => {
    'serial': serial,
    'status': status.name,
    if (workOrderId != null) 'workOrderId': workOrderId,
    if (workOrderLabel != null) 'workOrderLabel': workOrderLabel,
  };

  SerialRecord copyWith({
    SerialStatus? status,
    String? workOrderId,
    String? workOrderLabel,
  }) => SerialRecord(
    serial: serial,
    status: status ?? this.status,
    workOrderId: workOrderId ?? this.workOrderId,
    workOrderLabel: workOrderLabel ?? this.workOrderLabel,
  );
}

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
    this.serials = const [],
    this.description,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String barcode;
  final String sku;

  /// Individual units logged against this catalog item (e.g. via barcode
  /// scan), each with its own status (warehouse / on a work order /
  /// installed). [quantity] is the aggregate warehouse stock count — it
  /// only includes units still at [SerialStatus.warehouse].
  final List<SerialRecord> serials;
  final String? description;
  final String? photoUrl;
  final String category;
  final String location;
  final int quantity;
  final String unit;
  final int minStock;

  /// Convenience: just the serial strings, for UI that doesn't need status
  /// (e.g. the count/summary shown in the read-only detail view).
  List<String> get serialNumbers => [for (final s in serials) s.serial];

  StockStatus get status =>
      stockStatusFor(quantity: quantity, minStock: minStock);

  factory Product.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Product(
      id: doc.id,
      name: d['name'] as String? ?? '',
      barcode: d['barcode'] as String? ?? '',
      sku: d['sku'] as String? ?? '',
      serials:
          (d['serials'] as List<dynamic>?)
              ?.map(SerialRecord.fromDynamic)
              .toList() ??
          const [],
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
    'serials': serials.map((s) => s.toMap()).toList(),
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
    List<SerialRecord>? serials,
    String? category,
    String? location,
    int? quantity,
    String? unit,
    int? minStock,
    String? description,
    String? photoUrl,
  }) => Product(
    id: id ?? this.id,
    name: name ?? this.name,
    barcode: barcode ?? this.barcode,
    sku: sku ?? this.sku,
    serials: serials ?? this.serials,
    category: category ?? this.category,
    location: location ?? this.location,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    minStock: minStock ?? this.minStock,
    description: description ?? this.description,
    photoUrl: photoUrl ?? this.photoUrl,
  );
}
