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
    updatedAt: DateTime(2026, 1, 1),
    isDemo: isDemo,
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
}
