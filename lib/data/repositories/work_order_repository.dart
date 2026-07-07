import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/quote.dart';
import '../models/work_order.dart';

class WorkOrderRepository {
  WorkOrderRepository()
      : _col = FirebaseFirestore.instance.collection('workOrders');

  final CollectionReference<Map<String, dynamic>> _col;

  Stream<List<WorkOrder>> watchWorkOrders() {
    return _col.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs
              .map((d) => WorkOrder.fromFirestore(
                    d as DocumentSnapshot<Map<String, dynamic>>,
                  ))
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

  Future<void> deleteWorkOrder(String id) async {
    await _col.doc(id).delete();
  }

  /// Write (or overwrite) the quote embedded in a work order.
  Future<void> saveQuote(String orderId, Quote quote) async {
    await _col.doc(orderId).update({'quote': quote.toMap()});
  }
}
