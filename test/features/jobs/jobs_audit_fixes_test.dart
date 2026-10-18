import 'dart:async';

import 'package:ava_gurlan/core/geo/geo_names.dart';
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/features/jobs/controllers/jobs_controller.dart';
import 'package:ava_gurlan/features/jobs/jobs_sections.dart';
import 'package:ava_gurlan/features/jobs/screens/jobs_my_ads_screen.dart';
import 'package:ava_gurlan/features/jobs/widgets/ad_card.dart';
import 'package:ava_gurlan/features/jobs/widgets/complaint_sheet.dart';
import 'package:ava_gurlan/models/geo_area.dart';
import 'package:ava_gurlan/models/job_ad.dart';
import 'package:ava_gurlan/repositories/jobs_repository.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// «Иш топ» аудити (2026-10-18): A2 A3 A4 B4 B5 B6 B7 B8.
//
// `AppLocalizations` делегати уланмаганда `context.tr(key)` калитнинг ўзини
// қайтаради — шунинг учун текширувлар калит матни бўйича.

JobAd _ad({
  String id = 'a1',
  String type = 'ad',
  String title = 'Ноутбук сотилади',
  String text = 'Ҳолати аъло',
  String status = 'active',
  String phone = '998901234567',
  String address = '',
  String districtId = '',
  DateTime? expiresAt,
}) =>
    JobAd(
      id: id,
      type: type,
      text: text,
      title: title,
      authorName: 'Эга',
      authorPhone: phone,
      address: address,
      isUrgent: false,
      status: status,
      districtId: districtId,
      expiresAt: expiresAt,
    );

class _Ctl extends JobsController {
  _Ctl({this.owner = false, bool admin = false})
      : super(repo: JobsRepository()) {
    isAdmin = admin;
  }

  final bool owner;

  @override
  bool isOwner(JobAd ad) => owner;
}

