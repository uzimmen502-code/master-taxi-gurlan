import 'dart:io';

import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

TvClip _clip({
  String processingStatus = 'ready',
  Map<String, String> variants = const {},
  String hlsUrl = '',
}) =>
    TvClip(
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
      videoVariants: variants,
      hlsUrl: hlsUrl,
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

  group('TvClip.mp4Url — админ панели ва соцсет учун', () {
    test('480p бор — ўша олинади (енгилроқ)', () {
      final c = _clip(variants: {
        '480p': 'https://example.test/480.mp4',
        '720p': 'https://example.test/720.mp4',
      });
      expect(c.mp4Url, 'https://example.test/480.mp4');
    });

    test('фақат 720p бор — ўша', () {
      final c = _clip(variants: {'720p': 'https://example.test/720.mp4'});
      expect(c.mp4Url, 'https://example.test/720.mp4');
    });

    test('эски клип, варианти йўқ — асл видеога қайтади', () {
      expect(_clip().mp4Url, 'https://example.test/a.mp4');
    });
  });

  group('urlForQuality — HLS устунлиги', () {
    const hls = 'https://example.test/hls/master.m3u8';

    test('HLS бор — сифатдан қатъи назар ўша (ABR плеернинг иши)', () {
      final c = _clip(
        hlsUrl: hls,
        variants: {
          '480p': 'https://example.test/480.mp4',
          '720p': 'https://example.test/720.mp4',
        },
      );
      expect(c.urlForQuality('720p'), hls);
      expect(c.urlForQuality('480p'), hls);
    });

    test('HLS йўқ (эски клип) — сўралган MP4 варианти', () {
      final c = _clip(variants: {'720p': 'https://example.test/720.mp4'});
      expect(c.urlForQuality('720p'), 'https://example.test/720.mp4');
    });

    test('на HLS, на вариант — асл файлга қайтади', () {
      expect(_clip().urlForQuality('720p'), 'https://example.test/a.mp4');
    });

    test('mp4Url HLS бор бўлса ҳам ҳеч қачон playlist қайтармайди', () {
      final c = _clip(
        hlsUrl: hls,
        variants: {'480p': 'https://example.test/480.mp4'},
      );
      expect(c.mp4Url, 'https://example.test/480.mp4');
    });
  });

  group('TvClipCacheService.isHlsUrl', () {
    test('m3u8 — кэшланмайди', () {
      expect(
        TvClipCacheService.isHlsUrl('https://example.test/hls/master.m3u8'),
        isTrue,
      );
    });

    test('Firebase token\'ли m3u8 ҳам аниқланади', () {
      expect(
        TvClipCacheService.isHlsUrl(
          'https://firebasestorage.googleapis.com/v0/b/x/o/'
          'tv_clip_hls%2Fc1%2Fmaster.m3u8?alt=media&token=abc',
        ),
        isTrue,
      );
    });

    test('mp4 — кэшланади', () {
      expect(
        TvClipCacheService.isHlsUrl('https://example.test/720.mp4?token=a'),
        isFalse,
      );
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
