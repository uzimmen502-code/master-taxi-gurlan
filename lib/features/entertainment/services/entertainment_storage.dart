import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// `entertainment/{videoId}.mp4` — админ юклайди.
class EntertainmentStorage {
  EntertainmentStorage({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Storage rules bilan mos (400 MB).
  static const int maxUploadBytes = 400 * 1024 * 1024;

  Future<String> uploadVideo({
    required String videoId,
    required Uint8List bytes,
    String contentType = 'video/mp4',
  }) async {
    if (bytes.length > maxUploadBytes) {
      throw Exception(
        'Видео жуда катта (макс. ${maxUploadBytes ~/ (1024 * 1024)} МБ).',
      );
    }
    final ref = _storage.ref('entertainment/$videoId.mp4');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  Future<String> downloadUrl(String storagePath) async {
    if (storagePath.isEmpty) return '';
    return _storage.ref(storagePath).getDownloadURL();
  }
}
