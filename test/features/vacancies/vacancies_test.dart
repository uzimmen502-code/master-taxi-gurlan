import 'dart:async';

import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/home/widgets/home_ads_section.dart';
import 'package:ava_gurlan/features/home/widgets/home_lite_cards.dart';
import 'package:ava_gurlan/features/home/widgets/home_markets_block.dart';
import 'package:ava_gurlan/features/vacancies/domain/job_vacancy.dart';
import 'package:ava_gurlan/features/vacancies/screens/vacancies_screen.dart';
import 'package:ava_gurlan/features/vacancies/screens/vacancy_detail_screen.dart';
import 'package:ava_gurlan/features/vacancies/screens/vacancy_form_screen.dart';
import 'package:ava_gurlan/models/job_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// «Иш ўринлари — Вакансиялар» (эга 2026-11-28). Делегатсиз `context.tr(key)` калитнинг ўзини қайтаради.

const _employer = '998901110001';
const _me = '998901110002';

JobAd _vac({
  String id = 'v1',
  String phone = _employer,
  DateTime? createdAt,
  DateTime? expiresAt,
  Map<String, Object?>? vacancy,
}) {
  final v = JobVacancy.tryParse(vacancy ??
      {
        'position': 'Тикувчи',
        'salaryFrom': 3000000,
        'salaryTo': 5000000,
        'salaryNegotiable': false,
        'schedule': 'full_time',
        'experience': '1',
        'requirements': 'Тикув машинасида ишлай олиш',
        'employerName': 'Гурлан тўқимачилик',
      });
  return JobAd(
    id: id,
    type: 'work',
    text: 'Тикув машинасида ишлай олиш',
    title: v?.position ?? '',
    authorName: 'Эга',
    authorPhone: phone,
    address: 'Гурлан',
    isUrgent: false,
    status: 'active',
    createdAt: createdAt,
    expiresAt: expiresAt,
    vacancy: v,
  );
}

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  group('JobVacancy (sof)', () {
    test('tryParse: lavozimsiz / xarita emas → null; maoş butun', () {
      expect(JobVacancy.tryParse(null), isNull);
      expect(JobVacancy.tryParse({'position': ''}), isNull);
      final v = JobVacancy.tryParse({'position': 'Usta', 'salaryFrom': 2.5, 'salaryTo': 4000000})!;
      expect(v.salaryFrom, isNull, reason: 'kasr maoş qabul qilinmaydi');
      expect(v.salaryTo, 4000000);
    });

    test('salaryLabel: oraliq / dan / gaça / kelişiladi', () {
      String tr(String k) => switch (k) {
            'currency_sum' => 'сўм',
            'vac_salary_from' => '{n} сўмдан',
            'vac_salary_to' => '{n} сўмгача',
            _ => k,
          };
      expect(_vac().vacancy!.salaryLabel(tr), '3 000 000 – 5 000 000 сўм');
      expect(JobVacancy.tryParse({'position': 'x', 'salaryFrom': 1500000})!.salaryLabel(tr), '1 500 000 сўмдан');
      expect(JobVacancy.tryParse({'position': 'x', 'salaryTo': 900000})!.salaryLabel(tr), '900 000 сўмгача');
      expect(JobVacancy.tryParse({'position': 'x', 'salaryNegotiable': true, 'salaryFrom': 1})!.salaryLabel(tr),
          'vac_salary_negotiable');
    });

    test('parseSalary va validate — server bilan bir xil çegaralar', () {
      expect(JobVacancy.parseSalary(''), isNull);
      expect(JobVacancy.parseSalary('3 000 000'), 3000000);
      expect(JobVacancy.parseSalary('0'), -1);
      expect(JobVacancy.parseSalary('1000000001'), -1);
      expect(JobVacancy.parseSalary('abc'), -1);
      String? v({String p = 'Usta', String r = '1234567890', bool neg = false, String f = '1', String t = ''}) =>
          JobVacancy.validate(
              position: p, requirements: r, negotiable: neg, fromRaw: f, toRaw: t, schedule: 'shift', experience: 'none');
      expect(v(), isNull);
      expect(v(p: 'ab'), 'vac_err_position');
      expect(v(r: '123456789'), 'vac_err_requirements', reason: '10 belgidan kam');
      expect(v(f: '', t: ''), 'vac_err_salary');
      expect(v(f: '5', t: '4'), 'vac_err_salary');
      expect(v(neg: true, f: '', t: ''), isNull);
      expect(
          JobVacancy.validate(
              position: 'Usta', requirements: '1234567890', negotiable: true, fromRaw: '', toRaw: '',
              schedule: 'night', experience: 'none'),
          'vac_err_schedule');
    });

    test('payload: kelişiladi — maoş yuborilmaydi; ish beruvçi ikkalasi birga', () {
      final p = JobVacancy.payload(
          position: ' Usta ', requirements: 'r', negotiable: true, salaryFrom: 5, schedule: 'shift', experience: '3',
          employerKind: 'business', employerId: 'b1', districtId: 'gurlan');
      expect(p['position'], 'Usta');
      expect(p.containsKey('salaryFrom'), isFalse);
      expect(p['employerKind'], 'business');
      expect(p['employerId'], 'b1');
      expect(p['districtId'], 'gurlan');
      final q = JobVacancy.payload(
          position: 'Usta', requirements: 'r', negotiable: false, salaryFrom: 5, schedule: 'shift', experience: '3',
          employerKind: 'business');
      expect(q.containsKey('employerKind'), isFalse);
      expect(q['salaryFrom'], 5);
    });

    test('vacancyErrorKey: server kodlari → kalit; noma\'lum → null', () {
      expect(vacancyErrorKey('VACANCY_REQUIREMENTS_INVALID'), 'vac_err_requirements');
      expect(vacancyErrorKey('JOB_AD_DAILY_LIMIT'), isNull);
    });

    test('JobAd.isVacancy: faqat work + vacancy; eski «Iş bor» — yöq', () {
      expect(_vac().isVacancy, isTrue);
      const old = JobAd(
          id: 'o', type: 'work', text: 'x', authorName: '', authorPhone: '', address: '', isUrgent: false, status: 'active');
      expect(old.isVacancy, isFalse);
    });
  });

  group('«Yangi e\'lonlar» tasmasi — 1 kun', () {
    final now = DateTime(2026, 11, 28, 12);
    test('≤ 24 soat va muddati ötmagan; eng yangisi birinçi; limit', () {
      final list = newVacanciesForStrip([
        _vac(id: 'old', createdAt: now.subtract(const Duration(hours: 25))),
        _vac(id: 'a', createdAt: now.subtract(const Duration(hours: 2))),
        _vac(id: 'b', createdAt: now.subtract(const Duration(minutes: 5))),
        _vac(id: 'edge', createdAt: now.subtract(const Duration(hours: 24))),
        _vac(id: 'exp', createdAt: now, expiresAt: DateTime(2000)),
      ], now, limit: 2);
      expect(list.map((a) => a.id), ['b', 'a']);
      expect(JobVacancy.isNew(now.subtract(const Duration(hours: 24)), now), isTrue, reason: 'çegara içida');
      expect(JobVacancy.isNew(null, now), isFalse);
    });
  });

  group('Bosh sahifa darvozalari', () {
    test('zavodlar — business_map («Bozorlar» ičida, ega 2026-11-28), vakansiyalar — jobs', () {
      final f = kHomeMarketEntries.firstWhere((e) => e.id == 'factories');
      expect(f.moduleId, 'business_map');
      expect(f.imagePath, kHomeFactoriesCardImage);
      expect(homeVacanciesCardVisible((id) => id == 'jobs'), isTrue);
      expect(homeVacanciesCardVisible((_) => false), isFalse);
    });

    testWidgets('HomeAdsSection: yangi vakansiya «Vakansiya» belgisi bilan, bosilsa onOpenVacancy', (t) async {
      final opened = <String>[];
      await t.pumpWidget(_app(Scaffold(
        body: SingleChildScrollView(
          child: HomeAdsSection(
            adType: 'ad',
            titleKey: 'home_section_ads',
            onOpenAll: () {},
            onOpenAd: (_) {},
            onOpenVacancy: (a) => opened.add(a.id),
            watchJobs: () => Stream.value(const <JobAd>[]),
            watchVacancies: () => Stream.value([_vac(id: 'nv', createdAt: DateTime.now())]),
          ),
        ),
      )));
      await t.pumpAndSettle();
      final row = find.byKey(const ValueKey('home_ads_vacancy_nv'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('home_badge_vacancy')), findsOneWidget);
      await t.tap(row);
      expect(opened, ['nv']);
    });
  });

  group('Ekranlar', () {
    testWidgets('VacanciesScreen: faqat oqimdagi vakansiyalar, belgilangan birinçi', (t) async {
      await t.pumpWidget(_app(VacanciesScreen(
        highlightAdId: 'v2',
        watch: (_) => Stream.value([_vac(id: 'v1'), _vac(id: 'v2')]),
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('vac_card_v1')), findsOneWidget);
      final y1 = t.getTopLeft(find.byKey(const ValueKey('vac_card_v1'))).dy;
      final y2 = t.getTopLeft(find.byKey(const ValueKey('vac_card_v2'))).dy;
      expect(y2 < y1, isTrue);
      expect(find.text('vac_schedule_full_time · Гурлан'), findsNWidgets(2));
    });

    testWidgets('VacanciesScreen: böş — vac_empty', (t) async {
      await t.pumpWidget(_app(VacanciesScreen(watch: (_) => Stream.value(const []))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('vac_empty')), findsOneWidget);
    });

    testWidgets('VacancyDetailScreen: «Talablar» körinadi, «Ariza beriş» → onApply; telefon yöq', (t) async {
      final applied = <String>[];
      await t.pumpWidget(_app(VacancyDetailScreen(
        ad: _vac(),
        myUid: _me,
        onApply: (_, ad) async => applied.add(ad.id),
      )));
      expect(find.text('Тикув машинасида ишлай олиш'), findsOneWidget);
      expect(find.byKey(const ValueKey('vac_detail_employer')), findsOneWidget);
      expect(find.textContaining(_employer), findsNothing);
      await t.tap(find.byKey(const ValueKey('vac_apply')));
      await t.pump();
      expect(applied, ['v1']);
    });

    testWidgets('VacancyDetailScreen: öz vakansiyasida «Ariza beriş» yöq', (t) async {
      await t.pumpWidget(_app(VacancyDetailScreen(ad: _vac(), myUid: _employer)));
      expect(find.byKey(const ValueKey('vac_apply')), findsNothing);
    });

    testWidgets('VacancyFormScreen: talablarsiz — xato, töğri forma — payload serverga', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      Map<String, Object?>? sent;
      final biz = Business(
          id: 'f1', ownerId: _employer, name: 'Завод', category: BusinessCategory.manufacturing, phone: _employer,
          lat: 41, lng: 60, districtId: 'gurlan', regionId: 'xorazm');
      await t.pumpWidget(_app(VacancyFormScreen(
        employerBusinessId: 'f1',
        loadMyBusinesses: () async => [biz],
        submit: (v, text, rid) async {
          sent = v;
          return 'pending';
        },
      )));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('vac_f_position')), 'Тикувчи');
      await t.enterText(find.byKey(const ValueKey('vac_f_from')), '3 000 000');
      await t.tap(find.byKey(const ValueKey('vac_f_submit')));
      await t.pump();
      expect(find.text('vac_err_requirements'), findsOneWidget);
      expect(sent, isNull);
      await t.enterText(find.byKey(const ValueKey('vac_f_requirements')), 'Тажриба 1 йил, масъулиятли');
      await t.tap(find.byKey(const ValueKey('vac_f_submit')));
      await t.pumpAndSettle();
      expect(sent, isNotNull);
      expect(sent!['salaryFrom'], 3000000);
      expect(sent!['employerKind'], 'business');
      expect(sent!['employerId'], 'f1');
      expect(sent!['districtId'], 'gurlan');
      expect(sent!['requirements'], 'Тажриба 1 йил, масъулиятли');
    });
  });
}
