// «Автомобил суғуртаси» (эга 2026-11-28): соф ёрдамчилар, бош саҳифа бўлими (сервер босқичи), экран
// (мой дастури жараёни, нарх, аризалар, «Суғурталанган» белгиси ЙЎҚ), 3 тил калитлари.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/admin_web/screens/car_insurance_admin_screen.dart';
import 'package:ava_gurlan/features/car_insurance/car_insurance_service.dart';
import 'package:ava_gurlan/features/car_insurance/screens/car_insurance_screen.dart';
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/core/utils/wallet_ledger_labels.dart';
import 'package:ava_gurlan/models/wallet_ledger_entry.dart';
import 'package:ava_gurlan/features/car_insurance/widgets/car_insurance_home_section.dart';
import 'package:ava_gurlan/features/car_insurance/widgets/car_insurance_offer_prompt.dart';
import 'package:ava_gurlan/features/home/widgets/home_lite_cards.dart';
import 'package:ava_gurlan/services/push_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

class _FakeSvc extends CarInsuranceService {
  _FakeSvc(this.state);
  final InsuranceState state;
  final calls = <String>[];

  @override
  Future<InsuranceState> myState() async => state;

  @override
  Future<void> chooseCarOffer(String option) async => calls.add('choose:$option');
}

InsuranceState _state({InsuranceEnrollment? enrollment, InsuranceCampaign? campaign, String expiresOn = ''}) => InsuranceState.fromMap({
      'available': true,
      'tariffVersion': 3,
      'options': [
        {'policyType': 'osago', 'vehicleType': 'car', 'termMonths': 12, 'price': 200000},
        {'policyType': 'osago', 'vehicleType': 'car', 'termMonths': 6, 'price': 120000},
      ],
      'car': {'brand': 'Chevrolet', 'model': 'Cobalt', 'year': 2020, 'plate': '01 A 123 BC', 'complete': true},
      'carInsurance': expiresOn.isEmpty ? null : {'expiresOn': expiresOn, 'policyType': 'osago', 'source': 'ava'},
    }).copyWithForTest(enrollment: enrollment, campaign: campaign);

extension on InsuranceState {
  InsuranceState copyWithForTest({InsuranceEnrollment? enrollment, InsuranceCampaign? campaign}) => InsuranceState(
        available: available,
        options: options,
        tariffVersion: tariffVersion,
        carModel: carModel,
        carBrand: carBrand,
        carPlate: carPlate,
        carYear: carYear,
        carComplete: carComplete,
        expiresOn: expiresOn,
        policyType: policyType,
        expirySource: expirySource,
        campaign: campaign,
        enrollment: enrollment,
      );
}

