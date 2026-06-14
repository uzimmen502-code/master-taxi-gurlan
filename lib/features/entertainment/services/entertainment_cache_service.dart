import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Йўловчи offline tomoshа — MP4 ni mahalliy cache.
class EntertainmentCacheService {
  EntertainmentCacheService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<File?> localFile(String videoId) async {
    if (kIsWeb || videoId.isEmpty) return null;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'entertainment_cache', '$videoId.mp4'));
    return file.existsSync() ? file : null;
  }

  Future<bool> isCached(String videoId) async {
    final f = await localFile(videoId);
    return f != null;
  }

  Future<File?> download({
    required String videoId,
    required String storagePath,
  }) async {
    if (kIsWeb || storagePath.isEmpty) return null;
    final existing = await localFile(videoId);
    if (existing != null) return existing;

    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'entertainment_cache'));
    if (!cacheDir.existsSync()) await cacheDir.create(recursive: true);
    final dest = File(p.join(cacheDir.path, '$videoId.mp4'));

    await _storage.ref(storagePath).writeToFile(dest);
    return dest.existsSync() ? dest : null;
  }
}
