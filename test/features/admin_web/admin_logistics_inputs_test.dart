// Admin AVA Logistics (D1/D8): sof mantiq — yo'qolgan posilka javobi, so'm kiritish,
// bosqich konfigi, telefon, divisor, xato matni.
//
//   flutter test test/features/admin_web/admin_logistics_inputs_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/admin_web/services/admin_callable.dart';
import 'package:ava_gurlan/features/admin_web/utils/logistics_stage.dart';
import 'package:ava_gurlan/features/admin_web/utils/logistics_tariff_inputs.dart';
import 'package:ava_gurlan/features/admin_web/utils/loss_incident.dart';

void main() {
  group('parsePositiveSom', () {
    test('musbat butun', () {
      expect(parsePositiveSom('35000'), 35000);
      expect(parsePositiveSom(' 35 000 '), 35000);
      expect(parsePositiveSom('1'), 1);
    });
    test('0, manfiy, o\'nli, harf, bo\'sh, juda uzun — null', () {
      for (final s in ['', ' ', '0', '000', '-5', '1.5', '1,5', '12a', 'abc', '1234567890123']) {
        expect(parsePositiveSom(s), isNull, reason: '"$s"');
      }
    });
  });

  group('LossIncident', () {
    test('to\'liq javob', () {
      final list = LossIncident.parseList([
        {
          'id': 'S1', 'shipmentId': 'S1', 'status': 'settled', 'goodsValue': 100000,
          'refundedNow': 60000, 'outstanding': 40000, 'declaredAtMs': 1760000000000,
          'courier': '99890***4567', 'reason': 'yo\'qoldi', 'trackingNumber': 'AVA-26-1007-000001',
        },
      ]);
      expect(list.single.goodsValue, 100000);
      expect(list.single.outstanding, 40000);
      expect(list.single.canRecordPayment, isTrue);
      expect(list.single.courierPhoneMasked, '99890***4567', reason: 'eski "courier" kaliti ham o\'qiladi');
      expect(list.single.declaredAt, isNotNull);
    });

    test('server javobi (adminListLossIncidents) — hamma maydon', () {
      final i = LossIncident.fromMap({
        'id': 'S9', 'shipmentId': 'S9', 'trackingNumber': 'AVA-26-1007-000009', 'status': 'repaid',
        'goodsValue': 100000, 'refundedNow': 60000, 'outstanding': 0, 'paidTotal': 40000,
        'declaredAtMs': 1760000000000, 'courierPhoneMasked': '***4567', 'courierAccountId': 'acc_1',
        'reason': 'yo\'qoldi', 'legId': 'L2',
      });
      expect(i.courierPhoneMasked, '***4567');
      expect(i.courierAccountId, 'acc_1');
      expect(i.paidTotal, 40000);
      expect(i.legId, 'L2');
      expect(i.trackingNumber, 'AVA-26-1007-000009');
      expect(i.declaredAtMs, 1760000000000);
      expect(i.outstanding, 0);
      expect(i.canRecordPayment, isFalse);
    });

    test('refundedNow/outstanding/paidTotal null = hisoblanmagan: 0 emas, "-" ko\'rsatiladi', () {
      final i = LossIncident.fromMap({
        'id': 'S8', 'shipmentId': 'S8', 'status': 'declared', 'goodsValue': 50000,
        'refundedNow': null, 'outstanding': null, 'paidTotal': null,
        'courierPhoneMasked': '', 'courierAccountId': '', 'legId': '',
      });
      expect(i.refundedNow, isNull);
      expect(i.outstanding, isNull);
      expect(i.paidTotal, isNull);
      expect(i.canRecordPayment, isFalse, reason: 'qarz hisoblanmaguncha to\'lov taklif qilinmaydi');
      expect(lossMoneyText(i.refundedNow), '-');
      expect(lossMoneyText(i.outstanding), '-');
      expect(lossMoneyText(i.goodsValue), '50 000');
      expect(lossMoneyText(0), '0');
    });

    test('courierPhoneMasked eski "courier" kalitidan ustun', () {
      final i = LossIncident.fromMap({
        'shipmentId': 'S7', 'courierPhoneMasked': '***1111', 'courier': '***2222',
      });
      expect(i.courierPhoneMasked, '***1111');
    });

    test('maydonlar yo\'q / noto\'g\'ri tur — yiqilmaydi', () {
      final list = LossIncident.parseList([
        {'shipmentId': 'S2'},
        {'shipmentId': 'S3', 'goodsValue': 'x', 'outstanding': null, 'courier': {'masked': '***1'}},
        'axlat',
        42,
      ]);
      expect(list.length, 2);
      expect(list[0].id, 'S2');
      expect(list[0].outstanding, isNull);
      expect(list[0].canRecordPayment, isFalse);
      expect(list[1].goodsValue, isNull, reason: 'noto\'g\'ri tur — null, 0 emas');
      expect(list[1].courierPhoneMasked, '***1');
      expect(LossIncident.parseList(null), isEmpty);
      expect(LossIncident.parseList({'a': 1}), isEmpty);
    });

    test('holat matnlari; noma\'lum holat o\'zi', () {
      expect(lossStatusLabel('declared'), isNot('declared'));
      expect(lossStatusLabel('repaid'), isNot('repaid'));
      expect(lossStatusLabel('kelajak'), 'kelajak');
      expect(lossStatusLabel(''), '—');
    });
  });

  group('LogisticsStageConfig', () {
    test('serverdagi qiymat', () {
      final c = LogisticsStageConfig.fromDoc({
        'logistics': {'stage': 'pilot', 'testerIds': ['998901234567', 7]},
      }, exists: true);
      expect(c.stage, 'pilot');
      expect(c.testerIds, ['998901234567', '7']);
    });
    test('yo\'q/noto\'g\'ri bosqich — internal (server stageOf kabi)', () {
      expect(LogisticsStageConfig.fromDoc(null, exists: false).stage, 'internal');
      expect(LogisticsStageConfig.fromDoc({'logistics': {'stage': 'xx'}}, exists: true).stage, 'internal');
      expect(LogisticsStageConfig.fromDoc({'logistics': 5}, exists: true).testerIds, isEmpty);
    });
    test('4 ta bosqich va matnlari', () {
      expect(kLogisticsStages, ['off', 'internal', 'pilot', 'public']);
      for (final s in kLogisticsStages) {
        expect(kLogisticsStageLabels[s], isNotNull);
      }
    });
  });

  group('normalizeTesterPhone / testerListContains', () {
    test('qabul', () {
      expect(normalizeTesterPhone('90 123 45 67'), '901234567');
      expect(normalizeTesterPhone('+998 90 123-45-67'), '998901234567');
    });
    test('rad', () {
      for (final s in ['', '123', '9012345678', '997901234567', '99890123456']) {
        expect(normalizeTesterPhone(s), isNull, reason: s);
      }
    });
    test('ro\'yxatda bor (9 va 12 xonali teng)', () {
      expect(testerListContains(['998901234567'], '901234567'), isTrue);
      expect(testerListContains(['901234567'], '998901234567'), isTrue);
      expect(testerListContains(['998901234567'], '998909999999'), isFalse);
    });
  });

  group('parseVolumetricDivisor', () {
    test('bo\'sh — o\'zgartirilmaydi', () {
      final r = parseVolumetricDivisor('  ');
      expect(r.value, isNull);
      expect(r.error, isNull);
    });
    test('musbat butun', () {
      expect(parseVolumetricDivisor('6000').value, 6000);
      expect(parseVolumetricDivisor('5 000').value, 5000);
    });
    test('0, manfiy, o\'nli, harf — xato', () {
      for (final s in ['0', '-1', '5000.5', '5000,5', 'abc']) {
        final r = parseVolumetricDivisor(s);
        expect(r.value, isNull, reason: s);
        expect(r.error, isNotNull, reason: s);
      }
    });
  });

  group('adminErrorText', () {
    test('ma\'lum reason — matn; tizim kodi ko\'rsatilmaydi', () {
      final t = adminErrorText(const AdminCallableException(
          'failed-precondition', 'shipment_not_lossable', 'x'));
      expect(t.contains('shipment_not_lossable'), isFalse);
      expect(t, isNotEmpty);
    });
    test('permission-denied', () {
      final t = adminErrorText(const AdminCallableException('permission-denied', '', 'denied'));
      expect(t.contains('Рухсат'), isTrue);
    });
    test('noma\'lum reason — xabar + reason', () {
      final t = adminErrorText(const AdminCallableException('internal', 'weird', 'boom'));
      expect(t, 'boom (weird)');
    });
    test('boshqa xato turi', () {
      expect(adminErrorText(StateError('s')), contains('s'));
    });
  });
}
