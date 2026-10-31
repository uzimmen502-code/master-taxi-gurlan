import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// `wholesale_products/{sellerId}/` остига расм юклаш/ўчириш —
/// `AdsStorageService`нинг айнан ўзи, фақат Storage йўли алоҳида.
class WholesaleStorageService {
  WholesaleStorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  Future<List<String>> uploadImages({
    required String sellerId,
    required List<XFile> images,
  }) async {
    if (sellerId.isEmpty) {
      throw ArgumentError('sellerId is required');
    }
    final urls = <String>[];
    for (final file in images) {
      final bytes = await _compress(file);
      final name =
          '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
      final ref =
          _storage.ref().child('wholesale_products').child(sellerId).child(name);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  /// 3b: карта буюртмасида харидорнинг ўтказма чеки —
  /// `wholesale_receipts/{buyerPhone}/{file}`. URL эмас, Storage ЙЎЛИ
  /// қайтади: у `submitWholesaleCardReceipt` га берилади (сервер йўл
  /// харидорники эканини текширади).
  Future<String> uploadReceipt({required String buyerId, required XFile image}) async {
    if (buyerId.isEmpty) throw ArgumentError('buyerId is required');
    final bytes = await _compress(image);
    final name = '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    final ref = _storage.ref().child('wholesale_receipts').child(buyerId).child(name);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.fullPath;
  }

  /// Чек расмини кўрсатиш учун URL (Storage rules сотувчига ўқишни бериши шарт).
  Future<String> downloadUrlForPath(String path) => _storage.ref(path).getDownloadURL();

  Future<void> deleteImages(List<String> imageUrls) async {
    for (final url in imageUrls) {
      try {
        await _storage.refFromURL(url).delete();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  Future<Uint8List> _compress(XFile file) async {
    if (kIsWeb) {
      return file.readAsBytes();
    }
    final path = file.path;
    if (path.isEmpty) {
      return file.readAsBytes();
    }
    final outPath = p.join(
      p.dirname(path),
      'compressed_${_uuid.v4()}.jpg',
    );
    final result = await FlutterImageCompress.compressAndGetFile(
      path,
      outPath,
      minWidth: 1080,
      minHeight: 1080,
      quality: 75,
      format: CompressFormat.jpeg,
    );
    if (result == null) {
      return File(path).readAsBytesSync();
    }
    final bytes = await File(result.path).readAsBytes();
    try {
      await File(result.path).delete();
    } catch (_) {}
    return bytes;
  }
}
