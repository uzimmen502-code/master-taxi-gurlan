import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Davra fotoalbomi — `circles/{circleId}/album/` ostiga siqilgan rasm yuklash.
class CircleAlbumStorage {
  CircleAlbumStorage({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  Future<({String url, String path})> uploadImage({
    required String circleId,
    required XFile image,
  }) async {
    final bytes = await _compress(image);
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    final path = 'circles/$circleId/album/$name';
    final ref = _storage.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return (url: await ref.getDownloadURL(), path: path);
  }

  Future<void> deleteByUrl(String url) async {
    if (url.isEmpty) return;
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  Future<Uint8List> _compress(XFile file) async {
    if (kIsWeb) return file.readAsBytes();
    final path = file.path;
    if (path.isEmpty) return file.readAsBytes();
    final outPath = p.join(p.dirname(path), 'circle_${_uuid.v4()}.jpg');
    final result = await FlutterImageCompress.compressAndGetFile(
      path,
      outPath,
      minWidth: 1280,
      minHeight: 1280,
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
