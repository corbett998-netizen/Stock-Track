import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/product.dart';
import '../../data/providers/inventory_providers.dart';
import '../../data/providers/repository_providers.dart';
import '../inventory/product_detail_screen.dart';

/// Best-effort catalog/serial numbers read from the label's printed text
/// (as opposed to a decoded barcode value, which often encodes something
/// else entirely — e.g. a UPC/GTIN that doesn't match the printed catalog
/// number a person would actually read off the nameplate).
class _OcrGuess {
  const _OcrGuess({this.catalog, this.serial});
  final String? catalog;
  final String? serial;
}

final _catalogLabelPattern = RegExp(
  r'\b(CAT(?:ALOG)?\.?\s*(?:NO|NUM|#)?|MODEL\.?\s*(?:NO|NUM|#)?|P\s*/\s*N|PART\.?\s*(?:NO|NUM|#)?)\b\.?\s*[:\-]?',
  caseSensitive: false,
);
final _serialLabelPattern = RegExp(
  r'\b(S\s*/\s*N|SERIAL\.?\s*(?:NO|NUM|#)?)\b\.?\s*[:\-]?',
  caseSensitive: false,
);

/// Scans recognized text lines for common nameplate labels ("MODEL NO.",
/// "CAT #", "SERIAL NO.", "S/N") and returns the value printed near each
/// one, if found. Nameplates typically print the caption directly above a
/// barcode and the human-readable value directly below it — the barcode
/// itself produces no OCR text, so "below" has to be found by comparing
/// each line's actual on-image position, not by list order (ML Kit doesn't
/// guarantee lines come back in top-to-bottom reading order). This is a
/// heuristic, not a guarantee — the caller is expected to let the user
/// review/correct the result (and pick from the raw detected lines).
_OcrGuess _guessCatalogAndSerial(RecognizedText text) {
  final lines = [for (final block in text.blocks) ...block.lines];

  String? findValue(RegExp labelPattern) {
    for (final captionLine in lines) {
      final captionText = captionLine.text.trim();
      final match = labelPattern.firstMatch(captionText);
      if (match == null) continue;

      // Caption and value on the same line (e.g. "MODEL NO: ABC123").
      final sameLineValue = captionText.substring(match.end).trim();
      if (sameLineValue.isNotEmpty) return sameLineValue;

      // Otherwise, find the closest line that sits below this caption and
      // roughly lines up with it horizontally (allowing generous slack,
      // since the value is centered under a barcode that may be a
      // different width than the caption text above it).
      final captionBox = captionLine.boundingBox;
      TextLine? best;
      double bestGap = double.infinity;
      for (final candidate in lines) {
        if (identical(candidate, captionLine)) continue;
        if (labelPattern.hasMatch(candidate.text)) continue;
        final box = candidate.boundingBox;
        final verticalGap = box.top - captionBox.bottom;
        if (verticalGap < -captionBox.height * 0.3) continue; // not below
        final horizontalOffset = (box.center.dx - captionBox.center.dx).abs();
        if (horizontalOffset > captionBox.width + box.width) continue;
        if (verticalGap < bestGap) {
          bestGap = verticalGap;
          best = candidate;
        }
      }
      if (best != null) {
        final value = best.text.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  return _OcrGuess(
    catalog: findValue(_catalogLabelPattern),
    serial: findValue(_serialLabelPattern),
  );
}

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

  // The most recently delivered camera frame, refreshed continuously while
  // live — this is what "Capture" freezes when tapped. No barcode scanning
  // is used at all; MobileScanner is just the camera preview/frame source.
  Uint8List? _latestFrame;

  // Freeze-frame review, shown after a manual capture. Catalog/serial are
  // pre-filled with an OCR best guess but stay fully editable — the user
  // confirms (or picks from the raw detected text) before anything is
  // looked up or saved.
  Uint8List? _frozenImage;
  bool _reviewingCapture = false;
  bool _ocrRunning = false;
  final _catalogController = TextEditingController();
  final _serialController = TextEditingController();
  final _catalogFocus = FocusNode();
  final _serialFocus = FocusNode();
  final _textRecognizer = TextRecognizer();
  List<String> _detectedLines = [];

  // Tracks which field to fill when a detected-text chip is tapped. Set via
  // focus-gained listeners rather than read live at tap time, because
  // tapping a Chip can itself steal focus from the text field first —
  // checking `.hasFocus` at that point would be unreliable.
  bool _lastFocusWasSerial = false;

  // Existing-product match — either a one-tap "log this unit" confirm
  // (when we captured a serial) or the bulk quantity stepper (when we
  // didn't, e.g. manual entry or a single-barcode label).
  Product? _matchedProduct;
  String? _pendingSerial;
  int _qty = 1;

  // Already-logged-this-unit notice.
  Product? _duplicateProduct;
  String? _duplicateSerial;

  bool _scanning = true; // actively feeding _latestFrame from the camera
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _catalogFocus.addListener(() {
      if (_catalogFocus.hasFocus) _lastFocusWasSerial = false;
    });
    _serialFocus.addListener(() {
      if (_serialFocus.hasFocus) _lastFocusWasSerial = true;
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _cameraController.dispose();
    _catalogController.dispose();
    _serialController.dispose();
    _catalogFocus.dispose();
    _serialFocus.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning) return;
    final image = capture.image;
    if (image != null) _latestFrame = image;
  }

  Future<void> _captureNow() async {
    final frame = _latestFrame;
    if (frame == null) return;

    setState(() => _scanning = false);
    await _cameraController.stop();
    if (!mounted) return;

    setState(() {
      _frozenImage = frame;
      _reviewingCapture = true;
      _ocrRunning = true;
      _catalogController.clear();
      _serialController.clear();
      _detectedLines = [];
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/stocktrack_scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(frame);
      final recognized = await _textRecognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      try {
        await file.delete();
      } catch (_) {
        // Best-effort cleanup only.
      }

      final lines = [
        for (final block in recognized.blocks)
          for (final line in block.lines) line.text.trim(),
      ].where((t) => t.isNotEmpty).toList();
      final guess = _guessCatalogAndSerial(recognized);

      if (mounted) {
        setState(() {
          _detectedLines = lines;
          if (guess.catalog != null) _catalogController.text = guess.catalog!;
          if (guess.serial != null) _serialController.text = guess.serial!;
        });
      }
    } catch (_) {
      // OCR is best-effort — fields just stay empty for manual entry if it
      // fails entirely (no camera/network dependency, so failure here is
      // rare, but nothing else in the flow should block on it).
    }

    if (!mounted) return;
    setState(() => _ocrRunning = false);
  }

  /// Fills whichever of the two fields was last focused (defaults to
  /// catalog) with a tapped line from the raw OCR output — a one-tap fix
  /// when the auto-guess picked the wrong text.
  void _applyDetectedLine(String text) {
    if (_lastFocusWasSerial) {
      _serialController.text = text;
    } else {
      _catalogController.text = text;
    }
  }

  Future<void> _confirmCapture() async {
    final catalog = _catalogController.text.trim();
    if (catalog.isEmpty) return;
    final serial = _serialController.text.trim();
    setState(() => _reviewingCapture = false);
    await _lookup(catalog, serial: serial.isEmpty ? null : serial);
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
    _reviewingCapture = false;
    _ocrRunning = false;
    _catalogController.clear();
    _serialController.clear();
    _detectedLines = [];
    _latestFrame = null;
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

    final showTorch =
        _matchedProduct == null &&
        !_reviewingCapture &&
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
            : _reviewingCapture
            ? _FrozenReview(
                image: _frozenImage,
                catalogController: _catalogController,
                serialController: _serialController,
                catalogFocus: _catalogFocus,
                serialFocus: _serialFocus,
                ocrRunning: _ocrRunning,
                detectedLines: _detectedLines,
                onSelectLine: _applyDetectedLine,
                onConfirm: _confirmCapture,
                onRetake: _resumeScanning,
              )
            : _ScannerView(
                cameraController: _cameraController,
                barcodeController: _barcodeController,
                onLookup: (code) => _lookup(code),
                onDetect: _onDetect,
                onCapture: _captureNow,
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
    required this.onCapture,
  });

  final MobileScannerController cameraController;
  final TextEditingController barcodeController;
  final ValueChanged<String> onLookup;
  final void Function(BarcodeCapture capture) onDetect;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text(
          'Frame the label so both numbers are readable, then tap Capture. Or enter a code manually below.',
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
                MobileScanner(controller: cameraController, onDetect: onDetect),
                // Framing guide only — purely visual, nothing is gated on it.
                Center(
                  child: Container(
                    width: 260,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.primaryBlue,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: onCapture,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          icon: const Icon(Icons.camera_alt),
          label: const Text(
            'Capture',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
            prefixIcon: const Icon(Icons.numbers, color: AppColors.textFaint),
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
    required this.catalogController,
    required this.serialController,
    required this.catalogFocus,
    required this.serialFocus,
    required this.ocrRunning,
    required this.detectedLines,
    required this.onSelectLine,
    required this.onConfirm,
    required this.onRetake,
  });

  final Uint8List? image;
  final TextEditingController catalogController;
  final TextEditingController serialController;
  final FocusNode catalogFocus;
  final FocusNode serialFocus;
  final bool ocrRunning;
  final List<String> detectedLines;
  final ValueChanged<String> onSelectLine;
  final VoidCallback onConfirm;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              SizedBox(
                height: 220,
                width: double.infinity,
                child: image != null
                    ? Image.memory(image!, fit: BoxFit.cover)
                    : Container(color: AppColors.surfaceAlt),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.inStockGreen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Captured',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (ocrRunning)
                Positioned.fill(
                  child: Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Reading label…',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          ocrRunning
              ? 'Reading the label…'
              : "Check these against the label — edit anything that's wrong.",
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: catalogController,
          focusNode: catalogFocus,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Catalog number'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: serialController,
          focusNode: serialFocus,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Serial number (optional)',
          ),
        ),
        if (detectedLines.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Detected on label — tap to use (fills whichever field you tapped last):',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final line in detectedLines)
                ActionChip(
                  label: Text(line),
                  backgroundColor: AppColors.surfaceAlt,
                  labelStyle: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  onPressed: () => onSelectLine(line),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: ocrRunning ? null : onConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.inStockGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          child: const Text(
            'Looks good — continue',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onRetake,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.surfaceBorder),
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('Retake'),
        ),
      ],
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
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value ?? 'Not detected',
          style: TextStyle(
            color: value != null ? AppColors.textPrimary : AppColors.textFaint,
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
          const Icon(Icons.info_outline, color: AppColors.lowOrange, size: 40),
          const SizedBox(height: 16),
          Text(
            'Already logged',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Serial $serial is already recorded on ${product.name}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
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
                    color: AppColors.textFaint,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                _ReadoutRow(label: 'Serial number', value: serial),
                const SizedBox(height: 8),
                Text(
                  'Current stock: ${product.quantity} ${product.unit}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
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
  late final _controller = TextEditingController(text: widget.qty.toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(int value) {
    final clamped = value.clamp(1, 9999);
    _controller.text = clamped.toString();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
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
                    color: AppColors.textFaint,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Current stock: ${p.quantity} ${p.unit}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
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
                icon: Icons.remove,
                onTap: () => _set(widget.qty - 1),
              ),
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
              _StepButton(icon: Icons.add, onTap: () => _set(widget.qty + 1)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'New total will be: ${p.quantity + widget.qty} ${p.unit}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
