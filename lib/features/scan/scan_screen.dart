import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/installation.dart';
import '../../data/models/product.dart';
import '../../data/providers/inventory_providers.dart';
import '../../data/providers/repository_providers.dart';
import '../inventory/product_detail_screen.dart';
import 'scan_providers.dart';

/// Scan tab. The camera is STUBBED for slice 1 (no `mobile_scanner` wired) — a
/// "Simulate scan" button stands in for a live decode, and a manual barcode
/// field lets you look up any item. A known barcode prompts a quick quantity
/// dialog and writes straight through `adjustQuantity`; an unknown barcode
/// opens the product-detail screen in "new product" mode with the scanned
/// code pre-filled. Swapping in a real camera later is additive: it only
/// needs to feed a decoded barcode into the same lookup.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _barcodeController = TextEditingController();
  final _rng = Random();

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _lookup(String code) async {
    final scannedCode = code.trim();
    if (scannedCode.isEmpty) return;

    final repo = ref.read(inventoryRepositoryProvider);
    final product = await repo.findByBarcode(scannedCode);
    if (!mounted) return;

    if (product == null) {
      _barcodeController.clear();
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ProductDetailScreen(
            isNew: true,
            product: Product(
              id: '',
              name: '',
              barcode: scannedCode,
              sku: '',
              category: '',
              location: '',
              quantity: 0,
              unit: 'units',
              minStock: 0,
            ),
          ),
        ),
      );
      return;
    }

    final qty = await _askQuantity(product);
    if (qty == null || qty <= 0) return;
    if (!mounted) return;

    final mode = ref.read(scanModeProvider);
    final delta = mode.sign * qty;
    final updated =
        await repo.adjustQuantity(productId: product.id, delta: delta);

    if (mode == ScanMode.scanOut) {
      await ref.read(installationRepositoryProvider).add(
            Installation(
              id: 'i_${DateTime.now().microsecondsSinceEpoch}',
              productId: product.id,
              productName: product.name,
              quantity: qty,
              installerName: 'Unassigned',
              address: 'No address provided',
              installedAt: DateTime.now(),
            ),
          );
    }

    if (!mounted) return;
    final verb = mode == ScanMode.stockIn ? 'Stocked in' : 'Scanned out';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$verb $qty × ${product.name} — now ${updated.quantity} ${product.unit}',
        ),
      ),
    );
    _barcodeController.clear();
  }

  Future<int?> _askQuantity(Product product) {
    final mode = ref.read(scanModeProvider);
    final controller = TextEditingController(text: '1');
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(product.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Currently ${product.quantity} ${product.unit} · ${mode.label}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(int.tryParse(controller.text.trim()) ?? 1),
            child: Text(mode.label),
          ),
        ],
      ),
    );
  }

  Future<void> _simulateScan() async {
    final products = ref.read(productsProvider).valueOrNull ?? const [];
    if (products.isEmpty) return;
    final pick = products[_rng.nextInt(products.length)];
    _barcodeController.text = pick.barcode;
    await _lookup(pick.barcode);
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
          ],
        ),
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
