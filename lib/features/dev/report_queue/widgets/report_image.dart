import 'dart:io';

import 'package:flutter/material.dart';

import 'report_common.dart';

/// Renders a report screenshot from either a remote URL (uploaded to Storage) or a
/// LOCAL file path (Storage-off / mock capture, rendered on-device), falling back to
/// a placeholder when neither loads.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic; it just picks the right
/// loader for a source string.
class ReportImage extends StatelessWidget {
  const ReportImage(
    this.source, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;

  bool get _isRemote => source.startsWith('http');

  @override
  Widget build(BuildContext context) {
    if (_isRemote) {
      return Image.network(
        source,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (c, child, p) => p == null ? child : _placeholder(),
      );
    }
    final file = File(source);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => SizedBox(
    width: width,
    height: height,
    child: const ReportThumbPlaceholder(),
  );
}

/// Full-screen, pinch-to-zoom gallery over a report's screenshots. Reading a bug
/// screenshot on a phone requires zoom.
Future<void> showScreenshotGallery(
  BuildContext context, {
  required List<String> sources,
  int initialIndex = 0,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          _ScreenshotGallery(sources: sources, initialIndex: initialIndex),
    ),
  );
}

class _ScreenshotGallery extends StatelessWidget {
  const _ScreenshotGallery({required this.sources, required this.initialIndex});

  final List<String> sources;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final controller = PageController(initialPage: initialIndex);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${sources.length} screenshot${sources.length == 1 ? '' : 's'}',
        ),
      ),
      body: PageView.builder(
        controller: controller,
        itemCount: sources.length,
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Center(child: ReportImage(sources[i], fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