Widget _host(JobsController c, Widget child) =>
    ChangeNotifierProvider<JobsController>.value(
      value: c,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A3 — хато фойдаланувчига ички матн сифатида чиқмайди', () {
    FirebaseFunctionsException ex(String code, {String message = 'x', Object? details}) =>
        FirebaseFunctionsException(message: message, code: code, details: details);

    test('диагностик код → матн калити', () {
      expect(jobsErrorKey(ex('resource-exhausted', details: {'code': 'JOB_AD_DAILY_LIMIT'})),
          'jobs_err_daily_limit|10');
      expect(jobsErrorKey(ex('invalid-argument', details: {'code': 'JOB_AD_TITLE_LENGTH'})),
          'jobs_err_title_short');
      expect(jobsErrorKey(ex('invalid-argument', details: {'code': 'JOB_AD_TEXT_LENGTH'})),
          'jobs_err_text_short');
      expect(jobsErrorKey(ex('invalid-argument', details: {'code': 'JOB_AD_INVALID_TYPE'})),
          'jobs_err_unknown_type');
      expect(jobsErrorKey(ex('permission-denied', details: {'code': 'PHONE_MISMATCH'})),
          'jobs_err_permission');
    });

    test('сервернинг инглизча матни (message) ҲЕЧ ҚАЧОН калитга айланмайди', () {
      final k = jobsErrorKey(ex('invalid-argument', message: 'title 3..120'));
      expect(k, 'jobs_err_post');
      expect(k.contains('3..120'), isFalse);
      expect(jobsErrorKey(ex('internal', message: 'Phone mismatch')), 'jobs_err_post');
    });

    test('кодсиз, лекин маълум FirebaseFunctions кодлари', () {
      expect(jobsErrorKey(ex('unauthenticated')), 'jobs_err_login');
      expect(jobsErrorKey(ex('permission-denied')), 'jobs_err_permission');
      expect(jobsErrorKey(ex('resource-exhausted', message: 'Daily complaint limit reached'),
          fallback: 'jobs_err_generic'), 'ad_report_limit');
      expect(jobsErrorKey(ex('resource-exhausted', message: 'Daily ad limit reached')),
          'jobs_err_daily_limit|10');
    });

    test('ихтиёрий бошқа хато — умумий матн, `\$e` эмас', () {
      expect(jobsErrorKey(StateError('Индекс ёки сўров хатоси: boom')), 'jobs_err_post');
      expect(jobsErrorKey(Exception('x'), fallback: 'jobs_err_generic'), 'jobs_err_generic');
    });

    test('контроллер валидацияси калит қайтаради (қотирилган кирилл эмас)', () async {
      final c = _Ctl();
      final short = await c.submitAd(type: 'ad', title: 'ab', text: 'matn matn', isUrgent: false);
      expect(short.error, 'jobs_err_title_short');
      final noText = await c.submitAd(type: 'ad', title: 'Sarlavha', text: 'x', isUrgent: false);
      expect(noText.error, 'jobs_err_text_short');
      final badType = await c.submitAd(type: 'cheap_product', title: 'Sarlavha', text: 'matn', isUrgent: false);
      expect(badType.error, 'jobs_err_unknown_type');
      final noPhone = await c.submitAd(type: 'ad', title: 'Sarlavha', text: 'matn', isUrgent: false);
      expect(noPhone.error, 'jobs_err_phone');
    });
  });

  group('B8 — requestId (идемпотентлик) ва Тошкент куни', () {
    test('бир хил мазмун → бир хил id; таҳрирланган мазмун → янги id', () {
      String id(String text, {bool urgent = false}) => JobsController.requestIdFor(
            'seed1234',
            type: 'ad', title: 'Сарлавҳа', text: text, priceText: '', isUrgent: urgent);
      expect(id('матн'), id('матн'));
      expect(id('матн'), isNot(id('матн 2')));
      expect(id('матн'), isNot(id('матн', urgent: true)));
    });

    test('id сервер regex\'ига мос: [A-Za-z0-9_-]{8,64}', () {
      final seed = JobsController.newRequestSeed();
      final rid = JobsController.requestIdFor(seed,
          type: 'service', title: 'Сарлавҳа', text: 'матн', priceText: '5 сўм', isUrgent: false);
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(rid), isTrue, reason: rid);
      expect(JobsController.newRequestSeed(), isNot(seed));
    });

    test('tashkentDayStartUtc: Тошкент 00:00 = 19:00 UTC (кечаги кун)', () {
      // 2026-10-18 10:00 UTC = Тошкент 15:00 → кун боши 2026-10-17 19:00 UTC.
      expect(tashkentDayStartUtc(DateTime.utc(2026, 10, 18, 10)),
          DateTime.utc(2026, 10, 17, 19));
      // 2026-10-18 19:30 UTC = Тошкент 00:30 (18-куни охири эмас, 19-куни) → 18 19:00 UTC.
      expect(tashkentDayStartUtc(DateTime.utc(2026, 10, 18, 19, 30)),
          DateTime.utc(2026, 10, 18, 19));
      // Чегара: айнан 19:00 UTC — янги Тошкент куни бошланди.
      expect(tashkentDayStartUtc(DateTime.utc(2026, 10, 18, 19)),
          DateTime.utc(2026, 10, 18, 19));
      expect(tashkentDayStartUtc(DateTime.utc(2026, 10, 18, 18, 59, 59)),
          DateTime.utc(2026, 10, 17, 19));
    });

    test('қурилма вақт зонасидан мустақил (local DateTime ҳам тўғри)', () {
      final local = DateTime.utc(2026, 1, 1, 12).toLocal();
      expect(tashkentDayStartUtc(local), DateTime.utc(2025, 12, 31, 19));
    });
  });

  group('B7 — саҳифалаш ҳолати', () {
    test('чегарага яқин натижа → "яна юклаш"; янги эълон келмаса — тугади', () {
      final c = _Ctl();
      expect(c.debugLimit, JobsController.pageSize);
      expect(c.canLoadMore, isFalse); // ҳали ҳеч нарса келмаган
      c.debugFeedEvent(50);
      expect(c.canLoadMore, isTrue);
      c.loadMore();
      expect(c.debugLimit, 100);
      c.debugFeedEvent(100);
      expect(c.canLoadMore, isTrue);
      c.loadMore();
      expect(c.debugLimit, 150);
      c.debugFeedEvent(100); // янги эълон келмади → бошқа йўқ
      expect(c.canLoadMore, isFalse);
    });

    test('кам эълон → тугма йўқ', () {
      final c = _Ctl();
      c.debugFeedEvent(12);
      expect(c.canLoadMore, isFalse);
    });

    test('юқори чегара 500 дан ошмайди', () {
      final c = _Ctl();
      var n = 50;
      c.debugFeedEvent(n);
      for (var i = 0; i < 20 && c.canLoadMore; i++) {
        c.loadMore();
        n = c.debugLimit;
        c.debugFeedEvent(n);
      }
      expect(c.debugLimit, JobsController.maxLimit);
      expect(c.canLoadMore, isFalse);
    });

    test('reload() саҳифалашни бошидан бошлайди', () {
      final c = _Ctl();
      c.debugFeedEvent(50);
      c.loadMore();
      c.reload();
      expect(c.debugLimit, JobsController.pageSize);
    });
  });

  group('AdCard (B4, B5, B6)', () {
    testWidgets('B4: эга учун қалам йўқ — ФАҚАТ битта "Таҳрирлаш" тугмаси', (t) async {
      await t.pumpWidget(_host(_Ctl(owner: true), AdCard(ad: _ad())));
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.text('jobs_card_edit'), findsOneWidget);
      expect(find.text('jobs_card_mine'), findsOneWidget);
    });

    testWidgets('B4: бошқа одам эълонида — шикоят байроғи ва "Қўнғироқ"', (t) async {
      await t.pumpWidget(_host(_Ctl(), AdCard(ad: _ad())));
      expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
      expect(find.text('jobs_card_call'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
      // Шикоят тугмаси камида 48dp.
      final sz = t.getSize(find.byType(IconButton).first);
      expect(sz.width >= 48 && sz.height >= 48, isTrue, reason: '$sz');
    });

    testWidgets('B4: узун матн босилса тўлиқ очилади ва яна йиғилади', (t) async {
      final long = 'Жуда узун матн ' * 20;
      await t.pumpWidget(_host(_Ctl(), AdCard(ad: _ad(title: 'Қисқа', text: long))));
      expect(find.text('jobs_card_expand'), findsOneWidget);
      Text sub() => t.widget<Text>(find.text(long));
      expect(sub().maxLines, 3);
      await t.tap(find.text('jobs_card_expand'));
      await t.pump();
      expect(sub().maxLines, isNull);
      expect(find.text('jobs_card_collapse'), findsOneWidget);
      await t.tap(find.text('jobs_card_collapse'));
      await t.pump();
      expect(sub().maxLines, 3);
    });

    testWidgets('B4: қисқа матнда “Тўлиқ кўриш” ҳаволаси чиқмайди', (t) async {
      await t.pumpWidget(_host(_Ctl(), AdCard(ad: _ad())));
      expect(find.text('jobs_card_expand'), findsNothing);
      expect(AdCard.isLong(_ad()), isFalse);
      expect(AdCard.isLong(_ad(title: 'x' * 71)), isTrue);
    });

    testWidgets('B5: яроқсиз телефонда "Қўнғироқ" жимгина қайтмайди — хабар чиқади', (t) async {
      await t.pumpWidget(_host(_Ctl(), AdCard(ad: _ad(phone: '123'))));
      await t.tap(find.text('jobs_card_call'));
      await t.pump();
      expect(find.text('ad_details_phone_invalid'), findsOneWidget);
    });

    testWidgets('B6: хом address (эски эълонда уй манзили) КЎРСАТИЛМАЙДИ', (t) async {
      await t.pumpWidget(_host(
          _Ctl(), AdCard(ad: _ad(address: 'Гурлан, Навоий кўчаси 12-уй, 4-хона'))));
      expect(find.textContaining('Навоий'), findsNothing);
      expect(find.byIcon(Icons.location_on), findsNothing);
    });

    testWidgets('B6: туман id бўлса — фақат туман номи', (t) async {
      GeoNames.remember(districts: const [
        GeoDistrict(
            id: 'gurlan_t', regionId: 'xorazm', name: 'Gurlan tumani', nameUz: 'Гурлан тумани'),
      ]);
      await t.pumpWidget(_host(
          _Ctl(),
          AdCard(ad: _ad(
            address: 'Гурлан, Навоий кўчаси 12-уй',
            districtId: 'gurlan_t',
          ))));
      await t.pump();
      expect(find.textContaining('Навоий'), findsNothing);
      expect(find.textContaining('Гурлан'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });
  });

  group('A4 — шикоят сабаби: экранда маҳаллий, серверга бир хил матн', () {
    testWidgets('танланганда кирилл payload қайтади', (t) async {
      String? picked;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => picked = await showComplaintSheet(ctx),
            child: const Text('open'),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.textContaining('ad_report_reason_spam'), findsOneWidget);
      expect(find.text('ad_report_title'), findsOneWidget);
      await t.tap(find.textContaining('ad_report_reason_spam'));
      await t.pumpAndSettle();
      expect(picked, '🗑️ Спам / Такрорий');
    });
  });

  group('A2 — «Менинг эълонларим»', () {
    Future<void> pumpMy(WidgetTester t, Stream<List<JobAd>> s) => t.pumpWidget(
        _host(_Ctl(owner: true), SizedBox(height: 800, child: JobsMyAdsScreen(stream: s))));

    testWidgets('текширувдаги ва рад этилган эълон ҲАМ кўринади, ҳолат белгиси билан', (t) async {
      final past = DateTime.now().subtract(const Duration(days: 1));
      await pumpMy(
        t,
        Stream.value([
          _ad(id: 'p', title: 'Текширувда', status: 'pending'),
          _ad(id: 'b', title: 'Рад', status: 'blocked'),
          _ad(id: 'x', title: 'Эски', status: 'active', expiresAt: past),
          _ad(id: 'l', title: 'Фаол', status: 'active'),
        ]),
      );
      await t.pump();
      expect(find.text('jobs_status_pending'), findsOneWidget);
      expect(find.text('jobs_my_ads_pending_hint'), findsOneWidget);
      expect(find.text('jobs_status_blocked'), findsOneWidget);
      expect(find.text('jobs_status_expired'), findsOneWidget);
      expect(find.text('jobs_status_active'), findsOneWidget);
      expect(find.text('Текширувда'), findsOneWidget);
    });

    testWidgets('бўш рўйхат', (t) async {
      await pumpMy(t, Stream.value(const <JobAd>[]));
      await t.pump();
      expect(find.text('jobs_my_ads_empty'), findsOneWidget);
    });

    testWidgets('хато — умумий матн + қайта уриниш (ички матнсиз)', (t) async {
      await pumpMy(t, Stream<List<JobAd>>.error(StateError('secret-internal-detail')));
      await t.pump();
      expect(find.text('jobs_load_error'), findsOneWidget);
      expect(find.text('home_section_retry'), findsOneWidget);
      expect(find.textContaining('secret-internal-detail'), findsNothing);
    });
  });

  group('JobsSections — матн калитлари', () {
    test('ҳолат калити: муддати ўтган фаол алоҳида', () {
      expect(JobsSections.statusKeyFor('active', expired: true), 'jobs_status_expired');
      expect(JobsSections.statusKeyFor('active', expired: false), 'jobs_status_active');
      expect(JobsSections.statusKeyFor('pending', expired: true), 'jobs_status_pending');
      expect(JobsSections.statusKeyFor('blocked', expired: false), 'jobs_status_blocked');
      expect(JobsSections.statusKeyFor('completed', expired: false), 'jobs_status_completed');
    });

    test('B3: хизмат варағи "ХИЗМАТ", эълон варағи "ЭЪЛОН"', () {
      expect(JobsSections.submitKeyFor(AdKind.service), 'jobs_submit_service');
      expect(JobsSections.submitKeyFor(AdKind.ad), 'jobs_submit_ad');
      expect(JobsSections.postedKeyFor(AdKind.service, live: true), 'jobs_posted_service');
      expect(JobsSections.postedKeyFor(AdKind.service, live: false), 'jobs_review_service');
      expect(JobsSections.postedKeyFor(AdKind.ad, live: false), 'jobs_review_ad');
    });
  });
}
