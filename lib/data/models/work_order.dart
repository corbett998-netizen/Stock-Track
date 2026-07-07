import 'package:cloud_firestore/cloud_firestore.dart';

import 'quote.dart';

/// Why a work order exists — the "Why" dropdown on the 5-W form.
enum WorkOrderReason {
  newInstall('New install'),
  replaceOld('Replace old'),
  warranty('Warranty'),
  upgrades('Upgrades');

  const WorkOrderReason(this.label);
  final String label;

  static WorkOrderReason? fromName(String? name) {
    if (name == null) return null;
    for (final r in WorkOrderReason.values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

/// An installer who can be assigned to a work order (the "Who").
///
/// For now the roster is a static list (Tim, the owner). When employee login
/// profiles land, this becomes a Firestore-backed collection — keep the shape
/// stable so work orders written today stay readable.
class Installer {
  const Installer({
    required this.name,
    required this.license,
    this.role,
  });

  final String name;
  final String license;
  final String? role;

  String get displayLabel => role == null ? name : '$name ($role)';
}

/// One line of required equipment on a work order (the "What").
///
/// `productName` is a DENORMALIZED snapshot, same rule as [Installation]: a
/// work order must stay readable even if the product is later edited/removed.
class WorkOrderItem {
  const WorkOrderItem({
    required this.productId,
    required this.productName,
    this.quantity = 1,
  });

  final String productId;
  final String productName;
  final int quantity;

  factory WorkOrderItem.fromMap(Map<String, dynamic> m) => WorkOrderItem(
        productId: m['productId'] as String? ?? '',
        productName: m['productName'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
      };

  WorkOrderItem copyWith({int? quantity}) => WorkOrderItem(
        productId: productId,
        productName: productName,
        quantity: quantity ?? this.quantity,
      );
}

/// A work order in the 5-W format: Who / Where / What / When / Why.
class WorkOrder {
  const WorkOrder({
    required this.id,
    // Who
    required this.installerName,
    required this.installerLicense,
    // Where
    this.customerId,
    required this.address,
    this.customerName,
    // What
    this.items = const [],
    this.equipmentNotes,
    // When
    required this.createdAt,
    this.installDate,
    this.scheduleNotes,
    // Why
    required this.reason,
    this.quote,
  });

  final String id;
  final String installerName;
  final String installerLicense;

  /// Firestore id of the customer, when the address matched an existing
  /// profile (or one was created during the "Where" step).
  final String? customerId;
  final String address;
  final String? customerName;

  final List<WorkOrderItem> items;
  final String? equipmentNotes;

  final DateTime createdAt;
  final DateTime? installDate;

  /// Special requests / site-access info captured in the "When" step.
  final String? scheduleNotes;

  final WorkOrderReason reason;

  /// Customer-facing quote built from this order (one per order, editable).
  final Quote? quote;

  factory WorkOrder.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return WorkOrder(
      id: doc.id,
      installerName: d['installerName'] as String? ?? '',
      installerLicense: d['installerLicense'] as String? ?? '',
      customerId: d['customerId'] as String?,
      address: d['address'] as String? ?? '',
      customerName: d['customerName'] as String?,
      items: (d['items'] as List<dynamic>? ?? [])
          .map((e) => WorkOrderItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      equipmentNotes: d['equipmentNotes'] as String?,
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      installDate: d['installDate'] is Timestamp
          ? (d['installDate'] as Timestamp).toDate()
          : null,
      scheduleNotes: d['scheduleNotes'] as String?,
      reason:
          WorkOrderReason.fromName(d['reason'] as String?) ??
              WorkOrderReason.newInstall,
      quote: d['quote'] is Map<String, dynamic>
          ? Quote.fromMap(d['quote'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'installerName': installerName,
        'installerLicense': installerLicense,
        if (customerId != null) 'customerId': customerId,
        'address': address,
        if (customerName != null) 'customerName': customerName,
        'items': items.map((i) => i.toMap()).toList(),
        if (equipmentNotes != null) 'equipmentNotes': equipmentNotes,
        'createdAt': Timestamp.fromDate(createdAt),
        if (installDate != null) 'installDate': Timestamp.fromDate(installDate!),
        if (scheduleNotes != null) 'scheduleNotes': scheduleNotes,
        'reason': reason.name,
        if (quote != null) 'quote': quote!.toMap(),
      };
}
