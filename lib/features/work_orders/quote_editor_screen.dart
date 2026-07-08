import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/quote.dart';
import '../../data/models/work_order.dart';
import '../../data/providers/work_order_providers.dart';
import 'quote_pdf.dart';

/// Build / edit the quote for a work order. Lines start from the order's
/// equipment list (prices blank — typed here); custom lines cover labor,
/// consumables, anything not in inventory. Totals show subtotal + 13% HST.
class QuoteEditorScreen extends ConsumerStatefulWidget {
  const QuoteEditorScreen({super.key, required this.order});

  final WorkOrder order;

  @override
  ConsumerState<QuoteEditorScreen> createState() => _QuoteEditorScreenState();
}

class _LineEdit {
  _LineEdit({String description = '', int quantity = 1, double? unitPrice})
      : descCtrl = TextEditingController(text: description),
        qtyCtrl = TextEditingController(text: '$quantity'),
        priceCtrl = TextEditingController(
            text: unitPrice == null ? '' : unitPrice.toStringAsFixed(2));

  final TextEditingController descCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;

  QuoteLine toLine() => QuoteLine(
        description: descCtrl.text.trim(),
        quantity: int.tryParse(qtyCtrl.text.trim()) ?? 1,
        unitPrice: double.tryParse(priceCtrl.text.trim()) ?? 0,
      );

  void dispose() {
    descCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _QuoteEditorScreenState extends ConsumerState<QuoteEditorScreen> {
  late final List<_LineEdit> _lines;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  static final _money = NumberFormat.currency(symbol: r'$');

  @override
  void initState() {
    super.initState();
    final existing = widget.order.quote;
    if (existing != null && existing.lines.isNotEmpty) {
      _lines = [
        for (final l in existing.lines)
          _LineEdit(
            description: l.description,
            quantity: l.quantity,
            unitPrice: l.unitPrice,
          ),
      ];
    } else {
      // Seed from the work order's equipment list, prices left blank.
      _lines = [
        for (final i in widget.order.items)
          _LineEdit(description: i.productName, quantity: i.quantity),
      ];
      if (_lines.isEmpty) _lines.add(_LineEdit());
    }
    _notesCtrl = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _notesCtrl.dispose();
    super.dispose();
  }

  Quote _buildQuote() => Quote(
        lines: _lines
            .map((l) => l.toLine())
            .where((l) => l.description.isNotEmpty)
            .toList(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        updatedAt: DateTime.now(),
        // Keep the number this quote was issued with; the repository assigns
        // one on first save.
        number: widget.order.quote?.number,
      );

  /// Returns the quote as persisted (with its assigned number), or null if
  /// the save failed or the quote was empty.
  Future<Quote?> _save() async {
    final quote = _buildQuote();
    if (quote.lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one line to the quote.')),
      );
      return null;
    }
    setState(() => _saving = true);
    try {
      return await ref
          .read(workOrderRepositoryProvider)
          .saveQuote(widget.order.id, quote);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save quote: $e')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndClose() async {
    if (await _save() != null && mounted) Navigator.of(context).pop();
  }

  Future<void> _saveAndShare() async {
    final saved = await _save();
    if (saved == null) return;
    final order = WorkOrder(
      id: widget.order.id,
      installerName: widget.order.installerName,
      installerLicense: widget.order.installerLicense,
      customerId: widget.order.customerId,
      address: widget.order.address,
      customerName: widget.order.customerName,
      items: widget.order.items,
      equipmentNotes: widget.order.equipmentNotes,
      createdAt: widget.order.createdAt,
      installDate: widget.order.installDate,
      scheduleNotes: widget.order.scheduleNotes,
      reason: widget.order.reason,
      quote: saved,
    );
    await shareQuotePdf(order);
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Recomputed every rebuild — onChanged on the fields triggers setState.
    final quote = _buildQuote();

    // The bottom Save/Share bar sits under the keyboard, so both escape
    // hatches matter: drag-to-dismiss on the list + an explicit hide button.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote'),
        actions: [
          if (keyboardOpen)
            IconButton(
              icon: const Icon(Icons.keyboard_hide_outlined),
              tooltip: 'Hide keyboard',
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              widget.order.customerName?.isNotEmpty == true
                  ? '${widget.order.customerName} — ${widget.order.address}'
                  : widget.order.address,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),

            // Header row for the line table.
            const Row(
              children: [
                Expanded(
                    flex: 5,
                    child: Text('Description',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 11))),
                SizedBox(width: 6),
                SizedBox(
                    width: 44,
                    child: Text('Qty',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 11))),
                SizedBox(width: 6),
                SizedBox(
                    width: 84,
                    child: Text('Unit \$',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 11))),
                SizedBox(width: 34),
              ],
            ),
            const SizedBox(height: 6),

            for (var i = 0; i < _lines.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: _lines[i].descCtrl,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: _dec('Item or service'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 44,
                    child: TextField(
                      controller: _lines[i].qtyCtrl,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: _dec('1'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: _lines[i].priceCtrl,
                      onChanged: (_) => setState(() {}),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: _dec('0.00'),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: AppColors.textFaint),
                      onPressed: () => setState(() {
                        _lines.removeAt(i).dispose();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _lines.add(_LineEdit())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add line (labor, consumables…)'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryBlue),
              ),
            ),
            const SizedBox(height: 12),

            // Totals.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                children: [
                  _totalRow('Subtotal', _money.format(quote.subtotal)),
                  const SizedBox(height: 4),
                  _totalRow('HST (13%)', _money.format(quote.tax)),
                  const Divider(color: AppColors.surfaceBorder, height: 16),
                  _totalRow('Total', _money.format(quote.total), bold: true),
                ],
              ),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration:
                  _dec('Notes shown on the quote (warranty, terms, scope)…'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _saveAndClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.surfaceBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveAndShare,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      color: bold ? AppColors.textPrimary : AppColors.textSecondary,
      fontSize: bold ? 16 : 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}
