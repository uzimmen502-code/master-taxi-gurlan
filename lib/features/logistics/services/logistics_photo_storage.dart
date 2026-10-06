import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Handover далил расмлари — `logistics/{uploaderId}/{fileName}`.
///
/// Сервер (`scanHandover`, `confirmDelivery`) расмни МАЖБУРИЙ талаб
/// қилади (relay ҳужжати 7.4, 3-қадам). Йўл юкловчининг ўз телефон
/// папкаси — `storage.rules`даги `ads/` қоидаси билан бир хил шарт
/// (эгалик, ≤8MB, фақат расм). Сиқиш — `AdsStorageService` билан бир хил.
class LogisticsPhotoStorage {
  LogisticsPhotoStorage({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  Future<List<String>> uploadHandoverPhotos({
    required String uploaderId,
    required String shipmentId,
    required List<XFile> images,
  }) async {
    if (uploaderId.isEmpty) throw ArgumentError('uploaderId is required');
    final urls = <String>[];
    try {
      for (final file in images) {
        final bytes = await _compress(file);
        final name = '${shipmentId}_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 6)}.jpg';
        final ref = _storage.ref().child('logistics').child(uploaderId).child(name);
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        urls.add(await ref.getDownloadURL());
      }
    } catch (_) {
      for (final url in urls) {
        try {
          await _storage.refFromURL(url).delete();
        } catch (_) {}
      }
      rethrow;
    }
    return urls;
  }

  Future<Uint8List> _compress(XFile file) async {
    if (kIsWeb || file.path.isEmpty) return file.readAsBytes();
    final outPath = p.join(p.dirname(file.path), 'logistics_${_uuid.v4()}.jpg');
    final result = await FlutterImageCompress.compressAndGetFile(
      file.path,
      outPath,
      minWidth: 1280,
      minHeight: 1280,
      quality: 75,
      format: CompressFormat.jpeg,
    );
    if (result == null) return File(file.path).readAsBytes();
    final bytes = await File(result.path).readAsBytes();
    try {
      await File(result.path).delete();
    } catch (_) {}
    return bytes;
  }
}
