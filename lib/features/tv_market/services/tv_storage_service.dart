import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';

import '../models/tv_shop.dart';

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

  /// Видео ва постерни Storage'дан ўчириш (йўқ файл хатосини ютади).
  Future<void> deleteClipFiles({
    required String videoUrl,
    required String posterUrl,
  }) async {
    Future<void> one(String url) async {
      if (url.isEmpty) return;
      try {
        await _storage.refFromURL(url).delete();
      } catch (e) {
        debugPrint('[TvStorage] delete $e');
      }
    }

    await one(videoUrl);
    await one(posterUrl);
  }

  /// Витрина товар расми — `tv_shop/{ownerPhone}/`.
  Future<String> uploadShopPhoto({
    required String ownerPhone,
    required Uint8List bytes,
  }) async {
    final name =
        'item_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    final ref =
        _storage.ref().child('tv_shop').child(ownerPhone).child(name);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<Uint8List> compressShopPhoto(Uint8List photoBytes) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        photoBytes,
        quality: 78,
        minWidth: 1080,
        minHeight: 1080,
      );
      if (compressed.isNotEmpty) return Uint8List.fromList(compressed);
    } catch (e) {
      debugPrint('[TvStorage] compress $e');
    }
    return photoBytes;
  }

  /// 1–5 та дўкон расми. Тартиб сақланади.
  Future<List<String>> uploadShopPhotos({
    required String ownerPhone,
    required List<String> filePaths,
  }) async {
    final urls = <String>[];
    for (final path in filePaths.take(TvShopItem.maxPhotos)) {
      var bytes = await File(path).readAsBytes();
      bytes = await compressShopPhoto(bytes);
      urls.add(await uploadShopPhoto(ownerPhone: ownerPhone, bytes: bytes));
    }
    return urls;
  }
}
