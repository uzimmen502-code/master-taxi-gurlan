// `provider_presence/{uid}` — «ҳозир шу ерда, онлайн ва ишга тайёр».
//
// Бу МОДЕЛ ЁЗИШ payload'и, ҳаётий модел эмас (`CourierStatus` билан бир
// хил ёндашув). Ўқиш серверда: `functions_demand/sources/presence_geo.js`.
//
// ── НЕГА АЛОҲИДА КОЛЛЕКЦИЯ (`couriers` ўрнига) ─────────────────────────
// `couriers` фақат курьерлар учун ва ўша ҳужжатда исм, телефон, fcmToken
// каби маълумотлар аралаш турган. `provider_presence` эса МОДУЛДАН
// қатъи назар ҳамма таклифчи учун битта шакл: такси, юк, курьер.
// Шунинг учун бу ерга исм ҳам, телефон ҳам ЁЗИЛМАЙДИ (40-қоида: PII
// минимал). Админ панели керак бўлса `users/{id}`дан олади.
//
// ── СЕРВЕР ШАРТНОМАСИ (қоида ва sweep билан қулфланган) ────────────────
//
// 1. `providerId` МАЖБУРИЙ ва ҳужжат калити билан мос бўлиши керак
//    (`firestore.rules` → `presenceClientFieldsOk`). Калит — канон
//    12 хонали телефон.
// 2. `updatedAt` ни СЕРВЕР қўяди (`FieldValue.serverTimestamp()`).
//    Шунинг учун у бу моделда ЙЎҚ — репозиторий қўшади. Клиент соати
//    билан ёзилган вақт қоида томонидан РАД ЭТИЛАДИ: акс ҳолда
//    келажак вақт ёзиб, доимо «янги» бўлиб туриш мумкин эди.
// 3. ҲАР БИР heartbeat `isOnline: true` ни ҳам ёзиши ШАРТ. Сервердаги
//    sweep (`presenceSweeper`, ҳар 2 дақиқада) эскирган ёзувни
//    `isOnline: false` қилиб қўяди ва `updatedAt`га ТЕГМАЙДИ — яъни
//    фақат координатани янгилаган клиент қайтиб онлайн БЎЛМАЙДИ.
// 4. `trustScore` `rating` `matchingBlocked` `offlineAt` `offlineReason`
//    — сервер майдонлари. Бу моделда улар умуман йўқ.

import '../utils/geo_hash.dart';

class ProviderPresence {
  const ProviderPresence({
    required this.providerId,
    required this.module,
    required this.isOnline,
    required this.lat,
    required this.lng,
    this.vehicle = '',
    this.regionId = '',
    this.districtId = '',
  });

  /// Сақланадиган geohash аниқлиги.
  ///
  /// Сервер радиусдан келиб чиқиб ЎЗИ prefix узунлигини танлайди
  /// (`functions_demand/geo/geo.js` → `precisionForRadiusKm`, максимум 7)
  /// ва `geohash >= prefix && geohash < prefix~` диапазони билан сўров
  /// беради. Шунинг учун клиент ҚИСҚА ёзмаслиги керак: 7 дан қисқа
  /// қиймат диапазонга тушмайди ва курьер ҳеч қачон топилмайди.
  ///
  /// 9 танланди: 7 талаб (≈150 м), 9 эса ≈5 м — радиус кичрайса ҳам
  /// сақланган маълумот қайта ёзишни талаб қилмайди. Паритет
  /// `test/core/geo_hash_parity_test.dart` да қулфланган.
  static const int geohashPrecision = 9;

  /// Канон 12 хонали телефон — ҳужжат калити билан АЙНАН бир хил.
  final String providerId;

  /// `DemandModule.wire` (масалан `courier`).
  final String module;

  final bool isOnline;
  final double lat;
  final double lng;

  /// `moto` `car` `pickup`… — бўш бўлса ёзилмайди.
  final String vehicle;
  final String regionId;
  final String districtId;

  /// Сервер диапазон сўрови учун калит.
  String get geohash =>
      GeoHash.encode(lat, lng, precision: geohashPrecision);

  /// Firestore'га тушадиган майдонлар.
  ///
  /// `updatedAt` АТАЙЛАБ ЙЎҚ — уни репозиторий `serverTimestamp()` билан
  /// қўшади (2-банд). Шу сабабли бу map'ни тест Firestore'сиз текшира
  /// олади.
  Map<String, dynamic> toUpsertMap() => {
        'providerId': providerId,
        'module': module,
        'isOnline': isOnline,
        'lat': lat,
        'lng': lng,
        'geohash': geohash,
        if (vehicle.isNotEmpty) 'vehicle': vehicle,
        if (regionId.isNotEmpty) 'regionId': regionId,
        if (districtId.isNotEmpty) 'districtId': districtId,
      };
}
