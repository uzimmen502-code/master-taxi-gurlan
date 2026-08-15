import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// TV Market видеолари учун Storage upload.
class TvStorageService {
  TvStorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  /// Видео юклаш → download URL.
  /// [onProgress] 0.0..1.0 жараён.
  Future<String> uploadVideo({
    required String ownerPhone,
    required String filePath,
    void Function(double progress)? onProgress,
  }) async {
    final ext = filePath.split('.').last.toLowerCase();
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.$ext';
    final ref =
        _storage.ref().child('tv_clips').child(ownerPhone).child(name);

    final task = ref.putFile(
      File(filePath),
      SettableMetadata(contentType: 'video/$ext'),
    );

    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          onProgress(snap.bytesTransferred / snap.totalBytes);
        }
      });
    }

    await task;
    return ref.getDownloadURL();
  }

  /// Постер расм юклаш (thumbnail).
  Future<String> uploadPoster({
    required String ownerPhone,
    required Uint8List bytes,
  }) async {
    final name =
        'poster_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    final ref =
        _storage.ref().child('tv_clips').child(ownerPhone).child(name);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
