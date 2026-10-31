// Admin «Kuryer xizmat haqi» (AVA Logistics): % ↔ bps, namuna hisobi, ekran.
//
//   flutter test test/features/admin_web/courier_service_fee_admin_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/core/utils/wallet_ledger_labels.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_callable.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_courier_payout_service.dart';
import 'package:ava_gurlan/features/admin_web/utils/courier_service_fee_admin.dart';
import 'package:ava_gurlan/features/admin_web/widgets/courier_service_fee_panel.dart';
import 'package:ava_gurlan/models/wallet_ledger_entry.dart';

class _FakeCallable implements AdminCallable {
  _FakeCallable(this.handler);

  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> payload) handler;
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> payload) {
    calls.add((name, payload));
    return handler(name, payload);
  }
}

String _tr(String key, [Map<String, String>? params]) =>
    params == null ? '<$key>' : '<$key:${params.entries.map((e) => '${e.key}=${e.value}').join(',')}>';

void main() {
  group('courierServiceFee (server formulasi bilan bir xil: ceil)', () {
    test('chegaralar', () {
      expect(courierServiceFee(96000, 0), 0);
      expect(courierServiceFee(96000, 1), 10);
      expect(courierServiceFee(10000, 1), 1);
      expect(courierServiceFee(9999, 1), 1);
      expect(courierServiceFee(96001, 5000), 48001);
      expect(courierServiceFee(1, 5000), 1);
      expect(courierServiceFee(40000, 1250), 5000);
    });
    test('namuna: 40 000 so\'m', () {
      final e = courierFeeExample(1000);
      expect([e.gross, e.fee, e.net], [40000, 4000, 36000]);
      final z = courierFeeExample(0);
      expect([z.fee, z.net], [0, 40000]);
      final c = courierFeeExample(333); // 1332 → ceil
      expect([c.fee, c.net], [1332, 38668]);
    });
  });

  group('planCourierFeeChange (% → bps)', () {
    test('qabul: 0, 0,01, 2,5, 12.75, 50', () {
      expect(planCourierFeeChange(currentBps: null, text: '0').bps, 0);
      expect(planCourierFeeChange(currentBps: null, text: '0,01').bps, 1);
      expect(planCourierFeeChange(currentBps: null, text: '2,5').bps, 250);
      expect(planCourierFeeChange(currentBps: null, text: '12.75').bps, 1275);
      expect(planCourierFeeChange(currentBps: null, text: '50').bps, 5000);
    });
    test('rad: bo\'sh, 50.01, 51, manfiy, 3 xona kasr, harf', () {
      for (final t in ['', ' ', '50.01', '51', '-1', '1.234', 'abc', '1,2,3']) {
        final p = planCourierFeeChange(currentBps: 100, text: t);
        expect(p.error, isNotNull, reason: t);
        expect(p.changed, isFalse, reason: t);
      }
    });
    test('bir xil qiymat — o\'zgarish yo\'q', () {
      expect(planCourierFeeChange(currentBps: 250, text: '2,5').changed, isFalse);
      expect(planCourierFeeChange(currentBps: 250, text: '2.6').changed, isTrue);
    });
  });

  group('CourierServiceFeeState.fromMap', () {
    test('server javobi', () {
      final s = CourierServiceFeeState.fromMap({
        'ok': true,
        'configured': true,
        'valid': true,
        'feeBps': 250,
        'feeVersion': 3,
        'autoPayoutEnabled': false,
        'updatedBy': '998909990000',
        'feeAccountBalance': 1000,
        'recentPayouts': [
          {'key': 'courierPayout:S:l0', 'gross': 40000, 'fee': 1000, 'net': 39000, 'feeVersion': 3},
        ],
        'openAnomalies': [
          {'key': 'courierPayout:S:l1', 'reason': 'user_missing', 'amount': 500, 'attempts': 2},
          'axlat',
        ],
      });
      expect(s.percentText, '2.5');
      expect(s.autoPayoutEnabled, isFalse);
      expect(s.recentPayouts.single.net, 39000);
      expect(s.openAnomalies.single.reason, 'user_missing');
      expect(courierFeeAnomalyLabel('payable_insufficient'), contains('етмайди'));
    });
    test('bo\'sh javob: yoqilgan, 0 bps emas — null (bilinmaydi)', () {
      final s = CourierServiceFeeState.fromMap({});
      expect(s.autoPayoutEnabled, isTrue);
      expect(s.feeBps, isNull);
      expect(s.recentPayouts, isEmpty);
    });
  });

  group('hamyon yozuvi courier_payout', () {
    test('sarlavha va xizmat haqi izohi kalit orqali', () {
      final e = WalletLedgerEntry(
        id: 'w', type: 'courier_payout', amount: 36000, createdAt: DateTime(2026, 10, 31),
        module: '', refType: 'shipment', refId: 'S1', meta: const {'fee': 4000},
      );
      expect(walletLedgerTitle(e, _tr), '<wlt_l_courier_payout>');
      expect(walletLedgerSubtitle(e, _tr), startsWith('<wlt_l_courier_fee:amount='));
    });
    test('3 tilda kalitlar bor', () {
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final m = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
        expect(m['wlt_l_courier_payout'], isA<String>(), reason: lang);
        expect(m['wlt_l_courier_fee'], contains('{amount}'), reason: lang);
      }
    });
  });

  group('panel (soxta callable)', () {
    Map<String, dynamic> state({int bps = 1000, int ver = 1, bool auto = true}) => {
          'ok': true,
          'configured': true,
          'valid': true,
          'feeBps': bps,
          'feeVersion': ver,
          'autoPayoutEnabled': auto,
          'updatedBy': '998909990000',
          'feeAccountBalance': 4000,
          'recentPayouts': [
            {'key': 'courierPayout:shpA:leg0', 'shipmentId': 'shpA', 'legId': 'leg0', 'providerId': '998902220002',
              'gross': 40000, 'fee': 4000, 'net': 36000, 'feeVersion': 1},
          ],
          'openAnomalies': [
            {'key': 'courierPayout:shpB:leg0', 'shipmentId': 'shpB', 'legId': 'leg0', 'providerId': '998906660006',
              'amount': 30000, 'reason': 'user_missing', 'attempts': 3},
          ],
        };

    Future<void> pump(WidgetTester tester, _FakeCallable fake) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CourierServiceFeePanel(service: AdminCourierPayoutService(callable: fake))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('joriy %, namuna, ro\'yxatlar; % o\'zgarsa namuna yangilanadi; saqlash bps + sabab yuboradi', (tester) async {
      var bps = 1000;
      final fake = _FakeCallable((name, p) async {
        if (name == 'adminGetCourierServiceFee') return state(bps: bps, ver: bps == 1000 ? 1 : 2);
        if (name == 'adminSetCourierServiceFee') {
          bps = p['feeBps'] as int;
          return {'ok': true, 'feeVersion': 2, 'unchanged': false, 'feeBps': bps, 'autoPayoutEnabled': true};
        }
        return {};
      });
      await pump(tester, fake);
      expect(fake.calls.first.$1, 'adminGetCourierServiceFee');
      expect(find.textContaining('Ҳозир: 10 %'), findsOneWidget);
      expect(find.textContaining('40 000 сўм ишлаб топилди → хизмат ҳақи 4 000 сўм → ҳамёнга 36 000 сўм'), findsOneWidget);
      expect(find.text('Курьер фойдаланувчиси топилмади'), findsOneWidget);
      expect(find.text('40 000 − 4 000 = 36 000 сўм'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('courierFeePct')), '2,5');
      await tester.pump();
      expect(find.textContaining('хизмат ҳақи 1 000 сўм → ҳамёнга 39 000 сўм'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('courierFeePct')), '60');
      await tester.pump();
      expect(find.textContaining('0..50'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Сақлаш'));
      await tester.pumpAndSettle();
      expect(fake.calls.where((c) => c.$1 == 'adminSetCourierServiceFee'), isEmpty, reason: '60 % serverga ketmaydi');

      await tester.enterText(find.byKey(const ValueKey('courierFeePct')), '2,5');
      await tester.tap(find.widgetWithText(FilledButton, 'Сақлаш'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ҳамёнга 39 000 сўм'), findsWidgets, reason: 'dialogda ham namuna');
      await tester.enterText(find.byType(TextField).last, 'ega qarori');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Тасдиқлаш'));
      await tester.pumpAndSettle();
      final set = fake.calls.firstWhere((c) => c.$1 == 'adminSetCourierServiceFee');
      expect(set.$2, {'feeBps': 250, 'reason': 'ega qarori'});
      expect(find.textContaining('Ҳозир: 2.5 %'), findsOneWidget);
    });

    testWidgets('avto-to\'lov kaliti: faqat autoPayoutEnabled + sabab yuboriladi', (tester) async {
      final fake = _FakeCallable((name, p) async {
        if (name == 'adminGetCourierServiceFee') return state();
        return {'ok': true, 'feeVersion': 2, 'unchanged': false};
      });
      await pump(tester, fake);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'tekshiruv');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Тасдиқлаш'));
      await tester.pumpAndSettle();
      final set = fake.calls.firstWhere((c) => c.$1 == 'adminSetCourierServiceFee');
      expect(set.$2, {'autoPayoutEnabled': false, 'reason': 'tekshiruv'});
    });

    testWidgets('xato: rad matni ko\'rsatiladi', (tester) async {
      final fake = _FakeCallable((name, p) async =>
          throw const AdminCallableException('permission-denied', '', 'Admin role required'));
      await pump(tester, fake);
      expect(find.textContaining('Рухсат йўқ'), findsOneWidget);
    });
  });
}
