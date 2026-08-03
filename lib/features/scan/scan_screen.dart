import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/product.dart';
import '../../data/providers/inventory_providers.dart';
import '../../data/providers/repository_providers.dart';
import '../inventory/product_detail_screen.dart';

/// How long the same set of barcodes must be continuously visible before we
/// treat the camera as "stopped moving" and capture it.
const _stabilityHold = Duration(seconds: 2);

/// How long to hold the frozen capture on screen for review before moving on.
const _freezeReviewDuration = Duration(seconds: 2);

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _barcodeController = TextEditingController();
  final _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    returnImage: true,
  );

  // Stability tracking — how long has this exact set of barcodes been held
  // steady in frame.
  List<String>? _pendingSignature;
  DateTime? _pendingSince;

  // Freeze-frame review, shown briefly right after a stable capture.
  Uint8List? _frozenImage;
  String? _classifiedCatalog;
  String? _classifiedSerial;

  // Existing-product match — either a one-tap "log this unit" confirm
  // (when we captured a serial) or the bulk quantity stepper (when we
  // didn't, e.g. manual entry or a single-barcode label).
  Product? _matchedProduct;
  String? _pendingSerial;
  int _qty = 1;

  // Already-logged-this-unit notice.
  Product? _duplicateProduct;
  String? _duplicateSerial;

  bool _scanning = true; // actively listening for a stable detection
  bool _torchOn = false;

  @override
  void dispose() {
    _barcodeController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning) return;

    final codes = capture.barcodes
        .where((b) => b.rawValue != null && b.rawValue!.isNotEmpty)
        .toList();
    if (codes.isEmpty) {
      _pendingSignature = null;
      _pendingSince = null;
      return;
    }

    final signature = codes.map((b) => b.rawValue!).toList()..sort();
    final now = DateTime.now();

    if (!listEquals(signature, _pendingSignature)) {
      _pendingSignature = signature;
      _pendingSince = now;
      return;
    }

    if (_pendingSince != null && now.difference(_pendingSince!) >= _stabilityHold) {
      _pendingSignature = null;
      _pendingSince = null;
      _captureStable(capture, codes);
    }
  }

  Future<void> _captureStable(BarcodeCapture capture, List<Barcode> codes) async {
    setState(() => _scanning = false);
    await _cameraController.stop();

    // The catalog number is the largest, most-prominent barcode on the
    // label; a second (smaller) barcode, if present, is the serial number.
    final bySize = [...codes]..sort(
        (a, b) => (b.size.width * b.size.height)
            .compareTo(a.size.width * a.size.height),
      );
    final catalogNumber = bySize.first.rawValue!;
    final serialNumber = bySize.length > 1 ? bySize[1].rawValue : null;

    if (!mounted) return;
    setState(() {
      _frozenImage = capture.image;
      _classifiedCatalog = catalogNumber;
      _classifiedSerial = serialNumber;
    });

    await Future.delayed(_freezeReviewDuration);
    if (!mounted) return;

    await _lookup(catalogNumber, serial: serialNumber);
  }

  Future<void> _lookup(String catalogNumber, {String? serial}) async {
    final code = catalogNumber.trim();
    if (code.isEmpty) return;

    setState(() {
      _scanning = false;
      _frozenImage = null;
    });
    await _cameraController.stop();
    FocusScope.of(context).unfocus();

    final repo = ref.read(inventoryRepositoryProvider);
    final product = await repo.findByBarcode(code);
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
              barcode: code,
              sku: '',
              category: '',
              location: '',
              quantity: serial != null ? 1 : 0,
              unit: 'units',
              minStock: 0,
              serials: serial != null ? [serial] : const [],
            ),
          ),
        ),
      );
      _barcodeController.clear();
      _resumeScanning();
      return;
    }

    if (serial != null && product.serials.contains(serial)) {
      setState(() {
        _duplicateProduct = product;
        _duplicateSerial = serial;
      });
      return;
    }

    setState(() {
      _matchedProduct = product;
      _pendingSerial = serial;
      _qty = 1;
    });
  }

  Future<void> _confirmAdd() async {
    final product = _matchedProduct;
    if (product == null) return;

    final repo = ref.read(inventoryRepositoryProvider);
    final serial = _pendingSerial;

    if (serial != null) {
      await repo.addSerial(productId: product.id, serial: serial);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logged unit $serial — ${product.name} now ${product.quantity + 1} ${product.unit}',
          ),
        ),
      );
    } else {
      if (_qty <= 0) return;
      await repo.adjustQuantity(productId: product.id, delta: _qty);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added $_qty × ${product.name} — now ${product.quantity + _qty} ${product.unit}',
          ),
        ),
      );
    }
    _dismissMatch();
  }

  void _dismissMatch() {
    setState(() {
      _matchedProduct = null;
      _pendingSerial = null;
      _qty = 1;
      _barcodeController.clear();
    });
    _resumeScanning();
  }

  void _dismissDuplicate() {
    setState(() {
      _duplicateProduct = null;
      _duplicateSerial = null;
    });
    _resumeScanning();
  }

  void _resumeScanning() {
    _frozenImage = null;
    _classifiedCatalog = null;
    _classifiedSerial = null;
    _pendingSignature = null;
    _pendingSince = null;
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

    final showTorch = _matchedProduct == null &&
        _frozenImage == null &&
        _duplicateProduct == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (showTorch)
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
        child: _duplicateProduct != null
            ? _DuplicateNotice(
                product: _duplicateProduct!,
                serial: _duplicateSerial!,
                onDismiss: _dismissDuplicate,
              )
            : _matchedProduct != null
                ? (_pendingSerial != null
                    ? _SerialConfirm(
                        product: liveProduct ?? _matchedProduct!,
                        serial: _pendingSerial!,
                        onConfirm: _confirmAdd,
                        onCancel: _dismissMatch,
                      )
                    : _QuantityAdjuster(
                        product: liveProduct ?? _matchedProduct!,
                        qty: _qty,
                        onQtyChanged: (v) => setState(() => _qty = v),
                        onConfirm: _confirmAdd,
                        onCancel: _dismissMatch,
                      ))
                : _frozenImage != null
                    ? _FrozenReview(
                        image: _frozenImage!,
                        catalogNumber: _classifiedCatalog,
                        serialNumber: _classifiedSerial,
                      )
                    : _ScannerView(
                        cameraController: _cameraController,
                        barcodeController: _barcodeController,
                        onLookup: (code) => _lookup(code),
                        onDetect: _onDetect,
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
          'Hold steady over the barcode(s) — catalog number and serial are captured automatically. Or enter a code manually.',
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

// ── Freeze-frame review ─────────────────────────────────────────────────────────

class _FrozenReview extends StatelessWidget {
  const _FrozenReview({
    required this.image,
    required this.catalogNumber,
    required this.serialNumber,
  });

  final Uint8List image;
  final String? catalogNumber;
  final String? serialNumber;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: Image.memory(image, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.inStockGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Captured',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                _ReadoutRow(label: 'Catalog number', value: catalogNumber),
                const SizedBox(height: 8),
                _ReadoutRow(label: 'Serial number', value: serialNumber),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadoutRow extends StatelessWidget {
  const _ReadoutRow({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(
          value ?? 'Not detected',
          style: TextStyle(
            color: value != null
                ? AppColors.textPrimary
                : AppColors.textFaint,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Duplicate-unit notice ─────────────────────────────────────────────────────

class _DuplicateNotice extends StatelessWidget {
  const _DuplicateNotice({
    required this.product,
    required this.serial,
    required this.onDismiss,
  });

  final Product product;
  final String serial;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.info_outline,
              color: AppColors.lowOrange, size: 40),
          const SizedBox(height: 16),
          Text(
            'Already logged',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Serial $serial is already recorded on ${product.name}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onDismiss,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ── Single-unit serial confirm ────────────────────────────────────────────────

class _SerialConfirm extends StatelessWidget {
  const _SerialConfirm({
    required this.product,
    required this.serial,
    required this.onConfirm,
    required this.onCancel,
  });

  final Product product;
  final String serial;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
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
                  product.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${product.category}  ·  ${product.location}',
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 13),
                ),
                const SizedBox(height: 12),
                _ReadoutRow(label: 'Serial number', value: serial),
                const SizedBox(height: 8),
                Text(
                  'Current stock: ${product.quantity} ${product.unit}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.inStockGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text(
              'Add this unit to stock',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onCancel,
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

// ── Quantity adjuster (bulk / no-serial-captured fallback) ─────────────────────

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
