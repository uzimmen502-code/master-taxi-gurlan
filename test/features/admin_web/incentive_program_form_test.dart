// «Дастурни таҳрирлаш» соддалаштириш (эга 2026-11-28): ном → лотин → калит, туркумлар рўйхатдан ва йиғинди,
// ёш бўш = чекловсиз, «Фақат янги фойдаланувчилар», синовчилар/туманлар босқичга қараб, кунлик бюджет,
// Тошкент куни бўйича саналар, эски prod ҳужжатлари (car_200k, women_100k) айнан қайта сақланади.

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/core/utils/uz_script.dart';
import 'package:ava_gurlan/features/admin_web/screens/incentive_programs_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_incentives_service.dart';
import 'package:ava_gurlan/features/admin_web/services/incentive_categories.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp _ts(int ms) => Timestamp.fromMillisecondsSinceEpoch(ms);

/// prod car_200k кўринишидаги ҳужжат (setup_incentive_programs.js: newUsersSince = 2026-11-03 01:04 Тошкент).
final _carSinceMs = DateTime.utc(2026, 11, 2, 20, 4).millisecondsSinceEpoch;
Map<String, dynamic> _car200k() => {
      'key': 'car_200k',
      'title': {'uz_Cyrl': 'Машина бонуси', 'uz_Latn': 'Mashina bonusi', 'ru': 'Бонус за авто'},
      'stage': 'internal',
      'internalPhones': ['998901238777'],
      'pilotDistrictIds': <String>[],
      'audience': {'gender': 'any', 'ageMin': 0, 'ageMax': 120, 'requireCar': true, 'newUsersSince': _ts(_carSinceMs)},
      'amount': 200000,
      'buckets': [
        {'category': 'tire', 'amount': 100000},
        {'category': 'oil', 'amount': 50000},
        {'category': 'battery', 'amount': 50000},
      ],
      'maxOrderSharePct': 50,
      'validityDays': 60,
      'budgetTotal': 20000000,
      'budgetDaily': 2000000,
      'startAt': null,
      'endAt': null,
      'counters': {'grantedAmount': 0},
    };

Map<String, dynamic> _women100k({int? sinceMs}) => {
      'key': 'women_100k',
      'title': {'uz_Cyrl': 'Аёллар бонуси', 'uz_Latn': 'Ayollar bonusi', 'ru': 'Бонус для женщин'},
      'stage': 'internal',
      'internalPhones': ['998901238777'],
      'pilotDistrictIds': <String>[],
      'audience': {'gender': 'female', 'ageMin': 15, 'ageMax': 60, 'requireCar': false, 'newUsersSince': _ts(sinceMs ?? _carSinceMs)},
      'amount': 100000,
      'buckets': <Map<String, dynamic>>[],
      'maxOrderSharePct': 50,
      'validityDays': 30,
      'budgetTotal': 10000000,
      'budgetDaily': 1000000,
    };

