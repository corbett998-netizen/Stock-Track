import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/quote.dart';
import '../models/work_order.dart';

class WorkOrderRepository {
  WorkOrderRepository()
    : _col = FirebaseFirestore.instance.collection('workOrders');

  final CollectionReference<Map<String, dynamic>> _col;

  Stream<List<WorkOrder>> watchWorkOrders() {
    return _col
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => WorkOrder.fromFirestore(
                  d as DocumentSnapshot<Map<String, dynamic>>,
                ),
              )
              .toList(),
        );
  }

  Future<void> addWorkOrder(WorkOrder order) async {
    final ref = order.id.isEmpty ? _col.doc() : _col.doc(order.id);
    await ref.set(order.toMap());
  }

  Future<void> updateWorkOrder(WorkOrder order) async {
    await _col.doc(order.id).set(order.toMap());
  }

  /// Attaches one scanned unit to an existing work order (the scan flow's
  /// "attach to work order" action) — adds [serial] to that product's line
  /// (creating the line, at quantity 1, if the product isn't on the order
  /// yet) and bumps quantity for lines that don't already include it.
  Future<void> attachProductSerial({
    required String workOrderId,
    required String productId,
    required String productName,
    required String serial,
  }) async {
    final ref = _col.doc(workOrderId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref as DocumentReference<Map<String, dynamic>>);
      if (!snap.exists) {
        throw StateError('No work order with id "$workOrderId"');
      }
      final order = WorkOrder.fromFirestore(snap);
      final index = order.items.indexWhere((i) => i.productId == productId);
      final List<WorkOrderItem> newItems;
      if (index == -1) {
        newItems = [
          ...order.items,
          WorkOrderItem(
            productId: productId,
            productName: productName,
            serials: [serial],
          ),
        ];
      } else {
        final existing = order.items[index];
        if (existing.serials.contains(serial)) return; // already attached
        newItems = [...order.items];
        newItems[index] = existing.copyWith(
          quantity: existing.quantity + 1,
          serials: [...existing.serials, serial],
        );
      }
      tx.update(ref, {'items': newItems.map((i) => i.toMap()).toList()});
    });
  }

  Future<void> deleteWorkOrder(String id) async {
    await _col.doc(id).delete();
  }

  /// Write (or overwrite) the quote embedded in a work order. The first save
  /// of an order's quote assigns the next sequential quote number (the red
  /// counter printed on the PDF); later saves keep the number it was issued.
  /// Returns the quote as persisted, number included.
  Future<Quote> saveQuote(String orderId, Quote quote) async {
    var numbered = quote;
    if (numbered.number == null) {
      final existing = (await _col.doc(orderId).get()).data()?['quote'];
      final prior = existing is Map<String, dynamic>
          ? (existing['number'] as num?)?.toInt()
          : null;
      numbered = quote.copyWith(number: prior ?? await _nextQuoteNumber());
    }
    await _col.doc(orderId).update({'quote': numbered.toMap()});
    return numbered;
  }

  /// Monotonic counter in a meta doc INSIDE workOrders — covered by the
  /// existing security rules, and invisible to the work-order list because
  /// the orderBy(createdAt) query skips docs without a createdAt field.
  Future<int> _nextQuoteNumber() async {
    final ref = _col.doc('_quoteCounter');
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final next = ((snap.data()?['last'] as num?)?.toInt() ?? 0) + 1;
      tx.set(ref, {'last': next});
      return next;
    });
  }
}
