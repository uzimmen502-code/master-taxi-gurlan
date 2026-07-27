import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Админ web учун: нон расмини `bread_images/{id}.jpg` (ёки kengaytma)га юклайди.
class BreadImageStorage {
  BreadImageStorage({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// [docId] — `bread_products` ҳужжат ID (ёки вақтинча UUID).
  Future<String> uploadBreadProductImage({
    required String docId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ext = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
            ? 'webp'
            : 'jpg';
    final ref = _storage.ref('bread_images/$docId.$ext');
    await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  /// Таом расми (`food_images/`).
  Future<String> uploadFoodImage({
    required String docId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ext = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
            ? 'webp'
            : 'jpg';
    final ref = _storage.ref('food_images/$docId.$ext');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  /// Қўшимча маҳсулот расми (`extra_images/`).
  Future<String> uploadExtraImage({
    required String docId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ext = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
            ? 'webp'
            : 'jpg';
    final ref = _storage.ref('extra_images/$docId.$ext');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  /// Мой/фильтр каталог расми (`oil_images/`).
  Future<String> uploadOilImage({
    required String docId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ext = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
            ? 'webp'
            : 'jpg';
    final ref = _storage.ref('oil_images/$docId.$ext');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  /// Платформа дўкони расми (`platform_images/`).
  /// [index] берилса файл номи уникал бўлади (кўп расм).
  Future<String> uploadPlatformImage({
    required String docId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    int? index,
  }) async {
    final ext = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
            ? 'webp'
            : 'jpg';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = index == null
        ? 'platform_images/$docId.$ext'
        : 'platform_images/${docId}_${index}_$stamp.$ext';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }
}
