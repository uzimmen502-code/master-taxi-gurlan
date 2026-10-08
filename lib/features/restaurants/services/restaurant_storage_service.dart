// `restaurant_images/{restaurantId}/` остига расм юклаш — улгуржи
// (`WholesaleStorageService`) билан бир хил: сиқиш + jpeg, фақат йўл бошқа.
// Storage қоидаси: фақат ресторан а'зоси (`firestore.exists(members/{phone})`).

import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class RestaurantStorageService {
  RestaurantStorageService({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  /// `kind` — `logo` · `cover` · `item` (фақат файл номи учун).
  Future<String> uploadImage({
    required String restaurantId,
    required XFile image,
    String kind = 'item',
  }) async {
    if (restaurantId.isEmpty) throw ArgumentError('restaurantId is required');
    final bytes = await _compress(image, kind == 'item' ? 1080 : 1440);
    final name = '${kind}_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    final ref = _storage.ref().child('restaurant_images').child(restaurantId).child(name);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> deleteByUrl(String url) async {
    if (url.isEmpty) return;
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  Future<Uint8List> _compress(XFile file, int maxSide) async {
    if (kIsWeb || file.path.isEmpty) return file.readAsBytes();
    final outPath = p.join(p.dirname(file.path), 'rest_${_uuid.v4()}.jpg');
    final result = await FlutterImageCompress.compressAndGetFile(
      file.path,
      outPath,
      minWidth: maxSide,
      minHeight: maxSide,
      quality: 78,
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
