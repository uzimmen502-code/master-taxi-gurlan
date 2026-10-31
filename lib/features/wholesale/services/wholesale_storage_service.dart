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

  /// 3b: Storage қоидаси — фақат расм ва 8 МБ дан кичик.
  static const maxReceiptBytes = 8 * 1024 * 1024;

  /// 3b: карта буюртмасида харидорнинг ўтказма чеки —
  /// `wholesale_receipts/{buyerPhone}/{orderId}/{file}` (Storage қоидаси ва сервер
  /// `parseReceiptPath` шу шаклни талаб қилади). URL эмас, Storage ЙЎЛИ қайтади:
  /// у `submitWholesaleCardReceipt` га берилади; сотувчи чекни сервер ёзган
  /// `cardPayment.receiptUrl` орқали кўради (унда Storage ўқиш ҳуқуқи йўқ).
  /// Ҳажм ошса — [ReceiptTooLargeException] (юклашдан олдин).
  Future<String> uploadReceipt({
    required String buyerId,
    required String orderId,
    required XFile image,
  }) async {
    if (buyerId.isEmpty || orderId.isEmpty) throw ArgumentError('buyerId/orderId is required');
    final bytes = await _compress(image);
    if (bytes.length >= maxReceiptBytes) throw const ReceiptTooLargeException();
    final name = '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    final ref = _storage.ref().child('wholesale_receipts').child(buyerId).child(orderId).child(name);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.fullPath;
  }

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

/// Чек файли Storage чегарасидан (8 МБ) катта.
class ReceiptTooLargeException implements Exception {
  const ReceiptTooLargeException();
}
