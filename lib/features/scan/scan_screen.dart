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

// (?:NO\.?|NUM(?:BER)?|#) — "NUM" alone would partially match inside the
// full word "NUMBER" and then fail the trailing \b mid-word, leaving
// "BER" (or worse, "Number: 12345" once a same-line value follows) stuck
// to the caption match. Spelling out NUM(?:BER)? avoids that dangling
// partial match entirely.
final _catalogLabelPattern = RegExp(
  r'\b(CAT(?:ALOG)?\.?\s*(?:NO\.?|NUM(?:BER)?|#)?|MODEL\.?\s*(?:NO\.?|NUM(?:BER)?|#)?|P\s*/\s*N|PART\.?\s*(?:NO\.?|NUM(?:BER)?|#)?)\b\.?\s*[:\-]?',
  caseSensitive: false,
);
final _serialLabelPattern = RegExp(
  r'\b(S\s*/\s*N|SERIAL\.?\s*(?:NO\.?|NUM(?:BER)?|#)?)\b\.?\s*[:\-]?',
  caseSensitive: false,
);

/// A plausible catalog/serial value has to actually contain a digit — real
/// part/model/serial numbers always do. This is what rules out a caption
/// like "CATALOG NUMBER" (or a stray leftover word fragment from matching
/// the caption pattern against it) from ever being mistaken for the value
/// itself.
final _looksLikeValue = RegExp(r'\d');

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

      // Caption and value on the same line (e.g. "MODEL NO: ABC123") — but
      // only trust it if what's left after the caption actually looks like
      // a number, not a leftover word fragment from a caption-only line
      // like "CATALOG NUMBER".
      final sameLineValue = captionText.substring(match.end).trim();
      if (sameLineValue.isNotEmpty && _looksLikeValue.hasMatch(sameLineValue)) {
        return sameLineValue;
      }

      // Otherwise, find the closest line that sits below this caption,
      // roughly lines up with it horizontally (allowing generous slack,
      // since the value is centered under a barcode that may be a
      // different width than the caption text above it), and actually
      // looks like a number rather than another caption/label word.
      final captionBox = captionLine.boundingBox;
      TextLine? best;
      double bestGap = double.infinity;
      for (final candidate in lines) {
        if (identical(candidate, captionLine)) continue;
        final candidateText = candidate.text.trim();
        if (!_looksLikeValue.hasMatch(candidateText)) continue;
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
      if (best != null) return best.text.trim();
    }
    return null;
  }

  return _OcrGuess(
    catalog: findValue(_catalogLabelPattern),
    serial: findValue(_serialLabelPattern),
  );
}

/// A rough score for how much a detected line "looks like" a part/model/
/// serial number rather than an incidental digit inside a sentence —
/// favors short, alphanumeric-dense strings. Used to rank the dropdown
/// options offered for each field.
double _valueLikelihoodScore(String s) {
  if (s.isEmpty) return 0;
  final alnum = RegExp(r'[A-Za-z0-9]').allMatches(s).length;
  final digits = RegExp(r'[0-9]').allMatches(s).length;
  final density = alnum / s.length;
  final digitRatio = digits / s.length;
  final lengthPenalty = s.length > 24 ? 0.4 : 1.0;
  return (density * 0.5 + digitRatio * 0.5) * lengthPenalty;
}

/// Every detected line that contains a digit (so could plausibly be a
/// part/model/serial number), deduplicated and ranked best-first.
List<String> _numericCandidates(RecognizedText text) {
  final seen = <String>{};
  final candidates = <String>[];
  for (final block in text.blocks) {
    for (final line in block.lines) {
      final t = line.text.trim();
      if (t.isEmpty || !_looksLikeValue.hasMatch(t)) continue;
      if (seen.add(t)) candidates.add(t);
    }
  }
  candidates.sort(
    (a, b) => _valueLikelihoodScore(b).compareTo(_valueLikelihoodScore(a)),
  );
  return candidates;
}

/// Digit-containing lines ranked by on-image size (tallest bounding box
/// first) — a proxy for font size / visual prominence. The catalog number
/// is often simply the biggest writing on the label, not something with an
/// explicit "CATALOG #" caption next to it, so this is used as the primary
/// signal for catalog specifically (serial numbers are reliably captioned
/// with "S/N"/"Serial No." so the caption-based guess stays primary there).
List<String> _sizeRankedCandidates(RecognizedText text) {
  final seen = <String>{};
  final entries = <MapEntry<String, double>>[];
  for (final block in text.blocks) {
    for (final line in block.lines) {
      final t = line.text.trim();
      if (t.isEmpty || !_looksLikeValue.hasMatch(t)) continue;
      if (seen.add(t)) entries.add(MapEntry(t, line.boundingBox.height));
    }
  }
  entries.sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in entries) e.key];
}

