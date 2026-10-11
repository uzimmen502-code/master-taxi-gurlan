import 'package:ava_gurlan/features/yuk_local/models/yuk_local_driver.dart';
import 'package:ava_gurlan/features/yuk_local/yuk_accept_radius.dart';
import 'package:ava_gurlan/features/yuk_local/yuk_local_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

// Гурлан маркази — қидирувчи нуқтаси.
const _userLat = 41.8450;
const _userLng = 60.3900;

YukLocalDriver _driver(
  String id, {
  double? lat,
  double? lng,
  String vehicleType = 'gazel',
  YukLocalLoadStatus loadStatus = YukLocalLoadStatus.empty,
  int acceptRadiusKm = 20,
  int workStart = 0,
  int workEnd = 24 * 60,
  DateTime? expiresAt,
  bool isDemo = false,
  String districtId = '',
  DateTime? updatedAt,
}) {
  return YukLocalDriver(
    id: id,
    ownerId: '99890000$id',
    ownerName: 'D$id',
    phone: '+99890000$id',
    vehicleType: vehicleType,
    plateNumber: '90 A 000 AA',
    capacityKg: 1000,
    bodyLengthM: 3,
    bodyWidthM: 2,
    bodyHeightM: 2,
    acceptRadiusKm: acceptRadiusKm,
    loadStatus: loadStatus,
    lat: lat,
    lng: lng,
    locationLabel: '',
    workStartMinutes: workStart,
    workEndMinutes: workEnd,
    expiresAt: expiresAt,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: updatedAt ?? DateTime(2026, 1, 1),
    isDemo: isDemo,
    districtId: districtId,
  );
}

