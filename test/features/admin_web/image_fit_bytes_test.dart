import 'dart:typed_data';

import 'package:ava_gurlan/features/admin_web/utils/image_fit_bytes.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad_prefetcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга 2026-11-28: админ splash креативи клиент кеши чегарасигача (1500 КБ) сиқилади.
void main() {
  const max = SplashAdPrefetcher.maxImageBytes;
  Uint8List bytes(int n) => Uint8List(n);

  test('чегара клиент кеши билан бир хил (1500 КБ)', () => expect(max, 1500 * 1024));

  test('сиғса — аслиси (формат сақланади), кодловчи чақирилмайди', () async {
    var calls = 0;
    final r = await fitImageToMaxBytes(bytes(max), maxBytes: max, mimeHint: 'image/png', encode: (_, __) async {
      calls++;
      return null;
    });
    expect([r!.bytes.length, r.mime, calls], [max, 'image/png', 0]);
  });

  test('катта — поғонама-поғона, биринчи сиққан JPEG; ҳаммаси ≤ 1500 КБ', () async {
    final tried = <(int, double)>[];
    final r = await fitImageToMaxBytes(bytes(6 * 1024 * 1024), maxBytes: max, encode: (e, q) async {
      tried.add((e, q));
      return bytes(e >= 1440 ? max + 1 : max - 10);
    });
    expect(r!.mime, 'image/jpeg');
    expect(r.bytes.length, lessThanOrEqualTo(max));
    expect(tried.map((x) => x.$1), [1600, 1440, 1280]);
  });

  test('ҳеч бири сиғмаса / кодлаш хатоси — null (юкланмайди)', () async {
    expect(await fitImageToMaxBytes(bytes(max + 1), maxBytes: max, encode: (_, __) async => bytes(max + 1)), isNull);
    expect(await fitImageToMaxBytes(bytes(max + 1), maxBytes: max, encode: (_, __) async => throw StateError('x')), isNull);
    expect(await fitImageToMaxBytes(Uint8List(0), maxBytes: max, encode: (_, __) async => null), isNull);
  });
}