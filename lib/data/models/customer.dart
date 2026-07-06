import 'package:cloud_firestore/cloud_firestore.dart';

class InstalledUnit {
  const InstalledUnit({
    required this.id,
    required this.productName,
    required this.installedAt,
    this.photoUrl,
    this.serialNumber,
    this.barcode,
    this.category,
    this.warehouseLocation,
    this.quantityInstalled = 1,
    this.sortOrder = 0,
  });

  final String id;
  final String productName;
  final DateTime installedAt;
  final String? photoUrl;
  final String? serialNumber;
  final String? barcode;
  final String? category;
  final String? warehouseLocation;
  final int quantityInstalled;
  final int sortOrder;

  factory InstalledUnit.fromMap(Map<String, dynamic> m) => InstalledUnit(
        id: m['id'] as String? ?? '',
        productName: m['productName'] as String? ?? '',
        installedAt: m['installedAt'] is Timestamp
            ? (m['installedAt'] as Timestamp).toDate()
            : DateTime.now(),
        photoUrl: m['photoUrl'] as String?,
        serialNumber: m['serialNumber'] as String?,
        barcode: m['barcode'] as String?,
        category: m['category'] as String?,
        warehouseLocation: m['warehouseLocation'] as String?,
        quantityInstalled: (m['quantityInstalled'] as num?)?.toInt() ?? 1,
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'productName': productName,
        'installedAt': Timestamp.fromDate(installedAt),
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (serialNumber != null) 'serialNumber': serialNumber,
        if (barcode != null) 'barcode': barcode,
        if (category != null) 'category': category,
        if (warehouseLocation != null) 'warehouseLocation': warehouseLocation,
        'quantityInstalled': quantityInstalled,
        'sortOrder': sortOrder,
      };

  InstalledUnit copyWith({
    String? photoUrl,
    String? serialNumber,
    String? barcode,
    String? category,
    String? warehouseLocation,
    int? quantityInstalled,
    int? sortOrder,
  }) =>
      InstalledUnit(
        id: id,
        productName: productName,
        installedAt: installedAt,
        photoUrl: photoUrl ?? this.photoUrl,
        serialNumber: serialNumber ?? this.serialNumber,
        barcode: barcode ?? this.barcode,
        category: category ?? this.category,
        warehouseLocation: warehouseLocation ?? this.warehouseLocation,
        quantityInstalled: quantityInstalled ?? this.quantityInstalled,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

class Customer {
  const Customer({
    required this.id,
    required this.address,
    required this.name,
    required this.phone,
    this.notes,
    this.installedUnits = const [],
  });

  final String id;
  final String address;
  final String name;
  final String phone;
  final String? notes;
  final List<InstalledUnit> installedUnits;

  factory Customer.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final units = (d['installedUnits'] as List<dynamic>? ?? [])
        .map((e) => InstalledUnit.fromMap(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Customer(
      id: doc.id,
      address: d['address'] as String? ?? '',
      name: d['name'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      notes: d['notes'] as String?,
      installedUnits: units,
    );
  }

  Map<String, dynamic> toMap() => {
        'address': address,
        'name': name,
        'phone': phone,
        if (notes != null) 'notes': notes,
        'installedUnits': installedUnits.map((u) => u.toMap()).toList(),
      };

  Customer copyWith({
    String? address,
    String? name,
    String? phone,
    String? notes,
    List<InstalledUnit>? installedUnits,
  }) =>
      Customer(
        id: id,
        address: address ?? this.address,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        notes: notes ?? this.notes,
        installedUnits: installedUnits ?? this.installedUnits,
      );
}
