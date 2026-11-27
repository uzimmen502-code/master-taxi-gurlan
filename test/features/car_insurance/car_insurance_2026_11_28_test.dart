// «Автомобил суғуртаси» (эга 2026-11-28): соф ёрдамчилар, бош саҳифа бўлими (сервер босқичи), экран
// (мой дастури жараёни, нарх, аризалар, «Суғурталанган» белгиси ЙЎҚ), 3 тил калитлари.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

class _ZoneSvc extends CarInsuranceService {
  _ZoneSvc(this.state, {this.settings = const {}});
  final InsuranceState state;
  final Map settings;
  final created = <(String, String, int, String, String)>[];
  List<Map<String, dynamic>> published = [];

  @override
  Future<InsuranceState> myState() async => state;

  @override
  Future<({String requestId, int price})> createRequest({
    required String policyType,
    required String vehicleType,
    required int termMonths,
    required String idempotencyKey,
    String zone = '',
    String driverScope = '',
  }) async {
    created.add((policyType, vehicleType, termMonths, zone, driverScope));
    return (requestId: 'ins_test_000001', price: 0);
  }

  final uploads = <(String, String, int)>[];
  @override
  Future<void> uploadTechPassport(String requestId, String side, String fileBase64) async =>
      uploads.add((requestId, side, fileBase64.length));

  @override
  Future<InsuranceQuote> quote(String requestId) async => throw StateError('stop'); // тўлов оқими бу тестда керак эмас

  final corrected = <Map<String, String>>[];
  List<InsuranceRequest> agentRequests = const [];
  @override
  Future<List<InsuranceRequest>> agentList(String status) async => agentRequests;
  @override
  Future<int> agentCorrect({required String requestId, required String zone, required String vehicleType, required String driverScope, required String reason}) async {
    corrected.add({'id': requestId, 'zone': zone, 'vehicle': vehicleType, 'scope': driverScope, 'reason': reason});
    return 1;
  }

  @override
  Future<Map> adminSettings() async => settings;

  @override
  Future<int> adminPublishTariff(List<Map<String, dynamic>> rows, String note) async {
    published = rows;
    return 1;
  }
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