void main() {
  group('соф', () {
    test('қолган кун, сана кўриниши, калит', () {
      expect(insuranceDaysLeft('2026-12-02', DateTime(2026, 11, 28, 23)), 4);
      expect(insuranceDaysLeft('2026-11-27', DateTime(2026, 11, 28)), -1);
      expect(insuranceDaysLeft('', DateTime(2026, 11, 28)), isNull);
      expect(insuranceDisplayDate('2027-11-28'), '28.11.2027');
      expect(insuranceDateKey(DateTime(2027, 1, 3)), '2027-01-03');
    });

    test('мой дастури жараёни: 1/2 → 50%, ишлатилган → 0%, бонус — null', () {
      const e1 = InsuranceEnrollment(year: 2026, option: 'oil', plate: 'X', oilChanges: 1, oilGoal: 2, discountPct: 50, discountUsed: false);
      expect(insuranceOilProgress(e1), (n: 1, goal: 2, pct: 50));
      const used = InsuranceEnrollment(year: 2026, option: 'oil', plate: 'X', oilChanges: 2, oilGoal: 2, discountPct: 100, discountUsed: true);
      expect(insuranceOilProgress(used)!.pct, 0);
      const bonus = InsuranceEnrollment(year: 2026, option: 'bonus', plate: 'X', oilChanges: 0, oilGoal: 0, discountPct: 0, discountUsed: false);
      expect(insuranceOilProgress(bonus), isNull);
    });

    test('ҳолат map: танловлар, машина, кампания қадамлари; ариза map', () {
      final s = InsuranceState.fromMap({
        'available': true,
        'campaign': {'year': 2026, 'bonusEnabled': true, 'bonusAmount': 100000, 'oilEnabled': true, 'oilSteps': [{'count': 1, 'pct': 50}, {'count': 2, 'pct': 100}]},
      });
      expect(s.campaign!.oilSteps.map((x) => x.pct), [50, 100]);
      final r = InsuranceRequest.fromMap('ins_1', {'status': 'issued', 'policy': {'number': 'AB 1', 'validTo': '2027-11-28'}, 'car': {'plate': 'P'}, 'createdAtMs': 1000});
      expect([r.policyNumber, r.validTo, r.carPlate, r.createdAt!.millisecondsSinceEpoch], ['AB 1', '2027-11-28', 'P', 1000]);
      expect(insuranceStatusKey('in_progress'), 'ins_status_in_progress');
      expect(insuranceStatusKey('weird'), 'ins_status_requested');
    });

    test('админ: рўйхат ва мой босқичлари таҳлили', () {
      expect(splitList('901234567, 998901111111\n 22'), ['901234567', '998901111111', '22']);
      expect(parseOilSteps('1:50, 2:100'), [
        {'count': 1, 'pct': 50},
        {'count': 2, 'pct': 100},
      ]);
      expect(parseOilSteps('1-50'), isNull);
      expect(parseOilSteps(''), isNull);
    });
  });

  group('бош саҳифа карточкаси (дарвоза — сервер босқичи)', () {
    setUp(resetCarInsuranceStateCache);

    test('ёпиқ / хато / телефон йўқ — кўринмайди; очиқ — кўринади; кешли', () async {
      expect(await carInsuranceHomeVisible('998901234567', loader: () async => InsuranceState.unavailable), isFalse);
      resetCarInsuranceStateCache();
      expect(await carInsuranceHomeVisible('998901234567', loader: () async => throw StateError('x')), isFalse);
      expect(await carInsuranceHomeVisible('', loader: () async => _state()), isFalse);
      var n = 0;
      Future<InsuranceState> load() async {
        n++;
        return _state();
      }

      expect(await carInsuranceHomeVisible('998901234567', loader: load), isTrue);
      expect(await carInsuranceHomeVisible('998901234567', loader: load), isTrue);
      expect(n, 1, reason: 'сессия кеши — бир callable');
      await carInsuranceHomeVisible('998901234567', loader: load, refresh: true);
      expect(n, 2);
    });

    testWidgets('карточка маълумоти: id, эга расми, матн', (t) async {
      final d = JsonL10nDelegate();
      late HomeLiteCardData card;
      await t.pumpWidget(l10nApp(
        delegate: d,
        home: Builder(builder: (ctx) {
          card = carInsuranceHomeCard(ctx, phone: '998901234567');
          return const SizedBox();
        }),
      ));
      await t.pumpAndSettle();
      expect(card.id, kCarInsuranceHomeCardId);
      expect(card.title, d.tr('ins_home_title'));
      expect(card.imagePath, 'assets/images/services/card_car_insurance_v1.webp');
      expect(File(kCarInsuranceCardImage).existsSync(), isTrue);
    });
  });

  group('машина рағбати (рўйхатдан ўтгач)', () {
    setUp(resetCarInsuranceStateCache);
    const c = InsuranceCampaign(year: 2026, bonusEnabled: true, bonusAmount: 100000, bonusValidityDays: 60, oilEnabled: true, oilSteps: [InsuranceOilStep(1, 50), InsuranceOilStep(2, 100)]);
    const e = InsuranceEnrollment(year: 2026, option: 'bonus', plate: 'X', oilChanges: 0, oilGoal: 0, discountPct: 0, discountUsed: false);

    test('қачон таклиф қилинади', () {
      expect(carInsuranceOfferDue(_state(campaign: c)), isTrue);
      expect(carInsuranceOfferDue(_state(campaign: c, enrollment: e)), isFalse, reason: 'аллақачон танланган');
      expect(carInsuranceOfferDue(_state()), isFalse, reason: 'кампания йўқ');
      expect(carInsuranceOfferDue(InsuranceState.unavailable), isFalse);
    });

    testWidgets('бонус танланади — сервер чақирилади; кампания йўқ — ойна йўқ', (t) async {
      final d = JsonL10nDelegate();
      final svc = _FakeSvc(_state(campaign: c));
      await t.pumpWidget(l10nApp(
        delegate: d,
        home: Scaffold(body: Builder(builder: (ctx) => TextButton(onPressed: () => maybeOfferCarInsuranceIncentive(ctx, '998901234567', service: svc), child: const Text('go')))),
      ));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text(d.tr('ins_offer_bonus').replaceAll('{amount}', formatMoney(100000))), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ins_prompt_bonus')));
      await t.pumpAndSettle();
      expect(svc.calls, ['choose:bonus']);

      resetCarInsuranceStateCache();
      final none = _FakeSvc(_state());
      await t.pumpWidget(l10nApp(
        home: Scaffold(body: Builder(builder: (ctx) => TextButton(onPressed: () => maybeOfferCarInsuranceIncentive(ctx, '998901234567', service: none), child: const Text('go2')))),
      ));
      await t.tap(find.text('go2'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ins_prompt_bonus')), findsNothing);
      expect(none.calls, isEmpty);
    });
  });

  test('ҳамён тарихи: суғурта тўлови ва қайтими ўз номи билан', () {
    String tr(String k, [Map<String, String>? p]) => p == null ? k : '$k(${p.values.join(',')})';
    WalletLedgerEntry e(String type) => WalletLedgerEntry(id: 'x', type: type, amount: type == 'purchase_debit' ? -1000 : 1000, module: 'insurance');
    expect(walletLedgerTitle(e('purchase_debit'), tr), 'wlt_l_purchase_mod(wlt_m_insurance)');
    expect(walletLedgerTitle(e('insurance_cancel_refund'), tr), 'wlt_l_insurance_cancel_refund');
  });

  test('push: эслатма/полис → суғурта экрани; агентга янги ариза — йўқ; бошқа push — йўқ', () {
    expect(PushNavigation.carInsurancePushOpensScreen({'type': 'insurance_remind', 'screen': 'car_insurance'}), isTrue);
    expect(PushNavigation.carInsurancePushOpensScreen({'type': 'insurance_issued'}), isTrue);
    expect(PushNavigation.carInsurancePushOpensScreen({'screen': 'car_insurance'}), isTrue);
    expect(PushNavigation.carInsurancePushOpensScreen({'type': 'insurance_agent_new', 'screen': 'car_insurance'}), isFalse);
    expect(PushNavigation.carInsurancePushOpensScreen({'type': 'wallet', 'screen': 'wallet'}), isFalse);
  });

  group('экран', () {
    testWidgets('мой дастури 1/2 — 50% тайёр, нарх, аризалар; «Суғурталанган» белгиси йўқ', (t) async {
      final d = JsonL10nDelegate();
      const e = InsuranceEnrollment(year: 2026, option: 'oil', plate: '01 A 123 BC', oilChanges: 1, oilGoal: 2, discountPct: 50, discountUsed: false);
      final svc = _FakeSvc(_state(enrollment: e, expiresOn: '2027-11-28'));
      final reqs = Stream.value([
        InsuranceRequest.fromMap('ins_a', {'status': 'issued', 'policyType': 'osago', 'termMonths': 12, 'price': 200000, 'policy': {'number': 'AB 1', 'validFrom': '2026-11-29', 'validTo': '2027-11-28'}}),
        InsuranceRequest.fromMap('ins_b', {'status': 'requested', 'policyType': 'osago', 'termMonths': 6, 'price': 120000}),
      ]);
      await t.pumpWidget(l10nApp(delegate: d, home: CarInsuranceScreen(phone: '998901234567', service: svc, requestsStream: reqs)));
      await t.pumpAndSettle();
      expect(find.text(d.tr('ins_oil_progress_ready').replaceAll('{n}', '1').replaceAll('{goal}', '2').replaceAll('{pct}', '50')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('ins_price')), 200);
      expect(find.byKey(const ValueKey('ins_price')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('ins_req_ins_b')), 200);
      expect(find.byKey(const ValueKey('ins_req_pay_ins_b')), findsOneWidget);
      expect(find.byKey(const ValueKey('ins_req_policy_ins_a')), findsOneWidget);
      expect(find.textContaining('Suğurtalangan'), findsNothing);
      expect(find.byKey(const ValueKey('ins_offer')), findsNothing, reason: 'рағбат танланган — таклиф йўқ');
    });

    testWidgets('рағбат таклифи: бонус/мой танлаш тугмалари; тасдиқлаб — сервер чақирилади', (t) async {
      final d = JsonL10nDelegate();
      const c = InsuranceCampaign(year: 2026, bonusEnabled: true, bonusAmount: 100000, bonusValidityDays: 60, oilEnabled: true, oilSteps: [InsuranceOilStep(1, 50), InsuranceOilStep(2, 100)]);
      final svc = _FakeSvc(_state(campaign: c));
      await t.pumpWidget(l10nApp(delegate: d, home: CarInsuranceScreen(phone: '998901234567', service: svc, requestsStream: Stream.value(const []))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ins_offer_bonus')), findsOneWidget);
      expect(find.byKey(const ValueKey('ins_offer_oil')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ins_offer_oil')));
      await t.pumpAndSettle();
      await t.tap(find.text(d.tr('ins_offer_choose')));
      await t.pumpAndSettle();
      expect(svc.calls, ['choose:oil']);
    });

    testWidgets('мавжуд эмас — тушунарли матн', (t) async {
      await t.pumpWidget(l10nApp(home: CarInsuranceScreen(phone: '998901234567', service: _FakeSvc(InsuranceState.unavailable), requestsStream: Stream.value(const []))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ins_not_available')), findsOneWidget);
    });
  });

  test('ins_* калитлари 3 тилда бир хил, uz_Latn янги алифбода', () {
    Set<String> keys(String l) => (jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>).keys.where((k) => k.startsWith('ins_')).toSet();
    final c = keys('uz_Cyrl');
    expect(c.length, greaterThanOrEqualTo(70));
    expect(keys('uz_Latn'), c);
    expect(keys('ru'), c);
    final latn = jsonDecode(File('assets/lang/uz_Latn.json').readAsStringSync()) as Map<String, dynamic>;
    for (final k in c) {
      expect(RegExp(r"o'|g'|sh|ch", caseSensitive: false).hasMatch('${latn[k]}'.replaceAll("ma'lumot", '')), isFalse, reason: k);
    }
  });
}
