/// A customer-facing quote built from a work order. Embedded in the work
/// order document (one quote per order). Line prices are typed at quote time —
/// inventory carries no pricing.
class QuoteLine {
  const QuoteLine({
    required this.description,
    this.quantity = 1,
    this.unitPrice = 0,
  });

  final String description;
  final int quantity;
  final double unitPrice;

  double get lineTotal => quantity * unitPrice;

  factory QuoteLine.fromMap(Map<String, dynamic> m) => QuoteLine(
        description: m['description'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };
}

class Quote {
  const Quote({
    required this.lines,
    this.taxRate = 0.13,
    this.notes,
    required this.updatedAt,
  });

  final List<QuoteLine> lines;

  /// 13% HST. Persisted per quote so historical quotes keep the rate they
  /// were issued with if the default ever changes.
  final double taxRate;
  final String? notes;
  final DateTime updatedAt;

  double get subtotal => lines.fold(0, (sum, l) => sum + l.lineTotal);
  double get tax => subtotal * taxRate;
  double get total => subtotal + tax;

  factory Quote.fromMap(Map<String, dynamic> m) => Quote(
        lines: (m['lines'] as List<dynamic>? ?? [])
            .map((e) => QuoteLine.fromMap(e as Map<String, dynamic>))
            .toList(),
        taxRate: (m['taxRate'] as num?)?.toDouble() ?? 0.13,
        notes: m['notes'] as String?,
        updatedAt: m['updatedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int)
            : DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'lines': lines.map((l) => l.toMap()).toList(),
        'taxRate': taxRate,
        if (notes != null) 'notes': notes,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };
}
