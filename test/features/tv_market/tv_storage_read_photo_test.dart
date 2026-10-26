import 'dart:io';

import 'package:ava_gurlan/features/tv_market/services/tv_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Янги маҳсулот» вебда «Сақлаб бўлмади» (эга, 2026-10-26): расм `dart:io File` билан ўқиларди — вебда ишламайди.
/// Энди `XFile` (вебда `blob:` манзилни ҳам ўқийди). VM'да — файл байтлари айнан ўқилади.
void main() {
  test('readPickedPhotoBytes файл байтларини ўзгаришсиз қайтаради', () async {
    final dir = await Directory.systemTemp.createTemp('ava_photo_');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/p.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 1, 2, 3]);
    expect(await TvStorageService.readPickedPhotoBytes(f.path), [0xFF, 0xD8, 0xFF, 1, 2, 3]);
  });

  test('uploadShopPhotos ичида dart:io File билан ўқиш қайтиб келмаган (вебда ишламайди)', () {
    final src = File('lib/features/tv_market/services/tv_storage_service.dart').readAsStringSync();
    final body = src.substring(src.indexOf('Future<List<String>> uploadShopPhotos('));
    expect(body.contains('File(path)'), isFalse);
    expect(body.contains('readPickedPhotoBytes(path)'), isTrue);
  });
}
