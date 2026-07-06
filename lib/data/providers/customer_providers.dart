import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import '../repositories/customer_repository.dart';

final customerRepositoryProvider = Provider<CustomerRepository>(
  (_) => CustomerRepository(),
);

final customersProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).watchCustomers();
});
