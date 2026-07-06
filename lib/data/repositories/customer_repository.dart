import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/customer.dart';

class CustomerRepository {
  CustomerRepository()
      : _col = FirebaseFirestore.instance.collection('customers'),
        _storage = FirebaseStorage.instance;

  final CollectionReference<Map<String, dynamic>> _col;
  final FirebaseStorage _storage;

  Stream<List<Customer>> watchCustomers() {
    return _col.orderBy('address').snapshots().map(
          (snap) => snap.docs
              .map((d) => Customer.fromFirestore(
                    d as DocumentSnapshot<Map<String, dynamic>>,
                  ))
              .toList(),
        );
  }

  Future<Customer> addCustomer(Customer customer) async {
    final ref = customer.id.isEmpty ? _col.doc() : _col.doc(customer.id);
    final withId = customer.copyWith();
    await ref.set(withId.toMap());
    return Customer(
      id: ref.id,
      address: withId.address,
      name: withId.name,
      phone: withId.phone,
      notes: withId.notes,
      installedUnits: withId.installedUnits,
    );
  }

  Future<void> updateCustomer(Customer customer) async {
    await _col.doc(customer.id).set(customer.toMap());
  }

  Future<void> deleteCustomer(String id) async {
    await _col.doc(id).delete();
  }

  /// Upload a unit photo and return the download URL.
  Future<String> uploadUnitPhoto({
    required String customerId,
    required String unitId,
    required File file,
  }) async {
    final ref =
        _storage.ref('customers/$customerId/units/$unitId.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
