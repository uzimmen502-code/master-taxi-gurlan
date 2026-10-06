// GEOHASH ПАРИТЕТИ — илова ва сервер АЙНАН бир хил катакни ҳисоблаши.
//
//   flutter test test/core/geo_hash_parity_test.dart
//
// НЕГА КЕРАК: `provider_presence` ҳужжатидаги `geohash`ни ИЛОВА ёзади
// (`lib/utils/geo_hash.dart`), сервер эса ўша қиймат бўйича диапазон
// сўрови беради (`functions_demand/sources/presence_geo.js` →
// `geo.prefixRange`). Иккита implementation бир-биридан ажралиб кетса,
// сўров ҲЕЧ ҚАЧОН натижа бермайди — ва бу ЖИМГИНА содир бўлади: хато
// чиқмайди, шунчаки «якинда курьер йўқ».
//
// Fixture: `functions_demand/test/fixtures/geohash_vectors.json`. Ўша
// файлнинг изоҳи шу тестни УЧИНЧИ истеъмолчи деб атайди, лекин тест
// аслида ёзилмаган эди — 13.6.3 да қўшилди.
//
// Қийматлар ҚЎЛДА ЁЗИЛМАГАН: `functions/geo_hash.js` (Wikipedia
// нazорат қиймати билан тасдиқланган) билан ҳисобланган.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/models/provider_presence.dart';
import 'package:ava_gurlan/utils/geo_hash.dart';

void main() {
  final file = File(
    'functions_demand/test/fixtures/geohash_vectors.json',
  );

  test('fixture мавжуд — акс ҳолда паритет текширилмай қолади', () {
    expect(
      file.existsSync(),
      isTrue,
      reason: 'fixture топилмади: ${file.path}. Тест `flutter test` ни '
          'репо илдизидан ишга туширишни кутади.',
    );
  });

  group('geohash fixture пaритети', () {
    final data =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final vectors = (data['vectors'] as List).cast<Map<String, dynamic>>();

    for (final v in vectors) {
      final name = v['name'] as String;
      final want = v['geohash'] as String;
      test('$name -> $want', () {
        final got = GeoHash.encode(
          (v['lat'] as num).toDouble(),
          (v['lng'] as num).toDouble(),
          precision: v['precision'] as int,
        );
        expect(got, want, reason: 'сервер «$want», илова «$got»');
      });
    }

    test('fixture бўш эмас', () {
      expect(vectors, isNotEmpty);
    });
  });

  group('presence аниқлиги', () {
    test('ёзиладиган аниқлик сервер талабидан КИЧИК эмас', () {
      // Сервер максимум 7 узунликдаги prefix ишлатади
      // (`geo.js` → `precisionForRadiusKm` цикли `p = 7` дан бошланади).
      // Клиент ундан қисқа ёзса, `geohash >= prefix` диапазонига
      // ТУШМАЙДИ ва курьер ҳеч қачон топилмайди.
      expect(ProviderPresence.geohashPrecision, greaterThanOrEqualTo(7));
    });

    test('presence geohash префикс сифатида fixture билан мос', () {
      // Урганч маркази: p7 = `tr7h7ev` (fixture'да бор). Шу нуқта учун
      // 9 узунликдаги қиймат АЙНАН шу префикс билан бошланиши керак —
      // яъни сервернинг p7 диапазон сўрови уни тутади.
      final p = ProviderPresence(
        providerId: '998901234567',
        module: 'courier',
        isOnline: true,
        lat: 41.55,
        lng: 60.63,
      );
      expect(p.geohash.length, ProviderPresence.geohashPrecision);
      expect(p.geohash.startsWith('tr7h7ev'), isTrue,
          reason: 'олинган: ${p.geohash}');
      // Диапазон текшируви: `prefix <= geohash < prefix + '~'`.
      expect('tr7h7ev'.compareTo(p.geohash) <= 0, isTrue);
      expect(p.geohash.compareTo('tr7h7ev~') < 0, isTrue);
    });
  });
}
