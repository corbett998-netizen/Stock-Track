import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/installation.dart';
import '../../data/models/product.dart';
import '../../data/providers/inventory_providers.dart';
import '../../data/providers/repository_providers.dart';
import 'scan_providers.dart';

/// Scan tab. The camera is STUBBED for slice 1 (no `mobile_scanner` wired) — a
/// "Simulate scan" button stands in for a live decode, and a manual barcode
/// field lets you look up any item. The stock-in / scan-out toggle + the
/// resulting-quantity preview + the confirm write are all REAL and update the
/// Dashboard / Inventory live. Swapping in a real camera later is additive: it
/// only needs to feed a decoded barcode into the same lookup.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _barcodeController = TextEditingController();
  final _installerController = TextEditingController();
  final _addressController = TextEditingController();
  final _rng = Random();

  Product? _found;
  String? _notFoundCode;
  int _qty = 1;

  @override
  void dispose() {
    _barcodeController.dispose();
    _installerController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _lookup(String code) async {
    final repo = ref.read(inventoryRepositoryProvider);
    final product = await repo.findByBarcode(code.trim());
    if (!mounted) return;
    setState(() {
      _found = product;
      _notFoundCode = product == null ? code.trim() : null;
      _qty = 1;
    });
  }

  Future<void> _simulateScan() async {
    final products = ref.read(productsProvider).valueOrNull ?? const [];
    if (products.isEmpty) return;
    final pick = products[_rng.nextInt(products.length)];
    _barcodeController.text = pick.barcode;
    await _lookup(pick.barcode);
  }

  void _clear() {
    setState(() {
      _found = null;
      _notFoundCode = null;
      _qty = 1;
      _barcodeController.clear();
      _installerController.clear();
      _addressController.clear();
    });
  }

  Future<void> _confirm() async {
    final product = _found;
    if (product == null) return;
    final mode = ref.read(scanModeProvider);
    final delta = mode.sign * _qty;

    final updated = await ref.read(inventoryRepositoryProvider).adjustQuantity(
          productId: product.id,
          delta: delta,
        );

    if (mode == ScanMode.scanOut) {
      await ref.read(installationRepositoryProvider).add(
            Installation(
              id: 'i_${DateTime.now().microsecondsSinceEpoch}',
              productId: product.id,
              productName: product.name,
              quantity: _qty,
              installerName: _installerController.text.trim().isEmpty
                  ? 'Unassigned'
                  : _installerController.text.trim(),
              address: _addressController.text.trim().isEmpty
                  ? 'No address provided'
                  : _addressController.text.trim(),
              installedAt: DateTime.now(),
            ),
          );
    }

    if (!mounted) return;
    final verb = mode == ScanMode.stockIn ? 'Stocked in' : 'Scanned out';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$verb $_qty × ${product.name} — now ${updated.quantity} ${product.unit}',
        ),
      ),
    );
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(scanModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const SizedBox(height: 2),
          const Text(
            'Move stock in or out by barcode',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Mode toggle — load-bearing, always visible.
          _ModeToggle(
            mode: mode,
            onChanged: (m) => ref.read(scanModeProvider.notifier).state = m,
          ),
          const SizedBox(height: 16),

          // Stubbed camera viewport.
          _CameraStub(mode: mode),
          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: _simulateScan,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Simulate scan'),
          ),
          const SizedBox(height: 12),

          // Manual barcode entry.
          TextField(
            controller: _barcodeController,
            style: const TextStyle(color: AppColors.textPrimary),
            keyboardType: TextInputType.number,
            onSubmitted: _lookup,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.numbers, color: AppColors.textFaint),
              hintText: 'Enter barcode manually…',
              suffixIcon: TextButton(
                onPressed: () => _lookup(_barcodeController.text),
                child: const Text('Look up'),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_found != null) _resultSheet(_found!, mode),
          if (_notFoundCode != null) _notFound(_notFoundCode!),
        ],
      ),
    ),
    );
  }

  Widget _resultSheet(Product product, ScanMode mode) {
    final resulting = mode == ScanMode.stockIn
        ? product.quantity + _qty
        : (product.quantity - _qty).clamp(0, 1 << 30);
    final accent = mode == ScanMode.stockIn
        ? AppColors.inStockGreen
        : AppColors.primaryBlue;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent),
                ),
                child: Text(
                  mode.label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${product.barcode}   ·   ${product.category}   ·   ${product.location}',
            style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // Quantity stepper.
          Row(
            children: [
              const Text('Quantity', style: TextStyle(color: AppColors.textSecondary)),
              const Spacer(),
              _StepBtn(icon: Icons.remove, onTap: () {
                if (_qty > 1) setState(() => _qty--);
              }),
              SizedBox(
                width: 44,
                child: Text(
                  '$_qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StepBtn(icon: Icons.add, onTap: () => setState(() => _qty++)),
            ],
          ),
          const SizedBox(height: 14),

          // Resulting-quantity preview — the guardrail.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${product.quantity}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 18),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.arrow_forward, size: 18, color: AppColors.textFaint),
                ),
                Text(
                  '$resulting',
                  style: TextStyle(
                    color: accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  product.unit,
                  style: const TextStyle(color: AppColors.textFaint, fontSize: 13),
                ),
              ],
            ),
          ),

          // Scan-out captures installer + site address (free-text in slice 1).
          if (mode == ScanMode.scanOut) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _installerController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline, color: AppColors.textFaint),
                hintText: 'Installer name',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.textFaint),
                hintText: 'Install site address',
              ),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.surfaceBorder),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: Text('Confirm ${mode.label.toLowerCase()}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notFound(String code) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off, color: AppColors.textSecondary, size: 28),
          const SizedBox(height: 8),
          Text(
            'No product found for "$code"',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Add new product — coming in the inventory-CRUD slice.'),
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryBlue,
              side: const BorderSide(color: AppColors.primaryBlue),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add new product'),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});
  final ScanMode mode;
  final ValueChanged<ScanMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          _segment(
            label: 'Stock-in',
            icon: Icons.south_west,
            selected: mode == ScanMode.stockIn,
            color: AppColors.inStockGreen,
            onTap: () => onChanged(ScanMode.stockIn),
          ),
          _segment(
            label: 'Scan-out',
            icon: Icons.north_east,
            selected: mode == ScanMode.scanOut,
            color: AppColors.primaryBlue,
            onTap: () => onChanged(ScanMode.scanOut),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? color : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? color : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraStub extends StatelessWidget {
  const _CameraStub({required this.mode});
  final ScanMode mode;

  @override
  Widget build(BuildContext context) {
    final accent = mode == ScanMode.stockIn
        ? AppColors.inStockGreen
        : AppColors.primaryBlue;
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 160,
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: accent, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const Positioned(
            bottom: 12,
            child: Text(
              'Camera stubbed for slice 1',
              style: TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ),
          Icon(Icons.qr_code_scanner, size: 36, color: accent.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}
