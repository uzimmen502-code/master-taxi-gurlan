import 'dart:io';

import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:flutter_test/flutter_test.dart';

TvClip _clip({String processingStatus = 'ready'}) => TvClip(
      id: 'c1',
      videoUrl: 'https://example.test/a.mp4',
      posterUrl: '',
      title: 'test',
      price: 0,
      districtId: 'd1',
      districtLabel: 'D',
      ownerPhone: '+998900000000',
      ownerName: 'Test',
      category: 'product',
      processingStatus: processingStatus,
    );

void main() {
  group('TvClip.isPlayable', () {
    test('transcode йиқилган клип — лентага чиқмайди', () {
      expect(_clip(processingStatus: 'error').isPlayable, isFalse);
    });

    test('ready — чиқади', () {
      expect(_clip(processingStatus: 'ready').isPlayable, isTrue);
    });

    test('processing — чиқади (вариант тайёр бўлгунча асл файл ўйнайди)', () {
      expect(_clip(processingStatus: 'processing').isPlayable, isTrue);
    });

    test('эски клип (майдон Firestore\'да йўқ) — default ready, чиқади', () {
      expect(_clip().isPlayable, isTrue);
    });
  });

  test('клиент ва сервердаги давомийлик чегараси мос', () {
    // Мослик бузилса фойдаланувчи огоҳлантирилмай қолади: сервер
    // кесади, клиент эса бошқа рақамни кўрсатади.
    final js = File('functions/index.js').readAsStringSync();
    final m = RegExp(r'const TV_CLIP_MAX_SECONDS = (\d+);').firstMatch(js);
    expect(m, isNotNull, reason: 'functions/index.js: TV_CLIP_MAX_SECONDS йўқ');
    expect(int.parse(m!.group(1)!), tvClipMaxUploadSeconds);
  });
}
