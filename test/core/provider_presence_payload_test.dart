// `provider_presence` ЁЗУВ ШАКЛИ — сервер шартномаси билан мос.
//
//   flutter test test/core/provider_presence_payload_test.dart
//
// Бу тест Firestore'сиз ишлайди: `toUpsertMap()` соф функция. Серверда
// ўша шаклни УЧТА жой текширади —
//   1) қоида:   `firestore.rules` → `presenceClientFieldsOk`
//                (`functions/test/provider_presence_rules.test.js`, 29/29)
//   2) ўқувчи:  `functions_demand/sources/presence_geo.js`
//   3) sweep:   `functions_demand/api/maintenance.js`
// шунинг учун бу ерда фақат КЛИЕНТ ТОМОНИ қулфланади.

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/demand_offer/domain/demand_enums.dart';
import 'package:ava_gurlan/models/provider_presence.dart';

ProviderPresence sample({
  String providerId = '998901234567',
  bool isOnline = true,
  double lat = 41.55,
  double lng = 60.63,
  String vehicle = '',
  String regionId = '',
  String districtId = '',
}) =>
    ProviderPresence(
      providerId: providerId,
      module: DemandModule.courier.wire,
      isOnline: isOnline,
      lat: lat,
      lng: lng,
      vehicle: vehicle,
      regionId: regionId,
      districtId: districtId,
    );

void main() {
  group('мажбурий майдонлар', () {
    test('ўқувчи талаб қиладиган барча майдон бор', () {
      final m = sample().toUpsertMap();
      // `presence_geo.fetchCandidates` сўрови: isOnline + module + geohash.
      // Масофа ва ETA учун: lat + lng.
      for (final key in ['providerId', 'module', 'isOnline', 'lat', 'lng',
        'geohash']) {
        expect(m.containsKey(key), isTrue, reason: '«$key» майдони йўқ');
      }
    });

    test('модул АЙНАН `courier` (сервер сўрови шу билан солиштиради)', () {
      expect(sample().toUpsertMap()['module'], 'courier');
    });

    test('`updatedAt` МОДЕЛДА ЙЎҚ — уни репозиторий қўшади', () {
      // Қоида `updatedAt == request.time` ни талаб қилади, яъни фақат
      // `FieldValue.serverTimestamp()` ўтади. Моделда sentinel сақланса,
      // бу map'ни тест текшира олмасди.
      expect(sample().toUpsertMap().containsKey('updatedAt'), isFalse);
    });

    test('ҳар heartbeat `isOnline: true` юборади', () {
      // Sweep эскирган ёзувни offline қилади ва `updatedAt`га тегмайди —
      // шунинг учун фақат координата янгиланса, курьер қайтиб онлайн
      // БЎЛМАЙДИ.
      expect(sample().toUpsertMap()['isOnline'], isTrue);
    });
  });

  group('сервер майдонларига тегилмайди', () {
    test('trustScore, rating, matchingBlocked, offlineAt ёзилмайди', () {
      final keys = sample(
        vehicle: 'moto',
        regionId: 'xorazm',
        districtId: 'gurlan',
      ).toUpsertMap().keys.toSet();
      for (final forbidden in [
        'trustScore', 'rating', 'matchingBlocked',
        'offlineAt', 'offlineReason', 'stats',
      ]) {
        expect(keys.contains(forbidden), isFalse,
            reason: '«$forbidden» — сервер майдони, қоида рад этади');
      }
    });

    test('исм ва телефон ЁЗИЛМАЙДИ (40-қоида: PII минимал)', () {
      final keys = sample().toUpsertMap().keys.toSet();
      expect(keys.contains('name'), isFalse);
      expect(keys.contains('phone'), isFalse);
      expect(keys.contains('fcmToken'), isFalse);
    });
  });

  group('ихтиёрий майдонлар', () {
    test('бўш қиймат УМУМАН ёзилмайди (null эмас)', () {
      final m = sample().toUpsertMap();
      expect(m.containsKey('vehicle'), isFalse);
      expect(m.containsKey('regionId'), isFalse);
      expect(m.containsKey('districtId'), isFalse);
    });

    test('берилган қиймат ёзилади', () {
      final m = sample(
        vehicle: 'moto',
        regionId: 'xorazm',
        districtId: 'gurlan',
      ).toUpsertMap();
      expect(m['vehicle'], 'moto');
      expect(m['regionId'], 'xorazm');
      expect(m['districtId'], 'gurlan');
    });
  });

  group('geohash', () {
    test('координатадан ҳисобланади, қўлда берилмайди', () {
      final a = sample(lat: 41.55, lng: 60.63).toUpsertMap()['geohash'];
      final b = sample(lat: 41.8419, lng: 60.3889).toUpsertMap()['geohash'];
      expect(a, isNot(b));
      expect((a as String).length, ProviderPresence.geohashPrecision);
    });

    test('кичик силжиш префиксни САҚЛАЙДИ (битта катак)', () {
      // ~10 м силжиш: p7 катаги ўзгармаслиги керак, акс ҳолда ҳар
      // қадамда бошқа катакка тушиб, сўров натижаси беқарор бўларди.
      final a = sample(lat: 41.5500, lng: 60.6300).geohash.substring(0, 7);
      final b = sample(lat: 41.55005, lng: 60.63005).geohash.substring(0, 7);
      expect(a, b);
    });
  });
}
