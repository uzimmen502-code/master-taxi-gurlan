import 'dart:io';

import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_cache_service.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/server_checkout.dart';

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
    test('360p бор — энг енгили олинади', () {
      final c = _clip(variants: {
        '360p': 'https://example.test/360.mp4',
        '480p': 'https://example.test/480.mp4',
        '720p': 'https://example.test/720.mp4',
      });
      expect(c.mp4Url, 'https://example.test/360.mp4');
    });

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

  group('TvClipCompress.trimToSeconds — юклашдан олдинги кесиш', () {
    // Чегарага НИСБИЙ: `tvClipMaxUploadSeconds` ўзгарса бу тестлар
    // ўзгаришсиз ишлайверади.
    const cap = tvClipMaxUploadSeconds;

    test('чегарадан калта — кесилмайди', () {
      expect(TvClipCompress.trimToSeconds(1000), isNull);
      expect(TvClipCompress.trimToSeconds((cap - 1) * 1000), isNull);
    });

    test('чегаранинг ўзи — кесилмайди', () {
      expect(TvClipCompress.trimToSeconds(cap * 1000), isNull);
    });

    test('чегарадан узун — чегарагача кесилади', () {
      expect(TvClipCompress.trimToSeconds((cap + 1) * 1000), cap);
      expect(TvClipCompress.trimToSeconds((cap * 2) * 1000), cap);
    });

    test('сония берадиган қурилмалар ҳам тўғри тушунилади', () {
      // 1000 дан кичик қиймат сония деб қабул қилинади.
      expect(TvClipCompress.trimToSeconds(999), 999 > cap ? cap : null);
      expect(TvClipCompress.trimToSeconds(1), isNull);
    });

    test('номаълум давомийлик — кесилмайди', () {
      expect(TvClipCompress.trimToSeconds(null), isNull);
      expect(TvClipCompress.trimToSeconds(0), isNull);
    });
  });

  test('клиент сўрайдиган ҳар бир сифат учун серверда вариант бор', () {
    // Мослик бузилса жимгина йиқилади: `videoVariants[quality]` топилмай,
    // клиент хом, сиқилмаган асл файлга қайтади — айнан энг заиф
    // тармоқдаги фойдаланувчи учун. (360p ўшандай йўқолиб турган эди.)
    final js = File('functions/index.js').readAsStringSync();
    final specs = RegExp(r"key: '(\d+p)'")
        .allMatches(js)
        .map((m) => m.group(1))
        .toSet();
    for (final quality in const ['720p', '480p', '360p']) {
      expect(
        specs,
        contains(quality),
        reason: 'functions/index.js: TV_CLIP_VARIANT_SPECS да $quality йўқ — '
            'TvNetworkQualityService уни сўрайди',
      );
    }
  });

  group('Таом видеоси — 60 сония (D-REST-30, эга 2026-10-19)', () {
    test('tvClipMaxSecondsFor: таом — 60; ресторан видеоси ва бошқалар — умумий чегара', () {
      expect(tvClipMaxSecondsFor('restaurant_item'), 60);
      expect(tvClipItemMaxUploadSeconds, 60);
      for (final k in ['restaurant', 'ad', 'service', 'market_ad', 'wholesale_product', '']) {
        expect(tvClipMaxSecondsFor(k), tvClipMaxUploadSeconds, reason: k);
      }
      expect(tvClipItemMaxUploadSeconds, lessThan(tvClipMaxUploadSeconds));
    });

    test('trimToSeconds(maxSeconds: 60): 60 с ўзи кесилмайди, 61 с → 60 га; умумий чегара ўзгаришсиз', () {
      expect(TvClipCompress.trimToSeconds(60 * 1000, maxSeconds: 60), isNull);
      expect(TvClipCompress.trimToSeconds(61 * 1000, maxSeconds: 60), 60);
      expect(TvClipCompress.trimToSeconds(45 * 1000, maxSeconds: 60), isNull);
      expect(TvClipCompress.trimToSeconds(5 * 60 * 1000, maxSeconds: 60), 60, reason: '5 дақиқа таом видеоси 60 га кесилади');
      // Параметрсиз чақирув (ресторан видеоси/бошқа клиплар) — эски 600 чегараси
      expect(TvClipCompress.trimToSeconds(5 * 60 * 1000), isNull);
      expect(TvClipCompress.trimToSeconds(601 * 1000), tvClipMaxUploadSeconds);
    });

    test('сервердаги таом чегараси (functions/tv_clip_limits.js) клиентнинг tvClipItemMaxUploadSeconds билан мос', skip: serverParitySkip, () {
      final js = File('functions/tv_clip_limits.js').readAsStringSync();
      final m = RegExp(r'const TV_CLIP_ITEM_MAX_SECONDS = (\d+);').firstMatch(js);
      expect(m, isNotNull, reason: 'functions/tv_clip_limits.js: TV_CLIP_ITEM_MAX_SECONDS йўқ');
      expect(int.parse(m!.group(1)!), tvClipItemMaxUploadSeconds);
      final kind = RegExp(r"const ITEM_LINK_KIND = '([a-z_]+)';").firstMatch(js);
      expect(kind!.group(1), 'restaurant_item', reason: 'сервер ва клиент бир хил боғлаш турини кутади');
    });

    test('index.js transcode ШУ чегарани клипнинг linkKind\'идан олади (учала ffmpeg `-t` қиймати қотирилмаган)', skip: serverParitySkip, () {
      final js = File('functions/index.js').readAsStringSync();
      expect(js, contains("require('./tv_clip_limits')"));
      expect(js, contains('tvClipMaxSecondsFor(cur, TV_CLIP_MAX_SECONDS)'));
      // `-t` ёнида умумий константа ҚОЛМАГАН: иккала ffmpeg чақируви ўзгарувчи чегарадан фойдаланади
      final fixed = RegExp(r"'-t', String\(TV_CLIP_MAX_SECONDS\)").allMatches(js).length;
      expect(fixed, 0, reason: "'-t' га бевосита TV_CLIP_MAX_SECONDS берилса таом чегараси ишламайди");
    });
  });

  group('Кўчмас мулк эълони видеоси — 60 сония (эга 2026-10-19)', () {
    test('tvClipMaxSecondsFor: realty_listing — 60; таом — 60; қолгани — умумий чегара', () {
      expect(tvClipMaxSecondsFor('realty_listing'), 60);
      expect(tvClipRealtyMaxUploadSeconds, 60);
      expect(tvClipRealtyMaxUploadSeconds, lessThan(tvClipMaxUploadSeconds));
      expect(tvClipMaxSecondsFor('restaurant_item'), 60);
      for (final k in ['restaurant', 'ad', 'service', 'market_ad', 'wholesale_product', '']) {
        expect(tvClipMaxSecondsFor(k), tvClipMaxUploadSeconds, reason: k);
      }
    });

    test('trimToSeconds(maxSeconds: 60): 60 с ўзи кесилмайди, 61 с → 60 га; 5 дақиқа → 60', () {
      expect(TvClipCompress.trimToSeconds(60 * 1000, maxSeconds: tvClipRealtyMaxUploadSeconds), isNull);
      expect(TvClipCompress.trimToSeconds(61 * 1000, maxSeconds: tvClipRealtyMaxUploadSeconds), 60);
      expect(TvClipCompress.trimToSeconds(5 * 60 * 1000, maxSeconds: tvClipRealtyMaxUploadSeconds), 60);
    });

    test('сервердаги чегара (functions/tv_clip_limits.js) клиентнинг tvClipRealtyMaxUploadSeconds билан мос', skip: serverParitySkip, () {
      final js = File('functions/tv_clip_limits.js').readAsStringSync();
      final m = RegExp(r'const TV_CLIP_REALTY_MAX_SECONDS = (\d+);').firstMatch(js);
      expect(m, isNotNull, reason: 'functions/tv_clip_limits.js: TV_CLIP_REALTY_MAX_SECONDS йўқ');
      expect(int.parse(m!.group(1)!), tvClipRealtyMaxUploadSeconds);
      final kind = RegExp(r"const REALTY_LINK_KIND = '([a-z_]+)';").firstMatch(js);
      expect(kind!.group(1), 'realty_listing');
      // Клиент тури ва қоидадаги тур ҳам бир хил (тур номи уч жойда — бири адашса жимгина йиқилади).
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains("d.get('linkKind', '') != 'realty_listing'"));
      final cleanup = File('functions/realty_video.js').readAsStringSync();
      expect(cleanup, contains("const REALTY_LINK_KIND = 'realty_listing';"));
    });

    test('экран ва транскодер чегарани клипнинг linkKind\'идан олади (клиентда `maxDuration` ҳам шундан)', () {
      final screen = File('lib/features/tv_market/screens/tv_publish_screen.dart').readAsStringSync();
      expect(screen, contains('tvClipMaxSecondsFor(widget.linkKind)'));
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
