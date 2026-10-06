// AVA LOGISTICS — DART ТОМОНИ ПАРИТЕТ ТЕСТИ.
//
//   flutter test test/features/logistics/logistics_parity_test.dart
//
// Жуфти: `functions_demand/test/logistics_parity.test.js`. Иккиси АЙНИ БИР
// фикстурани ўқийди: `functions_demand/test/fixtures/logistics_parity.json`.
// Фикстуранинг `docs` бўлими серверни ҳақиқий оқимда юритиб ёзилган
// (`--update`): яъни бу ерда Dart модели серверНИНГ ЎЗИ ёзган ҳужжатни
// ўқийди — тахмин эмас.
//
// Плагин керак эмас: моделлар соф Dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/demand_offer/domain/demand_enums.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand_match.dart';
import 'package:ava_gurlan/features/logistics/domain/logistics_models.dart';

void main() {
  late Map<String, dynamic> fx;
  late Map<String, dynamic> docs;
  late Map<String, dynamic> cyrl;

  setUpAll(() {
    final file = File('functions_demand/test/fixtures/logistics_parity.json');
    expect(file.existsSync(), isTrue, reason: 'Фикстура топилмади: ${file.path}');
    fx = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    docs = fx['docs'] as Map<String, dynamic>;
    cyrl = json.decode(File('assets/lang/uz_Cyrl.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  Map<String, dynamic> doc(String key) => docs[key] as Map<String, dynamic>;
  List<String> strs(String key) => (fx[key] as List).cast<String>();

  group('Энумлар — сервер сатрлари билан мослик', () {
    test('ShipmentStatus', () {
      for (final s in strs('shipmentStatuses')) {
        expect(ShipmentStatus.tryParse(s), isNotNull, reason: s);
        expect(ShipmentStatus.tryParse(s)!.wire, s);
      }
      expect(ShipmentStatus.values.length, strs('shipmentStatuses').length);
    });

    test('PaymentStatus', () {
      for (final s in strs('paymentStatuses')) {
        expect(PaymentStatus.tryParse(s), isNotNull, reason: s);
        expect(PaymentStatus.tryParse(s)!.wire, s);
      }
      expect(PaymentStatus.values.length, strs('paymentStatuses').length);
    });

    test('CustodianKind ва ҳолат белгилари', () {
      for (final k in strs('custodianKinds')) {
        expect(CustodianKind.tryParse(k), isNotNull, reason: k);
      }
      expect(CustodianKind.values.length, strs('custodianKinds').length);
      expect(ConditionFlags.all.toSet(), strs('conditionFlags').toSet());
    });

    test('MatchStatus — logistics ёзадиган `in_progress`/`completed`', () {
      expect(MatchStatus.tryParse('in_progress'), MatchStatus.inProgress);
      expect(MatchStatus.tryParse('completed'), MatchStatus.completed);
      expect(MatchStatus.inProgress.canOffer, isFalse);
      expect(MatchStatus.completed.isClosed, isTrue);
    });

    test('ҳар бир сервер сатри учун матн калити бор (uz_Cyrl)', () {
      // Калитлар учала тилда бир хил — `locale_sync_test` қулфлайди.
      for (final s in strs('shipmentStatuses')) {
        expect(cyrl.containsKey('logistics_status_$s'), isTrue, reason: s);
      }
      for (final s in strs('orderStatuses')) {
        expect(cyrl.containsKey('logistics_order_$s'), isTrue, reason: s);
      }
      for (final s in strs('paymentStatuses')) {
        expect(cyrl.containsKey('logistics_payment_$s'), isTrue, reason: s);
      }
      for (final f in strs('conditionFlags')) {
        expect(cyrl.containsKey('logistics_condition_$f'), isTrue, reason: f);
      }
    });

    test('`logistics_err_*` калитлари фақат мавжуд `reason` кодлари учун', () {
      // Эскирган калит қолиб кетмасин: сервер кодни ўзгартирса, матн ҳам.
      final reasons = strs('callableReasons').toSet();
      final stale = cyrl.keys
          .where((k) => k.startsWith('logistics_err_') && k != 'logistics_err_generic')
          .map((k) => k.substring('logistics_err_'.length))
          .where((r) => !reasons.contains(r))
          .toList();
      expect(stale, isEmpty, reason: 'серверда йўқ reason учун матн: $stale');
    });
  });

  group('Ҳужжатлар — сервер ёзган шаклдан ўқиш', () {
    test('Shipment (йўлда)', () {
      final s = Shipment.fromMap('SHIP1', doc('shipment'));
      expect(s.orderId, 'ORDER1');
      expect(s.trackingNumber, 'AVA-26-1007-000001');
      expect(s.status, ShipmentStatus.inTransit);
      expect(s.paymentStatus, PaymentStatus.escrowFunded);
      expect(s.priceSnapshot.customerPrice, 10000);
      expect(s.priceSnapshot.tariffVersion, 7, reason: 'D-8: тариф версияси муҳрланган');
      expect(s.priceSnapshot.zone, 'ZONE_0');
      expect(s.parcel.actualWeightG, 800);
      expect(s.parcel.lengthCm, 20);
      expect(s.custodianKind, CustodianKind.provider);
      expect(s.custodianId, '998902220002');
      expect(s.legIds, ['LEG1']);
      expect(s.assignedProviderIds, ['998902220002']);
      expect(s.needsPayment, isFalse);
      expect(s.secretsAvailable, isTrue);
      expect(s.origin?.addressText, 'Gurlan, Markaz 1');
      expect(s.createdAt, isNotNull);
    });

    test('Shipment (етказилган) — сирлар ёпиқ, бекор қилиб бўлмайди', () {
      final s = Shipment.fromMap('SHIP1', doc('shipmentDelivered'));
      expect(s.status, ShipmentStatus.delivered);
      expect(s.custodianKind, CustodianKind.recipient);
      expect(s.custodianId, isNull);
      expect(s.secretsAvailable, isFalse);
      expect(s.status.isCancellable, isFalse);
      expect(s.deliveredAt, isNotNull);
    });

    test('LogisticsOrder', () {
      final o = LogisticsOrder.fromMap('ORDER1', doc('order'));
      expect(o.ownerId, '998901110001');
      expect(o.status, 'delivered');
      expect(o.l10nStatusKey, 'logistics_order_delivered');
      expect(o.shipmentIds, ['SHIP1']);
      expect(o.trackingNumbers, ['AVA-26-1007-000001']);
      expect(o.customerPriceTotal, 10000);
      expect(o.recipientName, 'Olim aka');
      expect(o.recipientPhone, '998905556677',
          reason: 'қабул қилувчи телефони ФАҚАТ буюртмада (40-банд)');
      expect(o.destination?.districtId, 'gurlan');
    });

    test('CustodyEvent — олиш (жўнатувчи → ижрочи)', () {
      final e = CustodyEvent.fromMap('SHIP1_LEG1_pickup', doc('pickupEvent'));
      expect(e.kind, 'pickup');
      expect(e.isDelivery, isFalse);
      expect(e.fromKind, CustodianKind.sender);
      expect(e.toKind, CustodianKind.provider);
      expect(e.toId, '998902220002');
      expect(e.l10nKey, 'logistics_event_picked_up');
      expect(e.conditionFlags, ['intact']);
      expect(e.photoUrls.length, 1);
      expect(e.timestamp, isNotNull);
    });

    test('CustodyEvent — етказиш (ижрочи → қабул қилувчи)', () {
      final e = CustodyEvent.fromMap('SHIP1_LEG1_delivery', doc('deliveryEvent'));
      expect(e.isDelivery, isTrue);
      expect(e.toKind, CustodianKind.recipient);
      expect(e.toId, isNull);
      expect(e.l10nKey, 'logistics_event_delivered');
    });

    test('DemandMatch (logistics) + LegProjection — 1-поғона', () {
      final m = DemandMatch.fromMap('LEG1_998902220002', doc('matchAccepted'));
      expect(m.module, DemandModule.logistics);
      expect(m.status, MatchStatus.accepted);
      final leg = LegProjection.fromAttributes(m.projection.attributes);
      expect(leg.shipmentId, 'SHIP1');
      expect(leg.trackingNumber, 'AVA-26-1007-000001');
      expect(leg.payout, 8000, reason: 'ижрочи ҳақни кўради');
      expect(leg.legCount, 1);
      expect(leg.isLastLeg, isTrue);
      expect(leg.chargeableWeightG, 800);
      expect(m.contact, isNotNull);
      expect(m.contact!.stage, 1);
      expect(m.contact!.ownerPhone, '998901110001');
      expect(m.contact!.hasRecipient, isFalse, reason: 'Т-9: қабул қилувчи ҳали ёпиқ');
    });

    test('DemandMatch — 2-поғона (посилка олингандан кейин)', () {
      final m = DemandMatch.fromMap('LEG1_998902220002', doc('matchInProgress'));
      expect(m.status, MatchStatus.inProgress);
      expect(m.contact!.stage, 2);
      expect(m.contact!.hasRecipient, isTrue);
      expect(m.contact!.recipientPhone, '998905556677');
      expect(m.contact!.recipientName, 'Olim aka');
      expect(m.contact!.deliveryCodeRequired, isTrue);
      expect(m.contact!.dropoffAddress, "Gurlan, Bog'cha 5");
      expect(m.isVisibleAt(DateTime.parse('2026-10-07T00:00:00Z')), isTrue);
    });

    test('МАХФИЙЛИК: проекцияда телефон, аниқ манзил ва мижоз нархи ЙЎҚ', () {
      final m = DemandMatch.fromMap('k', doc('matchAccepted'));
      final text = json.encode({
        'title': m.projection.title,
        'description': m.projection.description,
        'attributes': m.projection.attributes,
      });
      expect(RegExp(r'998\d{9}').hasMatch(text), isFalse);
      expect(text.contains('Markaz 1'), isFalse);
      expect(text.contains("Bog'cha"), isFalse);
      expect(m.projection.attributes.containsKey('customerPrice'), isFalse,
          reason: '14-банд: мижоз нархи ижрочига кўрсатилмайди');
    });

    test('callable натижалари', () {
      final q = LogisticsQuote.fromMap(doc('quoteResult'));
      expect(q.total, 10000);
      expect(q.tariffVersion, 7);
      expect(q.parcels.single.customerPrice, 10000);
      expect(q.parcels.single.volumetricWeightG, 500);

      final r = CreateOrderResult.fromMap(doc('createResult'));
      expect(r.orderId, 'ORDER1');
      expect(r.shipmentIds, ['SHIP1']);
      expect(r.duplicate, isFalse);
      expect(r.total, 10000);

      final s = ShipmentSecrets.fromMap(doc('secretsResult'));
      expect(s.qrPayload.startsWith(fx['qrPrefix'] as String), isTrue);
      expect(s.handoverCode.length, 6);
      expect(s.deliveryCode, isNotNull, reason: 'эгасига етказиш коди ҳам келади');
      expect(RegExp(fx['trackingPattern'] as String).hasMatch(s.trackingNumber), isTrue);
    });
  });
}
