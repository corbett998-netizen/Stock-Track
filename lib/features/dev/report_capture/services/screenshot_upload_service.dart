import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Uploads report screenshots to Firebase Storage at SUBMIT time (nothing uploads
/// while drafting, so a discarded draft never orphans a Storage object). Ported
/// from Blueprint's `ScreenshotUploadService`, retargeted to the Stock-Track
/// reports layout in easy-stock-track.
///
/// Layout (mirrors the strict `storage.rules`):
///   `stockIssueReports/{uid}/{epochMillis}_{index}.{ext}`
/// where `{uid}` is the signed-in anonymous UID (so the per-user rule passes —
/// same uid the `stockIssueReports` Firestore doc is keyed on).
///
/// Returns one map per image: `{url, path, bytes, contentType}` — `url` for the
/// in-app thumbnail, `path` for the orchestrator's Admin-SDK download.
class ScreenshotUploadService {
  ScreenshotUploadService._();

  static Future<List<Map<String, dynamic>>> upload(
    List<XFile> images, {
    required String uid,
    FirebaseStorage? storage,
  }) async {
    if (images.isEmpty) return const <Map<String, dynamic>>[];
    if (uid.isEmpty) {
      throw StateError('Not signed in — cannot upload screenshots.');
    }
    final store = storage ?? FirebaseStorage.instance;
    final millis = DateTime.now().millisecondsSinceEpoch;
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final Uint8List data = await image.readAsBytes();
      final contentType = _contentTypeFor(image);
      final ext = _extFor(contentType);
      final path = 'stockIssueReports/$uid/${millis}_$i.$ext';
      final ref = store.ref(path);
      await ref.putData(data, SettableMetadata(contentType: contentType));
      final url = await ref.getDownloadURL();
      out.add(<String, dynamic>{
        'url': url,
        'path': path,
        'bytes': data.length,
        'contentType': contentType,
      });
    }
    return out;
  }

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
