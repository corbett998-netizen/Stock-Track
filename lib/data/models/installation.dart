/// An install record — written on every scan-out / install. The backbone of
/// the Dashboard's "Installed Today" + "Recent Installations" panels (and, in
/// slice 2, the History screen + recall tracing).
///
/// `productName` / `installerName` are intentionally DENORMALIZED snapshots: an
/// install record is a historical fact and must stay readable even if the
/// product or installer is later edited or removed.
class Installation {
  const Installation({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.installerName,
    required this.address,
    required this.installedAt,
  });

  final String id;
  final String productId;
  final String productName;
  final int quantity;
  final String installerName;
  final String address;
  final DateTime installedAt;
}
