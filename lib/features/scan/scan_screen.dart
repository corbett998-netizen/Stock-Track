import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/product.dart';
import '../../data/providers/inventory_providers.dart';
import '../../data/providers/repository_providers.dart';
import '../inventory/product_detail_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _barcodeController = TextEditingController();
  final _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  Product? _matchedProduct;
  int _qty = 1;
  bool _scanning = true; // false while processing a result
  bool _torchOn = false;

  @override
  void dispose() {
    _barcodeController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _lookup(String code) async {
    final scannedCode = code.trim();
    if (scannedCode.isEmpty) return;

    // Pause camera while we process.
    setState(() => _scanning = false);
    await _cameraController.stop();
    FocusScope.of(context).unfocus();

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
      _barcodeController.clear();
      _resumeScanning();
      return;
    }

    setState(() {
      _matchedProduct = product;
      _qty = 1;
    });
  }

  Future<void> _confirmAdd() async {
    final product = _matchedProduct;
    if (product == null || _qty <= 0) return;

    final repo = ref.read(inventoryRepositoryProvider);
    await repo.adjustQuantity(productId: product.id, delta: _qty);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added $_qty × ${product.name} — now ${product.quantity + _qty} ${product.unit}',
        ),
      ),
    );
    _dismissMatch();
  }

  void _dismissMatch() {
    setState(() {
      _matchedProduct = null;
      _qty = 1;
      _barcodeController.clear();
    });
    _resumeScanning();
  }

  void _resumeScanning() {
    _cameraController.start();
    setState(() => _scanning = true);
  }

  @override
  Widget build(BuildContext context) {
    final liveProduct = _matchedProduct == null
        ? null
        : (ref.watch(productsProvider).valueOrNull ?? [])
            .where((p) => p.id == _matchedProduct!.id)
            .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_matchedProduct == null)
            IconButton(
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: () {
                _cameraController.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              },
            ),
        ],
      ),
      body: SafeArea(
        child: _matchedProduct != null
            ? _QuantityAdjuster(
                product: liveProduct ?? _matchedProduct!,
                qty: _qty,
                onQtyChanged: (v) => setState(() => _qty = v),
                onConfirm: _confirmAdd,
                onCancel: _dismissMatch,
              )
            : _ScannerView(
                cameraController: _cameraController,
                barcodeController: _barcodeController,
                onLookup: _lookup,
                onDetect: (barcode) {
                  if (!_scanning) return;
                  final raw = barcode.barcodes.firstOrNull?.rawValue;
                  if (raw != null) _lookup(raw);
                },
              ),
      ),
    );
  }
}

// ── Scanner view ──────────────────────────────────────────────────────────────

class _ScannerView extends StatelessWidget {
  const _ScannerView({
    required this.cameraController,
    required this.barcodeController,
    required this.onLookup,
    required this.onDetect,
  });

  final MobileScannerController cameraController;
  final TextEditingController barcodeController;
  final ValueChanged<String> onLookup;
  final ValueChanged<BarcodeCapture> onDetect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text(
          'Point camera at a barcode or enter it manually',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Live camera viewport.
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 240,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: cameraController,
                  onDetect: onDetect,
                ),
                // Finder overlay.
                Center(
                  child: Container(
                    width: 200,
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AppColors.primaryBlue, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Manual entry.
        TextField(
          controller: barcodeController,
          style: const TextStyle(color: AppColors.textPrimary),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.search,
          onSubmitted: onLookup,
          decoration: InputDecoration(
            prefixIcon:
                const Icon(Icons.numbers, color: AppColors.textFaint),
            hintText: 'Enter barcode manually…',
            suffixIcon: TextButton(
              onPressed: () => onLookup(barcodeController.text),
              child: const Text('Look up'),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Quantity adjuster ─────────────────────────────────────────────────────────

class _QuantityAdjuster extends StatefulWidget {
  const _QuantityAdjuster({
    required this.product,
    required this.qty,
    required this.onQtyChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  final Product product;
  final int qty;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  State<_QuantityAdjuster> createState() => _QuantityAdjusterState();
}

class _QuantityAdjusterState extends State<_QuantityAdjuster> {
  late final _controller =
      TextEditingController(text: widget.qty.toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(int value) {
    final clamped = value.clamp(1, 9999);
    _controller.text = clamped.toString();
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    widget.onQtyChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${p.category}  ·  ${p.location}',
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Text(
                  'Current stock: ${p.quantity} ${p.unit}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'How many are you adding?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              _StepButton(
                  icon: Icons.remove, onTap: () => _set(widget.qty - 1)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      widget.onQtyChanged(parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              _StepButton(
                  icon: Icons.add, onTap: () => _set(widget.qty + 1)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'New total will be: ${p.quantity + widget.qty} ${p.unit}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
          ),

          const Spacer(),

          FilledButton(
            onPressed: widget.onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.inStockGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(
              'Add ${widget.qty} to stock',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: widget.onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.surfaceBorder),
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 24),
      ),
    );
  }
}
