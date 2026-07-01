import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../harness/harness_config.g.dart';
import '../../dev_gate.dart';

/// Resolves report screenshots at SUBMIT time (nothing is touched while drafting, so
/// a discarded draft never orphans anything). Ported from Blueprint's
/// `ScreenshotUploadService`, retargeted to the Stock-Track reports layout.
///
/// STORAGE GATE (Storage is deliberately OFF in easy-stock-track for the first
/// proof): when [kHarnessStorageEnabled] is false, this NEVER attempts a Storage
/// upload — it returns LOCAL descriptors (`{localPath, bytes, contentType}`) so the
/// screenshot renders on-device and the report still files. When Storage is enabled
/// it uploads to:
///   `stockIssueReports/{uid}/{epochMillis}_{index}.{ext}`
/// returning `{url, path, bytes, contentType}` (`url` for the thumbnail, `path` for
/// the orchestrator's Admin-SDK download). If a live upload fails (e.g. Storage not
/// actually enabled), it degrades to the local descriptor rather than throwing — the
/// report is never lost to a Storage hiccup.
class ScreenshotUploadService {
  ScreenshotUploadService._();

  static Future<List<Map<String, dynamic>>> upload(
    List<XFile> images, {
    required String uid,
    FirebaseStorage? storage,
  }) async {
    if (images.isEmpty) return const <Map<String, dynamic>>[];
    if (uid.isEmpty) {
      throw StateError('Not signed in — cannot resolve screenshots.');
    }
    final millis = DateTime.now().millisecondsSinceEpoch;
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final Uint8List data = await image.readAsBytes();
      final contentType = _contentTypeFor(image);

      if (!kHarnessStorageEnabled) {
        out.add(_localDescriptor(image, data, contentType));
        continue;
      }
      try {
        final store = storage ?? FirebaseStorage.instance;
        final ext = _extFor(contentType);
        // Config-driven collection prefix — a framework module must not hardcode an
        // app-specific collection name (matches the chat upload path).
        final path =
            '${HarnessConfig.reportsCollection}/$uid/${millis}_$i.$ext';
        final ref = store.ref(path);
        await ref.putData(data, SettableMetadata(contentType: contentType));
        final url = await ref.getDownloadURL();
        out.add(<String, dynamic>{
          'url': url,
          'path': path,
          'bytes': data.length,
          'contentType': contentType,
        });
      } catch (e) {
        // Storage enabled in the flag but not actually reachable → don't lose the
        // report; keep the local descriptor + a marker.
        debugPrint('[screenshot_upload] falling back to local: $e');
        out.add(_localDescriptor(image, data, contentType));
      }
    }
    return out;
  }

  static Map<String, dynamic> _localDescriptor(
    XFile image,
    Uint8List data,
    String contentType,
  ) => <String, dynamic>{
    'localPath': image.path,
    'bytes': data.length,
    'contentType': contentType,
    'storageOff': true,
  };

  static String _contentTypeFor(XFile image) {
    final mime = image.mimeType;
    if (mime != null && mime.startsWith('image/')) return mime;
    final name = image.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static String _extFor(String contentType) {
    switch (contentType) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'jpg';
    }
  }
}