void main() {
  group('соф', () {
    test('лотин номдан калит: янги ҳарфлар, апостроф, бўшлиқ, узунлик', () {
      expect(incentiveKeyFromLatin('Ayollar bonusi'), 'ayollar_bonusi');
      expect(incentiveKeyFromLatin("Maşina o'g'il çiroq Ğ"), 'mashina_ogil_chiroq_g');
      expect(incentiveKeyFromLatin('  -- 200 000 so\'m!! '), '200_000_som');
      expect(incentiveKeyFromLatin('A'), '', reason: '2 белгидан кам — бўш');
      expect(incentiveKeyFromLatin(''), '');
      final long = incentiveKeyFromLatin('a' * 39 + ' bcd');
      expect(long.length, lessThanOrEqualTo(40));
      expect(RegExp(r'^[a-z0-9_]{2,40}$').hasMatch(long), isTrue);
      expect(long.endsWith('_'), isFalse);
      // Кирилл → лотин (мавжуд UzScript, янги алифбо) → калит.
      expect(UzScript.toLatin('Аёллар бонуси'), 'Ayollar bonusi');
      expect(incentiveKeyFromLatin(UzScript.toLatin('Шина ва мой учун')), 'shina_va_moy_uchun');
    });

    test('калит хатоси: формат, махсус, банд; тўғри — null', () {
      expect(incentiveKeyError('ok_key', {'other'}), isNull);
      expect(incentiveKeyError('Bad Key', {}), contains('2–40'));
      expect(incentiveKeyError('a', {}), contains('2–40'));
      expect(incentiveKeyError('car_insurance_bonus', {}), contains('махсус'));
      expect(incentiveKeyError('car_200k', {'car_200k'}), contains('банд'));
    });

    test('кунлик бюджет: 0 ёки миқдор ≤ кунлик ≤ умумий (чегаралар)', () {
      String? e(int d) => incentiveBudgetDailyError(amount: 100000, total: 1000000, daily: d);
      expect(e(0), isNull);
      expect(e(100000), isNull, reason: '= миқдор');
      expect(e(1000000), isNull, reason: '= умумий');
      expect(e(99999), contains('камида'));
      expect(e(1), contains('камида'));
      expect(e(1000001), contains('ошмасин'));
      expect(e(-5), isNotNull);
    });

    test('Тошкент куни: бошланиш 00:00, тугаш — кейинги кун 00:00 (кун тўлиқ киради); эски ярим тун ҳам тўғри ўқилади', () {
      final day = DateTime(2026, 12, 31);
      expect(tashkentDayStartMs(day), DateTime.utc(2026, 12, 30, 19).millisecondsSinceEpoch);
      final end = tashkentDayEndExclusiveMs(day);
      expect(end, DateTime.utc(2026, 12, 31, 19).millisecondsSinceEpoch);
      expect(incentiveEndInclusiveDay(end), DateTime(2026, 12, 31));
      // Эски форма (Тошкентдаги браузер ярим туни 31.12) — дастур 31.12 бошида тугарди → охирги кун 30.12.
      expect(incentiveEndInclusiveDay(DateTime.utc(2026, 12, 30, 19).millisecondsSinceEpoch), DateTime(2026, 12, 30));
      expect(tashkentDateOf(_carSinceMs), DateTime(2026, 11, 3));
    });

    test('«ҳамма»: 2020-01-01 ва ундан олдин', () {
      expect(incentiveSinceMeansAll(kIncentiveAllUsersSinceMs), isTrue);
      expect(incentiveSinceMeansAll(0), isTrue);
      expect(incentiveSinceMeansAll(kIncentiveAllUsersSinceMs + 1), isFalse);
      expect(incentiveSinceMeansAll(_carSinceMs), isFalse);
    });

    test('қулф: car_insurance_bonus ва ҳар қандай kind; оддий дастур — йўқ', () {
      expect(incentiveProgramLocked('car_insurance_bonus', const {}), isTrue);
      expect(incentiveProgramLocked('x', const {'kind': 'car_insurance_bonus'}), isTrue);
      expect(incentiveProgramLocked('new_special', const {'kind': 'whatever'}), isTrue);
      expect(incentiveProgramLocked('spouse_link', const {}), isTrue);
      expect(incentiveProgramLocked('relatives_birthdays', const {}), isTrue);
      expect(incentiveProgramLocked('car_200k', _car200k()), isFalse);
      expect(incentiveProgramLocked('women_100k', const {'kind': ''}), isFalse);
      expect(incentiveLockedWhere('car_insurance_bonus', const {}), contains('Автомобил суғуртаси'));
      expect(incentiveLockedWhere('spouse_link', const {'kind': 'spouse_link'}), contains('Байрам саватчаси'));
    });

    test('«Кимга»: ёш чекловсиз бўлса кўрсатилмайди (0–120 / 0–0 йўқ), «ҳамма» санаси', () {
      expect(incentiveAudienceText(const {'gender': 'any'}), 'ҳамма');
      expect(incentiveAudienceText({'gender': 'any', 'ageMin': 0, 'ageMax': 120}), 'ҳамма');
      final w = incentiveAudienceText(Map<String, dynamic>.from(_women100k()['audience'] as Map));
      expect(w, contains('аёллар · 15–60 ёш'));
      expect(w, contains('янгилар: 03.11.2026 дан'));
      expect(incentiveAudienceText({'gender': 'male', 'ageMin': 18}), 'эркаклар · 18 ёшдан');
      expect(incentiveAudienceText({'gender': 'any', 'ageMax': 60}), 'ҳамма · 60 ёшгача');
      final all = incentiveAudienceText({'gender': 'any', 'requireCar': true, 'newUsersSince': _ts(kIncentiveAllUsersSinceMs)});
      expect(all, 'ҳамма · машина профили шарт · эски ва янги фойдаланувчилар');
    });

    test('туркумлар — ягона манба; сервер хато кодлари', () {
      expect(kIncentiveProgramCategories.keys.first, kIncentiveCategoryAny);
      expect(kIncentiveProgramCategories.keys, containsAll(kIncentiveCategories.keys));
      expect(incentiveCategoryLabel('tire'), 'Шина');
      expect(incentiveCategoryLabel('legacy_x'), 'legacy_x');
      FirebaseFunctionsException err(String c) => FirebaseFunctionsException(code: 'x', message: c, details: {'code': c});
      expect(incentiveAdminError(err('PROGRAM_SPECIAL')), contains('махсус'));
      expect(incentiveAdminError(err('PROGRAM_KEY_TAKEN')), contains('банд'));
      expect(incentiveAdminError(err('VALIDATION_budgetDaily')), contains('Кунлик бюджет'));
    });
  });

  group('форма', () {
    late List<(Map<String, dynamic>, String?)> saved;

    Future<void> open(WidgetTester tester,
        {String? id, Map<String, dynamic>? initial, Set<String> existing = const {}, Future<GeoArea?> Function(BuildContext)? pick}) async {
      saved = [];
      tester.view.physicalSize = const Size(1000 * 2, 2400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: c,
                  builder: (_) => IncentiveProgramFormDialog(
                    programId: id,
                    initial: initial,
                    existingIds: existing,
                    onSave: (p, pid) async => saved.add((p, pid)),
                    pickDistrict: pick,
                  ),
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

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('incentive_save')));
      await tester.tap(find.byKey(const ValueKey('incentive_save')));
      await tester.pumpAndSettle();
    }

    String errorText(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('incentive_form_error'))).data!;

    Future<void> chooseStage(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const ValueKey('incentive_form_stage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('янги: кирилл → лотин → калит; кишилар × миқдор = бюджет; кунлик хато; «ҳамма» → 2020-01-01; ёш бўш → 0/120', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('incentive_name_cyrl')), 'Аёллар бонуси');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('incentive_name_latn'))).controller!.text, 'Ayollar bonusi');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('incentive_key'))).controller!.text, 'ayollar_bonusi');
      await tester.enterText(find.byKey(const ValueKey('incentive_name_ru')), 'Бонус для женщин');
      await tester.enterText(find.byKey(const ValueKey('incentive_amount')), '100000');
      await tester.enterText(find.byKey(const ValueKey('incentive_people')), '50');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('incentive_budget'))).controller!.text, '5000000');
      await tester.enterText(find.byKey(const ValueKey('incentive_daily')), '50000');
      await tester.pump();
      expect(find.textContaining('камида битта кишининг'), findsWidgets, reason: 'жонли хато');
      await save(tester);
      expect(saved, isEmpty, reason: 'кунлик < миқдор — юборилмайди');
      await tester.enterText(find.byKey(const ValueKey('incentive_daily')), '0');
      await tester.tap(find.byKey(const ValueKey('incentive_only_new')));
      await tester.pump();
      expect(find.byKey(const ValueKey('incentive_since')), findsNothing, reason: 'ўчиқ — сана йўқ');
      await save(tester);
      expect(saved, hasLength(1));
      final (p, pid) = saved.single;
      expect(pid, isNull);
      expect(p['key'], 'ayollar_bonusi');
      expect(p['title'], {'uz_Cyrl': 'Аёллар бонуси', 'uz_Latn': 'Ayollar bonusi', 'ru': 'Бонус для женщин'});
      expect(p['audience'], {'gender': 'any', 'ageMin': 0, 'ageMax': 120, 'requireCar': false, 'newUsersSince': kIncentiveAllUsersSinceMs});
      expect([p['amount'], p['budgetTotal'], p['budgetDaily'], p['buckets'], p['stage']], [100000, 5000000, 0, [], 'off']);
      expect([p['startAt'], p['endAt']], [null, null]);
    });

    testWidgets('янги: банд калит ва махсус калит — сақланмайди; калитни қўлда ўзгартириш мумкин', (tester) async {
      await open(tester, existing: {'ayollar_bonusi'});
      await tester.enterText(find.byKey(const ValueKey('incentive_name_cyrl')), 'Аёллар бонуси');
      await tester.enterText(find.byKey(const ValueKey('incentive_name_ru')), 'Бонус');
      await tester.enterText(find.byKey(const ValueKey('incentive_amount')), '100000');
      await tester.enterText(find.byKey(const ValueKey('incentive_budget')), '1000000');
      await tester.pump();
      expect(find.textContaining('калит банд'), findsWidgets);
      await save(tester);
      expect(saved, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('incentive_key')), 'car_insurance_bonus');
      await save(tester);
      expect(saved, isEmpty);
      expect(errorText(tester), contains('махсус'));
      await tester.enterText(find.byKey(const ValueKey('incentive_key')), 'ayollar_2');
      // Номни ўзгартирса — қўлда ёзилган калит сақланади.
      await tester.enterText(find.byKey(const ValueKey('incentive_name_cyrl')), 'Аёллар');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('incentive_key'))).controller!.text, 'ayollar_2');
      await save(tester);
      expect(saved.single.$1['key'], 'ayollar_2');
      expect(saved.single.$1['title']['uz_Latn'], 'Ayollar');
    });

    testWidgets('car_200k: калит фақат ўқиш; йиғинди; ёш йўқ; синовчи чипи; тегмасдан сақлаш — айнан (newUsersSince ms, туркумлар)', (tester) async {
      await open(tester, id: 'car_200k', initial: _car200k());
      expect(find.byKey(const ValueKey('incentive_key')), findsNothing);
      expect(find.text('Калит: car_200k'), findsOneWidget);
      expect(find.byKey(const ValueKey('incentive_amount')), findsNothing, reason: 'туркум бор — қўлда эмас');
      expect(tester.widget<Text>(find.byKey(const ValueKey('incentive_amount_sum'))).data, contains('200'));
      expect(tester.widget<TextField>(find.byKey(const ValueKey('incentive_age_min'))).controller!.text, '');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('incentive_age_max'))).controller!.text, '');
      expect(find.byKey(const ValueKey('incentive_phone_998901238777')), findsOneWidget);
      expect(find.byKey(const ValueKey('incentive_add_district')), findsNothing, reason: 'internal — туман йўқ');
      expect(find.textContaining('Шу санадан: 03.11.2026'), findsOneWidget);
      expect(find.textContaining('Туркумлар йиғиндиси:'), findsNothing, reason: 'такрорий кўрсаткич олиб ташланди');
      await save(tester);
      expect(saved, hasLength(1));
      final (p, pid) = saved.single;
      expect(pid, 'car_200k');
      expect(p['key'], 'car_200k');
      expect(p['amount'], 200000);
      expect(p['buckets'], [
        {'category': 'tire', 'amount': 100000},
        {'category': 'oil', 'amount': 50000},
        {'category': 'battery', 'amount': 50000},
      ]);
      expect(p['audience'], {'gender': 'any', 'ageMin': 0, 'ageMax': 120, 'requireCar': true, 'newUsersSince': _carSinceMs});
      expect([p['internalPhones'], p['pilotDistrictIds'], p['stage']], [['998901238777'], [], 'internal']);
      expect([p['maxOrderSharePct'], p['validityDays'], p['budgetTotal'], p['budgetDaily']], [50, 60, 20000000, 2000000]);
    });

    testWidgets('туркум миқдори ўзгарса — «Ҳар бир кишига» йиғиндига эргашади; охирги туркум ўчса — қўлда майдон (йиғинди билан)', (tester) async {
      await open(tester, id: 'car_200k', initial: _car200k());
      await tester.enterText(find.byKey(const ValueKey('incentive_bucket_amount_0')), '120000');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('incentive_amount_sum'))).data, contains('220'));
      await save(tester);
      expect(saved.single.$1['amount'], 220000);
      expect((saved.single.$1['buckets'] as List).first, {'category': 'tire', 'amount': 120000});

      await open(tester, id: 'car_200k', initial: _car200k());
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('incentive_bucket_remove_0')));
        await tester.pump();
      }
      expect(tester.widget<TextField>(find.byKey(const ValueKey('incentive_amount'))).controller!.text, '50000');
    });

    testWidgets('pilot: туман/синовчисиз — рад; нотўғри рақам чипга қўшилмайди; туман танланса — сақланади', (tester) async {
      await open(tester,
          initial: null,
          pick: (_) async => const GeoArea(regionId: 'xorazm', districtId: 'gurlan', districtLabel: 'Гурлан'));
      await tester.enterText(find.byKey(const ValueKey('incentive_name_cyrl')), 'Пилот');
      await tester.enterText(find.byKey(const ValueKey('incentive_name_ru')), 'Пилот');
      await tester.enterText(find.byKey(const ValueKey('incentive_amount')), '10000');
      await tester.enterText(find.byKey(const ValueKey('incentive_budget')), '100000');
      expect(find.byKey(const ValueKey('incentive_phone_input')), findsNothing, reason: 'off — синовчилар яширин');
      await chooseStage(tester, 'Битта ҳудуд (пилот)');
      expect(find.byKey(const ValueKey('incentive_add_district')), findsOneWidget);
      await save(tester);
      expect(saved, isEmpty);
      expect(errorText(tester), contains('туман ёки синовчи'));
      await tester.enterText(find.byKey(const ValueKey('incentive_phone_input')), '12345');
      await tester.tap(find.byKey(const ValueKey('incentive_phone_add')));
      await tester.pump();
      expect(find.textContaining('Нотўғри рақам: 12345'), findsOneWidget);
      expect(find.byKey(const ValueKey('incentive_phone_12345')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('incentive_phone_input')), '');
      await tester.tap(find.byKey(const ValueKey('incentive_add_district')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('incentive_district_gurlan')), findsOneWidget);
      await save(tester);
      expect(saved.single.$1['pilotDistrictIds'], ['gurlan']);
      expect(saved.single.$1['stage'], 'pilot');
      expect(saved.single.$1['key'], 'pilot');
    });

    testWidgets('internal: синовчи 9 рақам → 998…; сақланмаган рақам ҳам сақлашда қўшилади', (tester) async {
      await open(tester, id: 'women_100k', initial: {..._women100k(), 'internalPhones': <String>[]});
      await save(tester);
      expect(saved, isEmpty);
      expect(errorText(tester), contains('синовчи'));
      await tester.enterText(find.byKey(const ValueKey('incentive_phone_input')), '901112233, 998905556677');
      await save(tester);
      expect(saved.single.$1['internalPhones'], ['998901112233', '998905556677']);
      expect(saved.single.$1['audience']['ageMin'], 15);
      expect(saved.single.$1['audience']['ageMax'], 60);
    });

    testWidgets('women_100k: «Фақат янги» ёқиқ; ўчирилса — 2020-01-01; 2020 санали ҳужжат — ўчиқ кўринади', (tester) async {
      await open(tester, id: 'women_100k', initial: _women100k());
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('incentive_only_new'))).value, isTrue);
      await tester.tap(find.byKey(const ValueKey('incentive_only_new')));
      await tester.pump();
      await save(tester);
      expect(saved.single.$1['audience']['newUsersSince'], kIncentiveAllUsersSinceMs);

      await open(tester, id: 'women_100k', initial: _women100k(sinceMs: kIncentiveAllUsersSinceMs));
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('incentive_only_new'))).value, isFalse);
      expect(find.text('Эски ва янги — ҳамма'), findsOneWidget);
      await save(tester);
      expect(saved.single.$1['audience']['newUsersSince'], kIncentiveAllUsersSinceMs);
    });

    testWidgets('тугаш санаси: тегилмаса — эски вақт айнан; ёрлиқ «шу кун ҳам киради»', (tester) async {
      final legacyEnd = DateTime.utc(2026, 12, 30, 19).millisecondsSinceEpoch; // эски: 31.12 ярим туни (Тошкент браузер)
      final start = DateTime.utc(2026, 11, 30, 19).millisecondsSinceEpoch;
      await open(tester, id: 'women_100k', initial: {..._women100k(), 'startAt': _ts(start), 'endAt': _ts(legacyEnd)});
      expect(find.textContaining('Охирги кун: 30.12.2026 (шу кун ҳам киради)'), findsOneWidget);
      expect(find.textContaining('Бошланиш: 01.12.2026'), findsOneWidget);
      await save(tester);
      expect([saved.single.$1['startAt'], saved.single.$1['endAt']], [start, legacyEnd]);
    });
  });
}
