import 'package:cloud_firestore/cloud_firestore.dart';

class InstalledUnit {
  const InstalledUnit({
    required this.id,
    required this.productName,
    required this.installedAt,
    this.photoUrl,
  });

  final String id;
  final String productName;
  final DateTime installedAt;
  final String? photoUrl;

  factory InstalledUnit.fromMap(Map<String, dynamic> m) => InstalledUnit(
        id: m['id'] as String? ?? '',
        productName: m['productName'] as String? ?? '',
        installedAt: m['installedAt'] is Timestamp
            ? (m['installedAt'] as Timestamp).toDate()
            : DateTime.now(),
        photoUrl: m['photoUrl'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'productName': productName,
        'installedAt': Timestamp.fromDate(installedAt),
        if (photoUrl != null) 'photoUrl': photoUrl,
      };
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
        .toList();
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
