import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Tanishuv profil fotosi — `dating/{uid}/` ostiga siqilgan rasm yuklash.
class DatingPhotoStorage {
  DatingPhotoStorage({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  Future<({String url, String path})> upload({
    required String userId,
    required XFile image,
  }) async {
    final bytes = await _compress(image);
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    final path = 'dating/$userId/$name';
    final ref = _storage.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return (url: await ref.getDownloadURL(), path: path);
  }

  Future<void> deleteByPath(String path) async {
    if (path.isEmpty) return;
    try {
      await _storage.ref().child(path).delete();
    } catch (_) {}
  }

  Future<Uint8List> _compress(XFile file) async {
    if (kIsWeb) return file.readAsBytes();
    final path = file.path;
    if (path.isEmpty) return file.readAsBytes();
    final outPath = p.join(p.dirname(path), 'dating_${_uuid.v4()}.jpg');
    final result = await FlutterImageCompress.compressAndGetFile(
      path,
      outPath,
      minWidth: 1080,
      minHeight: 1080,
      quality: 72,
      format: CompressFormat.jpeg,
    );
    if (result == null) return File(path).readAsBytesSync();
    final bytes = await File(result.path).readAsBytes();
    try {
      await File(result.path).delete();
    } catch (_) {}
    return bytes;
  }
}
