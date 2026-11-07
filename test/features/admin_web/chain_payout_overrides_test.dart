// Админ: бўлак ҳақини қўлда бериш — текширув ва диалог (эга 2026-11-07).
//
//   flutter test test/features/admin_web/chain_payout_overrides_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/admin_web/utils/chain_payout_overrides.dart';
import 'package:ava_gurlan/features/admin_web/widgets/logistics_chain_legs_dialog.dart';
import 'package:ava_gurlan/features/logistics/domain/logistics_models.dart';

ChainLegRow _leg(int i, int? payout, {String? provider}) => ChainLegRow(
      legId: 'L$i',
      legIndex: i,
      status: 'open',
      from: {'regionId': 'xorazm', 'districtId': 'd$i'},
      to: {'regionId': 'xorazm', 'districtId': 'd${i + 1}'},
      payout: payout,
      providerId: provider,
    );

void main() {
  group('parseAdminSum', () {
    test('бутун сон, бўшлиқлар', () {
      expect(parseAdminSum('48000'), 48000);
      expect(parseAdminSum(' 48 000 '), 48000);
      expect(parseAdminSum('48 000'), 48000);
    });
    test('рад: бўш, каср, ҳарф', () {
      expect(parseAdminSum(''), isNull);
      expect(parseAdminSum('48000.5'), isNull);
      expect(parseAdminSum('48,5'), isNull);
      expect(parseAdminSum('abc'), isNull);
    });
  });

  group('validatePayoutOverrides', () {
    test('тўғри: йиғинди = пул → [{legIndex, amount}]', () {
      final r = validatePayoutOverrides(['50000', '90000', '52000'], pool: 192000);
      expect(r.isValid, isTrue);
      expect(r.overrides, [
        {'legIndex': 0, 'amount': 50000},
        {'legIndex': 1, 'amount': 90000},
        {'legIndex': 2, 'amount': 52000},
      ]);
      expect(r.sum, 192000);
    });

    test('чегара: битта бўлак = бутун пул', () {
      final r = validatePayoutOverrides(['192000'], pool: 192000);
      expect(r.isValid, isTrue);
    });

    test('рад: йиғинди кам/кўп (1 сўм фарқ ҳам)', () {
      final less = validatePayoutOverrides(['48000', '96000', '47999'], pool: 192000);
      expect(less.isValid, isFalse);
      expect(less.error, contains('-1'));
      final more = validatePayoutOverrides(['48000', '96000', '48001'], pool: 192000);
      expect(more.isValid, isFalse);
      expect(more.error, contains('+1'));
    });

    test('рад: каср, манфий, 0, бўш', () {
      expect(validatePayoutOverrides(['96000.5', '96000'], pool: 192000).isValid, isFalse);
      expect(validatePayoutOverrides(['-1000', '193000'], pool: 192000).isValid, isFalse);
      expect(validatePayoutOverrides(['0', '192000'], pool: 192000).isValid, isFalse);
      expect(validatePayoutOverrides(['', '192000'], pool: 192000).isValid, isFalse);
    });

    test('рад: пул номаълум ёки бўлак йўқ', () {
      expect(validatePayoutOverrides(['1000'], pool: null).isValid, isFalse);
      expect(validatePayoutOverrides(['1000'], pool: 0).isValid, isFalse);
      expect(validatePayoutOverrides(const [], pool: 1000).isValid, isFalse);
    });
  });

  group('ChainLegRow / пул', () {
    test('demands ҳужжатидан: legAssignments устун, payout, нуқталар', () {
      final r = ChainLegRow.fromDemand(
        'L1',
        {
          'status': 'accepted',
          'location': {'regionId': 'xorazm', 'districtId': 'urganch', 'lat': 1.0},
          'destination': {'regionId': 'toshkent_shahri', 'districtId': ''},
          'attributes': {'legIndex': 1, 'payout': 96000},
          'assignment': {'providerId': 'OLD'},
        },
        legAssignments: {'L1': 'K1'},
      );
      expect(r.legIndex, 1);
      expect(r.providerId, 'K1');
      expect(r.payout, 96000);
      expect(r.from, {'regionId': 'xorazm', 'districtId': 'urganch'});
      expect(r.to, {'regionId': 'toshkent_shahri', 'districtId': ''});
      expect(r.routeLabel, 'urganch → toshkent_shahri');
    });

    test('курьер йўқ, payout йўқ — null', () {
      final r = ChainLegRow.fromDemand('L0', {'status': 'open'}, fallbackIndex: 0);
      expect(r.providerId, isNull);
      expect(r.payout, isNull);
    });

    test('пул = ҳақлар йиғиндиси; биттаси номаълум — null', () {
      expect(chainProviderPool([_leg(0, 48000), _leg(1, 96000), _leg(2, 48000)]), 192000);
      expect(chainProviderPool([_leg(0, 48000), _leg(1, null)]), isNull);
      expect(chainProviderPool(const []), isNull);
    });

    test('қисқа ҳолат матни', () {
      final line = chainSummaryLine(
        ShipmentChain(
          mode: ChainMode.assembleAll,
          state: ChainState.assembling,
          deadlineAt: DateTime(2026, 11, 9, 14, 5),
          claimed: 2,
          legCount: 3,
        ),
        fmt: (d) => '${d.day}.${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}',
      );
      expect(line, 'Бўлаклар: йиғилмоқда 2/3 · муддат 9.11 14:05');
    });
  });

  group('PayoutOverrideDialog', () {
    Future<void> open(WidgetTester tester, List<ChainLegRow> legs) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<(List<Map<String, int>>, String)>(
                  context: ctx,
                  builder: (_) => PayoutOverrideDialog(legs: legs),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    FilledButton saveButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const ValueKey('chain-payout-save')));

    testWidgets('йиғинди нотўғри — «Сақлаш» ёпиқ; тўғри + сабаб — натижа қайтади', (tester) async {
      final legs = [_leg(0, 48000), _leg(1, 96000), _leg(2, 48000)];
      await open(tester, legs);
      // Бошланғич қийматлар = жорий ҳақлар (йиғинди тўғри), лекин сабаб йўқ.
      expect(saveButton(tester).onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('chain-payout-reason')), 'Toshkent yo\'li qimmat');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNotNull);

      await tester.enterText(find.byKey(const ValueKey('chain-payout-1')), '100000');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull, reason: 'йиғинди 196000 ≠ 192000');
      expect(find.textContaining('+4000'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('chain-payout-0')), '44000');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('«Сақлаш» — overrides ва сабаб қайтарилади', (tester) async {
      (List<Map<String, int>>, String)? result;
      final legs = [_leg(0, 60000), _leg(1, 40000)];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showDialog<(List<Map<String, int>>, String)>(
                  context: ctx,
                  builder: (_) => PayoutOverrideDialog(legs: legs),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('chain-payout-0')), '70 000');
      await tester.enterText(find.byKey(const ValueKey('chain-payout-1')), '30000');
      await tester.enterText(find.byKey(const ValueKey('chain-payout-reason')), 'uzoq yo\'l');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chain-payout-save')));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.$1, [
        {'legIndex': 0, 'amount': 70000},
        {'legIndex': 1, 'amount': 30000},
      ]);
      expect(result!.$2, 'uzoq yo\'l');
    });

    testWidgets('пул номаълум — хато матни, «Сақлаш» ёпиқ', (tester) async {
      await open(tester, [_leg(0, null), _leg(1, 1000)]);
      await tester.enterText(find.byKey(const ValueKey('chain-payout-reason')), 'sabab');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull);
      expect(find.textContaining('Ижрочилар пули номаълум'), findsOneWidget);
    });
  });
}