void main() {
  final ranker = YukLocalRanking();
  final now = DateTime(2026, 9, 15, 12, 0);

  List<String> ids(List<YukLocalDriverRanked> r) =>
      r.map((e) => e.driver.id).toList();

  group('YukLocalRanking.rank — масофа/ETA', () {
    test('0.01° кенглик ≈ 1.11 км тўғри чизиқ, йўл ×1.35, ETA 27 км/с', () {
      final r = ranker.rank(
        drivers: [_driver('a', lat: _userLat + 0.01, lng: _userLng)],
        userLat: _userLat,
        userLng: _userLng,
        now: now,
      );
      expect(r, hasLength(1));
      expect(r.first.straightKm, closeTo(1.112, 0.01));
      expect(r.first.roadKm,
          closeTo(r.first.straightKm * YukLocalRanking.roadFactor, 1e-9));
      // 1.5 км / 27 км/с × 60 ≈ 3.34 → ceil 4
      expect(r.first.etaMinutes, 4);
    });

    test('ETA камида 1 дақиқа (ўша нуқтада турса ҳам)', () {
      final r = ranker.rank(
        drivers: [_driver('a', lat: _userLat, lng: _userLng)],
        userLat: _userLat,
        userLng: _userLng,
        now: now,
      );
      expect(r.first.etaMinutes, 1);
      expect(r.first.straightKm, closeTo(0, 1e-9));
    });
  });

  group('YukLocalRanking.rank — фильтр', () {
    test('GPS йўқ, муддати ўтган, иш вақтидан ташқари — чиқарилади', () {
      final r = ranker.rank(
        drivers: [
          _driver('noGps'),
          _driver('zeroGps', lat: 0, lng: 0),
          _driver('expired',
              lat: _userLat,
              lng: _userLng,
              expiresAt: now.subtract(const Duration(minutes: 1))),
          _driver('offHours',
              lat: _userLat, lng: _userLng, workStart: 13 * 60, workEnd: 18 * 60),
          _driver('ok', lat: _userLat, lng: _userLng),
        ],
        userLat: _userLat,
        userLng: _userLng,
        now: now,
      );
      expect(ids(r), ['ok']);
    });

    test('demo эълон муддати ўтган бўлса ҳам қолади', () {
      final r = ranker.rank(
        drivers: [
          _driver('demo',
              lat: _userLat,
              lng: _userLng,
              isDemo: true,
              expiresAt: now.subtract(const Duration(days: 1))),
        ],
        userLat: _userLat,
        userLng: _userLng,
        now: now,
      );
      expect(ids(r), ['demo']);
    });
  });

  group('YukLocalRanking.rank — радиус', () {
    test('радиусдан ташқари эълон чиқарилмайди, inRadius=false', () {
      final r = ranker.rank(
        drivers: [
          // ~11 км шимолда, радиус 5 км.
          _driver('far', lat: _userLat + 0.1, lng: _userLng, acceptRadiusKm: 5),
        ],
        userLat: _userLat,
        userLng: _userLng,
        now: now,
      );
      expect(r, hasLength(1));
      expect(r.first.inRadius, isFalse);
    });

    test('citywide (999) — ҳар қандай масофада inRadius=true', () {
      final r = ranker.rank(
        drivers: [
          _driver('city',
              lat: _userLat + 0.5,
              lng: _userLng,
              acceptRadiusKm: YukAcceptRadius.citywideKm),
        ],
        userLat: _userLat,
        userLng: _userLng,
        now: now,
      );
      expect(r.first.inRadius, isTrue);
    });
  });

  group('YukLocalRanking.rank — сорт тартиби', () {
    test('moto → тайёрлик → радиус → ETA → масофа', () {
      final r = ranker.rank(
        drivers: [
          // busy, яқин
          _driver('busyNear',
              lat: _userLat + 0.001,
              lng: _userLng,
              loadStatus: YukLocalLoadStatus.busy),
          // empty, узоқ лекин радиус ичида
          _driver('emptyFar', lat: _userLat + 0.05, lng: _userLng),
          // empty, яқин
          _driver('emptyNear', lat: _userLat + 0.002, lng: _userLng),
          // empty, радиусдан ташқари (5 км), лекин emptyFar'дан яқин
          _driver('emptyOutRadius',
              lat: _userLat + 0.06, lng: _userLng, acceptRadiusKm: 5),
          // moto — узоқ ва busy бўлса ҳам биринчи
          _driver('moto',
              lat: _userLat + 0.09,
              lng: _userLng,
              vehicleType: 'moto',
              loadStatus: YukLocalLoadStatus.busy),
        ],
        userLat: _userLat,
        userLng: _userLng,
        now: now,
      );
      expect(ids(r), [
        'moto',
        'emptyNear',
        'emptyFar',
        'emptyOutRadius',
        'busyNear',
      ]);
    });
  });

  group('YukLocalRanking.listWithoutGps — қидирувчида GPS йўқ (3а)', () {
    test('филтр rank билан бир хил; масофа номаълум, inRadius=true', () {
      final r = ranker.listWithoutGps(
        drivers: [
          _driver('noGps'),
          _driver('expired',
              lat: _userLat,
              lng: _userLng,
              expiresAt: now.subtract(const Duration(minutes: 1))),
          _driver('offHours',
              lat: _userLat, lng: _userLng, workStart: 13 * 60, workEnd: 18 * 60),
          _driver('ok', lat: _userLat + 0.3, lng: _userLng),
        ],
        now: now,
      );
      expect(ids(r), ['ok']);
      expect(r.first.distanceKnown, isFalse);
      expect(r.first.inRadius, isTrue);
    });

    test('тартиб: мото → тайёрлик → энг янги янгиланган', () {
      final r = ranker.listWithoutGps(
        drivers: [
          _driver('busyNew',
              lat: _userLat,
              lng: _userLng,
              loadStatus: YukLocalLoadStatus.busy,
              updatedAt: DateTime(2026, 9, 15)),
          _driver('emptyOld',
              lat: _userLat, lng: _userLng, updatedAt: DateTime(2026, 9, 1)),
          _driver('emptyNew',
              lat: _userLat, lng: _userLng, updatedAt: DateTime(2026, 9, 14)),
          _driver('moto',
              lat: _userLat,
              lng: _userLng,
              vehicleType: 'moto',
              loadStatus: YukLocalLoadStatus.busy,
              updatedAt: DateTime(2025, 1, 1)),
        ],
        now: now,
      );
      expect(ids(r), ['moto', 'emptyNew', 'emptyOld', 'busyNew']);
    });
  });

  group('YukLocalRanking.keepForDistrict — D-GEO-6 туман даражаси', () {
    List<YukLocalDriverRanked> ranked(List<YukLocalDriver> d) =>
        ranker.rank(drivers: d, userLat: _userLat, userLng: _userLng, now: now);

    test('шу туман (радиусдан ташқари бўлса ҳам) ва ҳудудсиз эски — қолади', () {
      final r = YukLocalRanking.keepForDistrict(
        ranked([
          _driver('sameFar',
              lat: _userLat + 0.3, lng: _userLng, acceptRadiusKm: 5,
              districtId: 'gurlan'),
          _driver('legacy', lat: _userLat + 0.3, lng: _userLng, acceptRadiusKm: 5),
        ]),
        'gurlan',
      );
      expect(ids(r)..sort(), ['legacy', 'sameFar']);
    });

    test('қўшни туман: радиуси қидирувчига етса кўринади, етмаса — йўқ', () {
      final r = YukLocalRanking.keepForDistrict(
        ranked([
          // ~5.6 км, радиус 10 — етади.
          _driver('nbReach',
              lat: _userLat + 0.05, lng: _userLng, acceptRadiusKm: 10,
              districtId: 'yangiariq'),
          // ~5.6 км, радиус 5 — етмайди.
          _driver('nbShort',
              lat: _userLat + 0.05, lng: _userLng, acceptRadiusKm: 5,
              districtId: 'yangiariq'),
        ]),
        'gurlan',
      );
      expect(ids(r), ['nbReach']);
    });

    test('чегара: масофа радиусга ТЕНГ — кўринади, 1 м ортиқ — йўқ', () {
      YukLocalDriverRanked at(String id, double km) => YukLocalDriverRanked(
            driver: _driver(id,
                lat: _userLat, lng: _userLng, acceptRadiusKm: 5,
                districtId: 'yangiariq'),
            straightKm: km,
            roadKm: km * YukLocalRanking.roadFactor,
            etaMinutes: 1,
            inRadius: km <= 5,
          );
      final r = YukLocalRanking.keepForDistrict(
        [at('edge', 5.0), at('over', 5.001)],
        'gurlan',
      );
      expect(ids(r), ['edge']);
    });

    test('қўшни туман «бутун туман» радиуси — бизнинг туманга етмайди', () {
      final r = YukLocalRanking.keepForDistrict(
        ranked([
          _driver('nbCity',
              lat: _userLat + 0.01,
              lng: _userLng,
              acceptRadiusKm: YukAcceptRadius.citywideKm,
              districtId: 'yangiariq'),
        ]),
        'gurlan',
      );
      expect(r, isEmpty);
    });

    test('GPS йўқ (масофа номаълум) — фақат шу туман ва эскилар', () {
      final r = YukLocalRanking.keepForDistrict(
        ranker.listWithoutGps(drivers: [
          _driver('same', lat: _userLat, lng: _userLng, districtId: 'gurlan'),
          _driver('nb', lat: _userLat, lng: _userLng, districtId: 'yangiariq'),
          _driver('legacy', lat: _userLat, lng: _userLng),
        ], now: now),
        'gurlan',
      );
      expect(ids(r)..sort(), ['legacy', 'same']);
    });

    test('туман бўш — филтр йўқ', () {
      final rows = ranked([
        _driver('a', lat: _userLat, lng: _userLng, districtId: 'x'),
      ]);
      expect(YukLocalRanking.keepForDistrict(rows, ''), rows);
    });
  });
}
