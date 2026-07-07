import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/work_order.dart';
import '../repositories/work_order_repository.dart';

final workOrderRepositoryProvider = Provider<WorkOrderRepository>(
  (_) => WorkOrderRepository(),
);

final workOrdersProvider = StreamProvider<List<WorkOrder>>((ref) {
  return ref.watch(workOrderRepositoryProvider).watchWorkOrders();
});

/// The installer roster (the "Who" dropdown). Static for now — Tim is the
/// only entry until employee login profiles land, then this becomes a
/// Firestore-backed stream.
final installersProvider = Provider<List<Installer>>((_) => const [
      Installer(name: 'Tim', role: 'Owner', license: '000218608'),
    ]);

/// Everything the New-Work-Order form has captured so far. Immutable; all
/// mutations go through [WorkOrderDraftNotifier] so the five section widgets
/// stay decoupled from each other.
class WorkOrderDraft {
  const WorkOrderDraft({
    this.installer,
    this.customer,
    this.address = '',
    this.items = const [],
    this.equipmentNotes = '',
    this.installDate,
    this.scheduleNotes = '',
    this.reason,
  });

  // Who
  final Installer? installer;

  // Where — [customer] is set when the typed address matched an existing
  // profile; [address] always mirrors what's in the text field.
  final Customer? customer;
  final String address;

  // What
  final List<WorkOrderItem> items;
  final String equipmentNotes;

  // When (createdAt is stamped at save time)
  final DateTime? installDate;
  final String scheduleNotes;

  // Why
  final WorkOrderReason? reason;

  /// Minimum bar to create the order: someone assigned, somewhere to go,
  /// and a reason. Equipment and install date can be filled in later.
  bool get isValid =>
      installer != null && address.trim().isNotEmpty && reason != null;
}

class WorkOrderDraftNotifier extends StateNotifier<WorkOrderDraft> {
  WorkOrderDraftNotifier(Installer? defaultInstaller)
      : super(WorkOrderDraft(installer: defaultInstaller));

  void setInstaller(Installer? installer) => state = _copy(installer: installer);

  /// An existing customer was picked from the typeahead — adopt their address.
  void selectCustomer(Customer customer) =>
      state = _copy(customer: customer, address: customer.address);

  /// Free-typed address; drops any previously selected customer so a stale
  /// profile is never attached to a different address.
  void setAddress(String address) => state = WorkOrderDraft(
        installer: state.installer,
        customer: null,
        address: address,
        items: state.items,
        equipmentNotes: state.equipmentNotes,
        installDate: state.installDate,
        scheduleNotes: state.scheduleNotes,
        reason: state.reason,
      );

  void addItem(Product product) {
    if (state.items.any((i) => i.productId == product.id)) return;
    state = _copy(items: [
      ...state.items,
      WorkOrderItem(productId: product.id, productName: product.name),
    ]);
  }

  void removeItem(String productId) => state = _copy(
        items: state.items.where((i) => i.productId != productId).toList(),
      );

  void setItemQuantity(String productId, int quantity) {
    if (quantity < 1) return;
    state = _copy(
      items: [
        for (final i in state.items)
          i.productId == productId ? i.copyWith(quantity: quantity) : i,
      ],
    );
  }

  void setEquipmentNotes(String notes) => state = _copy(equipmentNotes: notes);

  void setInstallDate(DateTime? date) => state = WorkOrderDraft(
        installer: state.installer,
        customer: state.customer,
        address: state.address,
        items: state.items,
        equipmentNotes: state.equipmentNotes,
        installDate: date,
        scheduleNotes: state.scheduleNotes,
        reason: state.reason,
      );

  void setScheduleNotes(String notes) => state = _copy(scheduleNotes: notes);

  void setReason(WorkOrderReason? reason) => state = _copy(reason: reason);

  WorkOrderDraft _copy({
    Installer? installer,
    Customer? customer,
    String? address,
    List<WorkOrderItem>? items,
    String? equipmentNotes,
    String? scheduleNotes,
    WorkOrderReason? reason,
  }) =>
      WorkOrderDraft(
        installer: installer ?? state.installer,
        customer: customer ?? state.customer,
        address: address ?? state.address,
        items: items ?? state.items,
        equipmentNotes: equipmentNotes ?? state.equipmentNotes,
        installDate: state.installDate,
        scheduleNotes: scheduleNotes ?? state.scheduleNotes,
        reason: reason ?? state.reason,
      );
}

/// One draft per open New-Work-Order form (autoDispose resets it on close).
/// Defaults the installer to the first roster entry — Tim, today.
final workOrderDraftProvider = StateNotifierProvider.autoDispose<
    WorkOrderDraftNotifier, WorkOrderDraft>((ref) {
  final roster = ref.watch(installersProvider);
  return WorkOrderDraftNotifier(roster.isEmpty ? null : roster.first);
});
