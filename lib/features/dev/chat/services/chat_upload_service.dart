import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../harness/harness_config.g.dart';
import '../../dev_gate.dart';

/// Resolves a staged chat image to the source string a message carries.
///
/// STORAGE GATE (Storage is deliberately OFF in easy-stock-track for the first
/// proof): when [kHarnessStorageEnabled] is false, this NEVER attempts an upload —
/// it returns the LOCAL file path (rendered on-device this session; fully usable in
/// mock mode). When Storage is enabled it uploads to:
///   `orchestratorChat/{uid}/media/{epochMillis}.{ext}`
/// and returns the download URL. A live-upload failure degrades to the local path
/// rather than throwing.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic; the media path prefix
/// comes from `HarnessConfig.chatRoot` (config), never a literal.
class ChatUploadService {
  ChatUploadService._();

  static Future<String?> resolve(
    XFile? image, {
    required String uid,
    FirebaseStorage? storage,
  }) async {
    if (image == null) return null;
    if (!kHarnessStorageEnabled) return image.path;
    try {
      final data = await image.readAsBytes();
      final contentType = _contentTypeFor(image);
      final ext = _extFor(contentType);
      final path =
          '${HarnessConfig.chatRoot}/$uid/media/'
          '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final ref = (storage ?? FirebaseStorage.instance).ref(path);
      await ref.putData(data, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('[chat_upload] falling back to local: $e');
      return image.path;
    }
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