/// Up to [max] dropdown options for a field: the heuristic's guess first
/// (if any), then other plausible numeric candidates found on the label.
List<String> _buildOptions(String? guess, List<String> pool, {int max = 4}) {
  final options = <String>[];
  if (guess != null && guess.isNotEmpty) options.add(guess);
  for (final c in pool) {
    if (options.length >= max) break;
    if (options.contains(c)) continue;
    options.add(c);
  }
  return options;
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
  // each a dropdown of up to 4 plausible numbers found on the label (the
  // heuristic's guess first, then other numeric-looking candidates) — the
  // user picks the right one instead of typing. If OCR found no numeric
  // candidates at all for a field, options is empty and the corresponding
  // controller becomes a plain manual-entry fallback.
  Uint8List? _frozenImage;
  bool _reviewingCapture = false;
  bool _ocrRunning = false;
  final _catalogController = TextEditingController();
  final _serialController = TextEditingController();
  final _textRecognizer = TextRecognizer();
  List<String> _catalogOptions = [];
  List<String> _serialOptions = [];
  String? _selectedCatalog;
  String? _selectedSerial;

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
  void dispose() {
    _barcodeController.dispose();
    _cameraController.dispose();
    _catalogController.dispose();
    _serialController.dispose();
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
      _catalogOptions = [];
      _serialOptions = [];
      _selectedCatalog = null;
      _selectedSerial = null;
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

      final guess = _guessCatalogAndSerial(recognized);
      final pool = _numericCandidates(recognized);
      final bySize = _sizeRankedCandidates(recognized);

      // Catalog: default to the largest writing on the label, then offer
      // the caption-based guess and other candidates as alternates.
      final catalogOptions = _buildOptions(
        bySize.firstOrNull ?? guess.catalog,
        [...bySize, if (guess.catalog != null) guess.catalog!, ...pool],
      );
      // Serial: captions like "S/N"/"Serial No." are reliable, keep that
      // as the primary signal.
      final serialOptions = _buildOptions(guess.serial, pool);

      if (mounted) {
        setState(() {
          _catalogOptions = catalogOptions;
          _serialOptions = serialOptions;
          _selectedCatalog = catalogOptions.firstOrNull;
          _selectedSerial = serialOptions.firstOrNull;
          _catalogController.text = _selectedCatalog ?? '';
          _serialController.text = _selectedSerial ?? '';
        });
      }
    } catch (_) {
      // OCR is best-effort — options stay empty, falling back to manual
      // entry, if it fails entirely (no camera/network dependency, so
      // failure here is rare, but nothing else should block on it).
    }

    if (!mounted) return;
    setState(() => _ocrRunning = false);
  }

  void _onCatalogSelected(String? value) {
    setState(() {
      _selectedCatalog = value;
      _catalogController.text = value ?? '';
    });
  }

  void _onSerialSelected(String? value) {
    setState(() {
      _selectedSerial = value;
      _serialController.text = value ?? '';
    });
  }

  Future<void> _confirmCapture() async {
    final catalog =
        (_catalogOptions.isEmpty
                ? _catalogController.text
                : (_selectedCatalog ?? ''))
            .trim();
    if (catalog.isEmpty) return;
    final serial =
        (_serialOptions.isEmpty
                ? _serialController.text
                : (_selectedSerial ?? ''))
            .trim();
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
    _catalogOptions = [];
    _serialOptions = [];
    _selectedCatalog = null;
    _selectedSerial = null;
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
                catalogOptions: _catalogOptions,
                serialOptions: _serialOptions,
                selectedCatalog: _selectedCatalog,
                selectedSerial: _selectedSerial,
                onCatalogSelected: _onCatalogSelected,
                onSerialSelected: _onSerialSelected,
                ocrRunning: _ocrRunning,
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
    required this.catalogOptions,
    required this.serialOptions,
    required this.selectedCatalog,
    required this.selectedSerial,
    required this.onCatalogSelected,
    required this.onSerialSelected,
    required this.ocrRunning,
    required this.onConfirm,
    required this.onRetake,
  });

  final Uint8List? image;
  final TextEditingController catalogController;
  final TextEditingController serialController;
  final List<String> catalogOptions;
  final List<String> serialOptions;
  final String? selectedCatalog;
  final String? selectedSerial;
  final ValueChanged<String?> onCatalogSelected;
  final ValueChanged<String?> onSerialSelected;
  final bool ocrRunning;
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
              : 'Pick the right number for each field — or type it in if none match.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _NumberPicker(
          label: 'Catalog number',
          options: catalogOptions,
          selected: selectedCatalog,
          controller: catalogController,
          onSelected: onCatalogSelected,
        ),
        const SizedBox(height: 12),
        _NumberPicker(
          label: 'Serial number (optional)',
          options: serialOptions,
          selected: selectedSerial,
          controller: serialController,
          onSelected: onSerialSelected,
        ),
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

/// A dropdown of up to 4 plausible values for a field. Falls back to a
/// plain text field when OCR found no numeric candidates at all, so a
/// label OCR can't read isn't a dead end.
class _NumberPicker extends StatelessWidget {
  const _NumberPicker({
    required this.label,
    required this.options,
    required this.selected,
    required this.controller,
    required this.onSelected,
  });

  final String label;
  final List<String> options;
  final String? selected;
  final TextEditingController controller;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return TextField(
        controller: controller,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          helperText: 'No numbers detected — enter manually',
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: options.contains(selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: onSelected,
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
