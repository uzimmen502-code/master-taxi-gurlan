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

  /// Cache chegarasi — telefon xotirasi to'lib ketmasligi uchun.
  /// Limitdan oshsa, eng eski (oxirgi ko'rilgan) videolar o'chiriladi.
  static const int maxCacheBytes = 1500 * 1024 * 1024; // ~1.5 GB

  Future<Directory> _cacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'entertainment_cache'));
    if (!cacheDir.existsSync()) await cacheDir.create(recursive: true);
    return cacheDir;
  }

  /// Joriy cache hajmi (bayt).
  Future<int> cacheSizeBytes() async {
    if (kIsWeb) return 0;
    final cacheDir = await _cacheDir();
    var total = 0;
    for (final f in cacheDir.listSync().whereType<File>()) {
      total += f.statSync().size;
    }
    return total;
  }

  /// Butun cache'ni tozalash.
  Future<void> clear() async {
    if (kIsWeb) return;
    final cacheDir = await _cacheDir();
    for (final f in cacheDir.listSync().whereType<File>()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// Limitdan oshsa — eng eski fayllardan boshlab o'chiramiz.
  Future<void> _prune() async {
    if (kIsWeb) return;
    final cacheDir = await _cacheDir();
    final files = cacheDir.listSync().whereType<File>().toList();
    var total = 0;
    for (final f in files) {
      total += f.statSync().size;
    }
    if (total <= maxCacheBytes) return;
    files.sort((a, b) =>
        a.statSync().modified.compareTo(b.statSync().modified));
    for (final f in files) {
      if (total <= maxCacheBytes) break;
      final sz = f.statSync().size;
      try {
        f.deleteSync();
        total -= sz;
      } catch (_) {}
    }
  }

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

    final cacheDir = await _cacheDir();
    final dest = File(p.join(cacheDir.path, '$videoId.mp4'));

    await _storage.ref(storagePath).writeToFile(dest);
    if (!dest.existsSync()) return null;
    // Yuklab bo'lgach — limitdan oshmasligini tekshiramiz.
    await _prune();
    return dest;
  }
}
