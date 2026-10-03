// 13.4.2 — DART TOMONI ПАРИТЕТ ТЕСТИ (Т-16).
//
//   flutter test test/features/demand_offer/demand_parity_test.dart
//
// Жуфти: `functions_demand/test/parity.test.js`.
// Иккиси АЙНИ БИР фикстурани ўқийди:
//   functions_demand/test/fixtures/demand_parity.json
//
// НЕГА БУ ТЕСТ БОР: концепция `attributes` моделларини JSON Schema'дан
// генерация қилишни таклиф қилган. Лекин репода `build_runner` йўқ ва
// 1.0.32 версиядаги production иловага codegen қувурини киритиш алоҳида
// катта иш. Шунинг учун моделлар ҚЎЛДА ёзилди — ва айни шу тест
// уларнинг сервердан ажралиб кетмаслигини қулфлайди.
//
// Плагин керак эмас: моделлар соф Dart, Firestore типларини билмайди.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/demand_offer/domain/demand.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand_enums.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand_match.dart';
import 'package:ava_gurlan/features/demand_offer/domain/offer.dart';

void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    final file = File('functions_demand/test/fixtures/demand_parity.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Паритет фикстураси топилмади: ${file.path}. '
          'Сервер тести (`parity.test.js`) ҳам шу файлни ўқийди.',
    );
    fixture = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  Map<String, dynamic> docOf(String key) =>
      (fixture['docs'] as Map<String, dynamic>)[key] as Map<String, dynamic>;

  Map<String, dynamic> dataOf(String key) =>
      docOf(key)['data'] as Map<String, dynamic>;

  Map<String, dynamic> expectOf(String key) =>
      docOf(key)['expect'] as Map<String, dynamic>;

  group('Demand.fromMap — паритет', () {
    test('тўлиқ талаб ҳужжати', () {
      final d = Demand.fromMap(docOf('demand')['id'] as String, dataOf('demand'));
      final e = expectOf('demand');

      expect(d.ownerId, e['ownerId']);
      expect(d.module.wire, e['module']);
      expect(d.mode.name, e['mode']);
      expect(d.status.wire, e['status']);
      expect(d.matching.state.wire, e['matchingState']);
      expect(d.matching.matchedBucket.wire, e['matchedBucket']);
      expect(d.title, e['title']);
      expect(d.location?.regionId, e['locationRegionId']);
      expect(d.location?.districtId, e['locationDistrictId']);
      expect(d.budget?.max, e['budgetMax']);
      expect(d.images.length, e['imageCount']);
      expect(d.wholesale, e['wholesale']);
      expect(d.assignment.isAssigned, e['isAssigned']);
      expect(d.attributes['visitType'], e['attributeVisitType']);
    });

    test('`in_progress` статуси тўғри ўқилади', () {
      // Энг осон хато: сервер `in_progress` (snake_case) ёзади, Dart эса
      // `inProgress` деб кутади. Шунда статус «номаълум» бўлиб қолади.
      final d = Demand.fromMap(
        docOf('demand_in_progress')['id'] as String,
        dataOf('demand_in_progress'),
      );
      final e = expectOf('demand_in_progress');

      expect(d.status, DemandStatus.inProgress);
      expect(d.status.wire, e['status']);
      expect(d.assignment.isAssigned, e['isAssigned']);
      expect(d.assignment.providerId, e['assignedProviderId']);
    });

    test('ISO сана DateTime га айланади', () {
      final d = Demand.fromMap('x', dataOf('demand'));
      expect(d.createdAt, isNotNull);
      expect(d.timeWindow.expiresAt, isNotNull);
      expect(d.timeWindow.expiresAt!.isAfter(d.createdAt!), isTrue);
    });

    test('номаълум статус — `draft` (илова йиқилмайди)', () {
      // Сервер янги статус қўшса, эски илова уни «номаълум» деб
      // қабул қилиб ишлашда давом этиши керак, йиқилмаслиги керак.
      final d = Demand.fromMap('x', {
        ...dataOf('demand'),
        'status': 'kelajakdagi_status',
      });
      expect(d.status, DemandStatus.draft);
    });

    test('бўш ҳужжат йиқитмайди', () {
      final d = Demand.fromMap('x', <String, dynamic>{});
      expect(d.id, 'x');
      expect(d.status, DemandStatus.draft);
      expect(d.images, isEmpty);
      expect(d.location, isNull);
    });
  });

  group('Offer.fromMap — паритет', () {
    test('таклиф ҳужжати', () {
      final o = Offer.fromMap(docOf('offer')['id'] as String, dataOf('offer'));
      final e = expectOf('offer');

      expect(o.providerId, e['providerId']);
      expect(o.ownerId, e['ownerId'], reason: 'Т-2.2 денормализацияси');
      expect(o.status.wire, e['status']);
      expect(o.price, e['price']);
      expect(o.etaMinutes, e['etaMinutes']);
      expect(o.revision, e['revision']);
      expect(o.isActive, e['isActive']);
    });

    test('таҳрир чегараси (Т-19.4)', () {
      final o = Offer.fromMap('p', {...dataOf('offer'), 'revision': 3});
      expect(o.canReviseWithLimit(3), isFalse);
      final o2 = Offer.fromMap('p', {...dataOf('offer'), 'revision': 2});
      expect(o2.canReviseWithLimit(3), isTrue);
    });
  });

  group('DemandMatch.fromMap — паритет', () {
    test('проекция ва метрикалар', () {
      final m = DemandMatch.fromMap(
        docOf('match')['id'] as String,
        dataOf('match'),
      );
      final e = expectOf('match');

      expect(m.demandId, e['demandId']);
      expect(m.providerId, e['providerId'],
          reason: 'providerId калитдан эмас, МАЙДОНДАН ўқилиши керак (Т-2.1)');
      expect(m.status.wire, e['status']);
      expect(m.isNew, e['isNew']);
      expect(m.status.canOffer, e['canOffer']);
      expect(m.score, e['score']);
      expect(m.sources.length, e['sourceCount']);
      expect(m.consentGiven, e['consentGiven']);
      expect(m.metrics.distanceKm, e['distanceKm']);
      expect(m.projection.geohash.length, e['projectionGeohashLength']);
      expect(m.projection.hasApproxPoint, e['hasApproxPoint']);
      expect(m.needsConsentPrompt, e['needsConsentPrompt']);
      expect(m.contact, isNull, reason: 'қабул қилинмагунча контакт ЙЎҚ');
    });

    test('МАХФИЙЛИК: проекцияда аниқ манзил ва телефон йўқ', () {
      final m = DemandMatch.fromMap('k', dataOf('match'));
      final text = json.encode({
        'title': m.projection.title,
        'description': m.projection.description,
        'district': m.projection.districtId,
        'address': m.projection.attributes,
      });
      expect(text.contains('15-uy'), isFalse);
      expect(text.contains('3-xonadon'), isFalse);
      expect(RegExp(r'998\d{9}').hasMatch(text), isFalse);
    });

    test('МАХФИЙЛИК: тахминий нуқта аниқ нуқтадан фарқ қилади', () {
      final m = DemandMatch.fromMap('k', dataOf('match'));
      final d = Demand.fromMap('x', dataOf('demand'));
      expect(m.projection.approxLat, isNot(d.location!.lat));
      expect(m.projection.approxLng, isNot(d.location!.lng));
    });

    test('cold start: розилик йўқ -> таклиф кўрсатилади', () {
      final m = DemandMatch.fromMap(
        docOf('match_cold_start_no_consent')['id'] as String,
        dataOf('match_cold_start_no_consent'),
      );
      final e = expectOf('match_cold_start_no_consent');

      expect(m.consentGiven, e['consentGiven']);
      expect(m.needsConsentPrompt, e['needsConsentPrompt'],
          reason: '`ads`дан топилган одамга розилик таклифи кўрсатилиши керак');
      expect(m.sources.length, e['sourceCount']);
    });

    test('Т-9: 1-поғонада қабул қилувчи телефони ЙЎҚ', () {
      final m = DemandMatch.fromMap(
        docOf('match_accepted_stage1')['id'] as String,
        dataOf('match_accepted_stage1'),
      );
      final e = expectOf('match_accepted_stage1');

      expect(m.status.wire, e['status']);
      expect(m.contact, isNotNull);
      expect(m.contact!.stage, e['contactStage']);
      expect(m.contact!.ownerPhone, e['contactOwnerPhone']);
      expect(m.contact!.hasRecipient, e['contactHasRecipient'],
          reason: 'манзил йиғиш ҳужумига қарши ҳимоя');
      expect(m.status.canOffer, e['canOffer']);
    });

    test('муддати ўтган match рўйхатда кўринмайди (Т-5)', () {
      final m = DemandMatch.fromMap('k', dataOf('match'));
      final beforeExpiry = DateTime.parse('2026-10-03T12:00:00.000Z');
      final afterExpiry = DateTime.parse('2026-10-05T12:00:00.000Z');
      expect(m.isVisibleAt(beforeExpiry), isTrue);
      expect(m.isVisibleAt(afterExpiry), isFalse,
          reason: 'сервер sweeper кечикса ҳам эскирган талаб кўринмаслиги керак');
    });
  });

  group('Энумлар — сервер сатрлари билан мослик', () {
    test('DemandStatus барча `wire` қийматлари', () {
      // Сервердаги `state_machine.js` STATUS қийматлари.
      const serverStatuses = [
        'draft', 'active', 'accepted', 'in_progress',
        'completed', 'cancelled', 'expired', 'disputed',
      ];
      for (final s in serverStatuses) {
        expect(DemandStatus.tryParse(s), isNotNull,
            reason: 'сервер «$s» ёзади, илова уни тушунмайди');
      }
      expect(DemandStatus.values.length, serverStatuses.length);
    });

    test('DemandMatchingState сервер билан бир хил', () {
      for (final s in ['pending', 'running', 'done', 'no_providers', 'failed']) {
        expect(DemandMatchingState.tryParse(s), isNotNull, reason: s);
      }
    });

    test('OfferStatus сервер билан бир хил', () {
      for (final s in ['active', 'withdrawn', 'accepted', 'rejected', 'expired']) {
        expect(OfferStatus.tryParse(s), isNotNull, reason: s);
      }
    });

    test('MatchStatus сервер ёзадиган ҳамма қийматни тушунади', () {
      // `orchestrator.js` ва `offers.js` ёзадиган статуслар.
      const serverMatchStatuses = [
        'new', 'seen', 'skipped', 'offered', 'accepted',
        'taken', 'expired', 'cancelled',
        'cancelled_by_provider', 'deadline_missed',
      ];
      for (final s in serverMatchStatuses) {
        expect(MatchStatus.tryParse(s), isNotNull,
            reason: 'сервер «$s» ёзади, илова уни тушунмайди');
      }
    });

    test('DemandModule рўйхати сервер схемаси билан бир хил', () {
      // `demand_input.schema.json` даги `module` enum.
      const serverModules = [
        'service', 'courier', 'intercity_taxi', 'local_taxi', 'freight_local',
        'freight_intercity', 'sell', 'market', 'platform_store', 'realty',
        'food', 'oil_change', 'carpet_wash', 'bread', 'agro_pickup',
      ];
      for (final m in serverModules) {
        expect(DemandModule.tryParse(m), isNotNull, reason: m);
      }
      expect(DemandModule.values.length, serverModules.length);
    });

    test('MatchedBucket сервер панжараси билан бир хил', () {
      // `scoring.js` даги `matchedBucket()`.
      for (final b in ['0', '1-2', '3-5', '6-10', '10+', '30+', '100+']) {
        expect(MatchedBucket.parse(b).wire, b, reason: b);
      }
      // Номаълум қиймат — бўш деб қабул қилинади, йиқилмайди.
      expect(MatchedBucket.parse('xayoliy').isEmpty, isTrue);
    });

    test('`in_progress` фақат dispatch ва quote режимида', () {
      expect(DemandMode.dispatch.usesInProgress, isTrue);
      expect(DemandMode.quote.usesInProgress, isTrue);
      expect(DemandMode.alert.usesInProgress, isFalse);
      expect(DemandMode.recurring.usesInProgress, isFalse);
    });
  });

  group('OfferList — тартиблаш', () {
    List<Offer> build() => [
          Offer.fromMap('p1', {
            ...dataOf('offer'), 'providerId': '998901111111', 'price': 200000,
          }).withProviderInfo(rating: 4.0, distanceKm: 5),
          Offer.fromMap('p2', {
            ...dataOf('offer'), 'providerId': '998902222222', 'price': 150000,
          }).withProviderInfo(rating: 5.0, distanceKm: 10),
          Offer.fromMap('p3', {
            ...dataOf('offer'), 'providerId': '998903333333', 'price': null,
            'delivery': true,
          }).withProviderInfo(rating: 3.0, distanceKm: 1),
        ];

    test('нарх бўйича — нархсиз таклиф охирида', () {
      final sorted = OfferList(build()).sorted(OfferSort.priceAsc);
      expect(sorted.map((o) => o.providerId).toList(), [
        '998902222222', '998901111111', '998903333333',
      ]);
    });

    test('рейтинг бўйича', () {
      final sorted = OfferList(build()).sorted(OfferSort.ratingDesc);
      expect(sorted.first.providerId, '998902222222');
    });

    test('масофа бўйича', () {
      final sorted = OfferList(build()).sorted(OfferSort.distanceAsc);
      expect(sorted.first.providerId, '998903333333');
    });

    test('етказиб бериш билан олдинда', () {
      final sorted = OfferList(build()).sorted(OfferSort.deliveryFirst);
      expect(sorted.first.delivery, isTrue);
    });

    test('тартиб БАРҚАРОР (рўйхат сакрамайди)', () {
      final a = OfferList(build()).sorted(OfferSort.priceAsc)
          .map((o) => o.providerId).toList();
      final b = OfferList(build().reversed.toList()).sorted(OfferSort.priceAsc)
          .map((o) => o.providerId).toList();
      expect(a, b);
    });

    test('фақат актив таклифлар кўрсатилади', () {
      final list = OfferList([
        Offer.fromMap('p1', {...dataOf('offer'), 'status': 'active'}),
        Offer.fromMap('p2', {...dataOf('offer'), 'status': 'withdrawn'}),
        Offer.fromMap('p3', {...dataOf('offer'), 'status': 'rejected'}),
      ]);
      expect(list.activeCount, 1);
      expect(list.sorted(OfferSort.priceAsc).length, 1);
    });
  });
}