  // Эга расмий ОСАГО жадвали (2026-11-28): ҳудуд × тоифа × [чекланган, чекланмаган].
  group('ОСАГО жадвали (schema 2)', () {
    const owner = {
      'tashkent': {'car': [192000, 384000], 'truck': [336000, 672000], 'bus': [384000, 768000], 'moto': [72000, 144000]},
      'other': {'car': [160000, 320000], 'truck': [280000, 560000], 'bus': [320000, 640000], 'moto': [60000, 120000]},
      'cis': {'car': [320000, 640000], 'truck': [560000, 1120000]},
    };
    List<Map<String, dynamic>> ownerRows() => [
          for (final z in owner.entries)
            for (final v in z.value.entries)
              for (var i = 0; i < 2; i++)
                {'policyType': 'osago', 'zone': z.key, 'vehicleType': v.key, 'driverScope': kInsuranceDriverScopes[i], 'termMonths': 12, 'price': v.value[i]},
        ];

    test('админ катаклари: қаторлар ↔ катак (20 та, МДҲ фақат енгил/юк), КАСКО сақланади, бўш катак 0', () {
      final g = insuranceGridFromRows([...ownerRows(), {'policyType': 'kasko', 'zone': 'other', 'vehicleType': 'car', 'driverScope': 'limited', 'termMonths': 12, 'price': 900000}]);
      expect(g.prices.length, 20);
      expect(g.others.single['policyType'], 'kasko');
      final rows = insuranceGridToRows(g.prices, others: g.others);
      expect(rows.length, 21);
      for (final r in ownerRows()) {
        expect(rows.any((x) => x['zone'] == r['zone'] && x['vehicleType'] == r['vehicleType'] && x['driverScope'] == r['driverScope'] && x['price'] == r['price']), isTrue, reason: '$r');
      }
      expect(insuranceGridVehicles('cis'), ['car', 'truck']);
      expect(insuranceGridVehicles('other'), kInsuranceVehicleTypes);
      expect(insuranceGridToRows(const {}).every((r) => r['price'] == 0), isTrue);
      expect(insuranceGridToRows(const {}).length, 20);
    });

    test('нархни олдиндан кўриш: ҳар комбинация; МДҲ микроавтобус — йўқ', () {
      final opts = [for (final r in ownerRows()) InsuranceOption.fromMap(r)];
      for (final r in ownerRows()) {
        expect(
          insuranceZoneOption(opts, policyType: 'osago', zone: r['zone'] as String, vehicleType: r['vehicleType'] as String, driverScope: r['driverScope'] as String, termMonths: 12)?.price,
          r['price'],
        );
      }
      expect(insuranceZoneOption(opts, policyType: 'osago', zone: 'cis', vehicleType: 'bus', driverScope: 'limited', termMonths: 12), isNull);
      expect(insuranceVehiclesFor(opts, 'osago', 'cis'), ['car', 'truck']);
    });

    testWidgets('ариза формаси: ҳудуд профилдан, ҳайдовчи/тоифа/МДҲ — нарх; юборилганда zone + driverScope', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final d = JsonL10nDelegate();
      final svc = _ZoneSvc(InsuranceState.fromMap({
        'available': true, 'tariffVersion': 4, 'tariffSchema': 2, 'derivedZone': 'tashkent', 'options': ownerRows(),
        'car': {'brand': 'Chevrolet', 'model': 'Cobalt', 'year': 2020, 'plate': '01 A 123 BC', 'complete': true},
      }));
      final picked = <String>[];
      await t.pumpWidget(l10nApp(
        delegate: d,
        home: CarInsuranceScreen(
          phone: '998901234567',
          service: svc,
          requestsStream: Stream.value(const []),
          pickImage: (side) async {
            picked.add(side);
            return Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2, 3]);
          },
        ),
      ));
      await t.pumpAndSettle();
      String price(int p) => d.tr('ins_price').replaceAll('{price}', formatMoney(p));
      Future<void> tap(String key) async {
        await t.ensureVisible(find.byKey(ValueKey(key)));
        await t.pumpAndSettle();
        await t.tap(find.byKey(ValueKey(key)));
        await t.pumpAndSettle();
      }

      await t.scrollUntilVisible(find.byKey(const ValueKey('ins_price')), 200);
      expect(find.text(price(192000)), findsOneWidget, reason: 'Тошкент · енгил · чекланган');
      await tap('ins_scope_unlimited');
      expect(find.text(price(384000)), findsOneWidget);
      await tap('ins_vehicle_truck');
      expect(find.text(price(672000)), findsOneWidget);
      await tap('ins_zone_other');
      expect(find.text(price(560000)), findsOneWidget);
      await tap('ins_cis');
      expect(find.byKey(const ValueKey('ins_vehicle_bus')), findsNothing);
      expect(find.byKey(const ValueKey('ins_vehicle_moto')), findsNothing);
      expect(find.byKey(const ValueKey('ins_zone_other')), findsNothing);
      expect(find.text(price(1120000)), findsOneWidget);
      // Эга 2026-11-28: техпаспорт икки томони танланмагунча юбориш ўчиқ.
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('ins_request_submit'))).onPressed, isNull);
      await tap('ins_tech_front');
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('ins_request_submit'))).onPressed, isNull);
      await tap('ins_tech_back');
      await tap('ins_request_submit');
      expect(svc.created, [('osago', 'truck', 12, 'cis', 'unlimited')]);
      expect(picked, ['front', 'back']);
      expect(svc.uploads.map((u) => (u.$1, u.$2)), [('ins_test_000001', 'front'), ('ins_test_000001', 'back')]);
    });

    testWidgets('админ: эга жадвали қоралама (сервер draftRows) — катаклар тўла, «Эълон қилиш» → 20 қатор', (t) async {
      final svc = _ZoneSvc(InsuranceState.unavailable, settings: {
        'config': {'activeTariffVersion': 0}, 'tariff': null, 'tariffVersions': const [], 'draftRows': ownerRows(),
      });
      await t.binding.setSurfaceSize(const Size(1000, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(home: CarInsuranceAdminScreen(service: svc)));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Нарх жадвали'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ins_tariff_draft')), findsOneWidget);
      expect(find.byKey(const ValueKey('ins_tariff_zone_cis')), findsOneWidget);
      expect(find.byKey(const ValueKey('ins_tariff_cis_bus_limited_1')), findsNothing);
      final f = t.widget<TextFormField>(find.byKey(const ValueKey('ins_tariff_cis_truck_unlimited_1')));
      expect(f.initialValue, '1120000');
      await t.ensureVisible(find.byKey(const ValueKey('ins_tariff_publish')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('ins_tariff_publish')));
      await t.pumpAndSettle();
      expect(svc.published.length, 20);
      for (final r in ownerRows()) {
        expect(svc.published.any((x) => x['zone'] == r['zone'] && x['vehicleType'] == r['vehicleType'] && x['driverScope'] == r['driverScope'] && x['price'] == r['price']), isTrue, reason: '$r');
      }
    });
  });

  testWidgets('агент (эга 2026-11-28): техпаспорт белгиси, «Маълумотни тузатиш» — ҳудуд/тоифа/ҳайдовчи + сабаб серверга', (t) async {
    final svc = _ZoneSvc(InsuranceState.unavailable)
      ..agentRequests = [
        InsuranceRequest.fromMap('ins_a1', {
          'requestId': 'ins_a1', 'status': 'paid', 'policyType': 'osago', 'vehicleType': 'car', 'termMonths': 12, 'price': 192000,
          'zone': 'tashkent', 'zoneDerived': 'other', 'zoneSource': 'user', 'driverScope': 'limited',
          'techPassport': {'front': true, 'back': true},
        }),
      ];
    await t.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: InsuranceRequestsAdminTab(service: svc))));
    await t.pumpAndSettle();
    expect(find.textContaining('олд ✓ · орқа ✓'), findsOneWidget);
    expect(find.textContaining('текширинг'), findsOneWidget);
    expect(find.byKey(const ValueKey('ins_admin_tech_open_ins_a1')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ins_admin_correct_ins_a1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('ins_corr_zone')));
    await t.pumpAndSettle();
    await t.tap(find.text('Ўзбекистоннинг бошқа ҳудудлари').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('ins_corr_reason')), 'техпаспорт: Хоразм');
    await t.tap(find.byKey(const ValueKey('ins_corr_ok')));
    await t.pumpAndSettle();
    expect(svc.corrected, [
      {'id': 'ins_a1', 'zone': 'other', 'vehicle': 'car', 'scope': 'limited', 'reason': 'техпаспорт: Хоразм'},
    ]);
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
