// `service` UI adapter'и — валидация, тасдиқлаш қаторлари ва
// карточкаларнинг МАХФИЙЛИК қоидаси.
//
//   flutter test test/features/demand_offer/service_ui_adapter_test.dart
//
// Бу тестнинг энг муҳим қисми — охиридаги «МАХФИЙЛИК» гуруҳи: таклифчи
// кўрадиган карточкада аниқ манзил ва телефон ЧИҚМАСЛИГИ. Сервер уларни
// проекцияга ёзмайди, лекин карточка кодида хато бўлса (масалан
// `match.projection.attributes` ичидан манзил чиқариб қўйилса), ҳимоя
// жимгина бузилиши мумкин.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand_enums.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand_match.dart';
import 'package:ava_gurlan/features/demand_offer/domain/offer.dart';
import 'package:ava_gurlan/features/demand_offer/ui_adapters/demand_ui_adapter.dart';
import 'package:ava_gurlan/features/demand_offer/ui_adapters/service_ui_adapter.dart';

/// ЛОКАЛИЗАЦИЯ ДЕЛЕГАТИ АТАЙЛАБ ҚЎШИЛМАГАН.
///
/// `AppLocalizations.delegate` асинхрон (`rootBundle.loadString`) ва
/// `shouldReload => true` — яъни ҳар қайта чизишда қайта юкланади.
/// Виджет тестида бу `Localizations` ҳеч қачон «тайёр» бўлмаслигига
/// олиб келади ва бола дарахт умуман қурилмайди (`LateError`).
///
/// Делегатсиз `context.tr('key')` КАЛИТНИНГ ЎЗИНИ қайтаради — бу
/// тестлар учун етарли ва ҳатто афзал:
///   - махфийлик текшируви матнга эмас, МАЪЛУМОТГА қарайди
///     (манзил/телефон чиқмаслиги),
///   - калитлар таржима ўзгарганда тест синмайди.
///
/// Таржималарнинг ўзи `test/core/locale_sync_test.dart`да текширилади.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(width: 360, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const adapter = ServiceUiAdapter();

  DemandDraft draft({
    String? categoryId = 'santexnik',
    DemandPoint? location = const DemandPoint(
      lat: 41.55,
      lng: 60.63,
      addressText: 'Al-Xorazmiy 15-uy, 3-xonadon',
    ),
    String title = 'Kran oqyapti',
    String description = '',
    num? budgetMax,
    String timeMode = 'today',
  }) {
    final d = adapter.newDraft(clientRequestId: 'req-test-0001');
    d.categoryId = categoryId;
    d.location = location;
    d.title = title;
    d.description = description;
    d.budgetMax = budgetMax;
    d.timeMode = timeMode;
    return d;
  }

  group('newDraft', () {
    test('модул ва стандарт атрибутлар', () {
      final d = adapter.newDraft(clientRequestId: 'req-abc12345');
      expect(d.module, DemandModule.service);
      expect(d.clientRequestId, 'req-abc12345');
      expect(d.attributes['visitType'], 'at_my_place');
      expect(d.attributes['preferredTimeOfDay'], 'any');
    });

    test('«Талаб яратиш» техник матни ИШЛАТИЛМАЙДИ', () {
      // Концепциянинг ўзгармайдиган қоидаси.
      expect(adapter.primaryActionL10nKey, 'request_call_master');
      expect(adapter.primaryActionL10nKey.contains('demand'), isFalse);
    });
  });

  group('validate', () {
    test('тўғри драфт — хато йўқ', () {
      expect(adapter.validate(draft()).isValid, isTrue);
    });

    test('категория йўқ — хато', () {
      final v = adapter.validate(draft(categoryId: null));
      expect(v.isValid, isFalse);
      expect(v.errorFor('categoryId'), 'request_what_needed');
    });

    test('уста келадиган бўлса жойлашув ШАРТ', () {
      // Жойлашувсиз ким мослигини аниқлаб бўлмайди.
      final v = adapter.validate(draft(location: null));
      expect(v.isValid, isFalse);
      expect(v.errorFor('location'), 'request_where');
    });

    test('масофадан хизматда жойлашув шарт эмас', () {
      final d = draft(location: null);
      d.attributes['visitType'] = 'remote';
      final v = adapter.validate(d);
      expect(v.errorFor('location'), isNull);
    });

    test('сарлавҳа ҳам, изоҳ ҳам бўш — хато', () {
      final v = adapter.validate(draft(title: '', description: ''));
      expect(v.errorFor('title'), 'request_describe');
    });

    test('сарлавҳа қисқа, лекин изоҳ бор — ўтади', () {
      final v = adapter.validate(
        draft(title: '', description: 'Hammomdagi smesitel tomchilaydi'),
      );
      expect(v.errorFor('title'), isNull);
    });

    test('манфий бюджет — хато', () {
      final v = adapter.validate(draft(budgetMax: -100));
      expect(v.errorFor('budgetMax'), 'request_budget');
    });

    test('хато матнлари КАЛИТ (тайёр матн эмас)', () {
      // Тайёр матн бўлса учала локал файлга тушмай қоларди.
      final v = adapter.validate(draft(categoryId: null, location: null));
      for (final key in v.errors.values) {
        expect(key, matches(RegExp(r'^[a-z_]+$')),
            reason: 'хато матни калит бўлиши керак, олинган: $key');
      }
    });
  });

  group('prefillFromIntent', () {
    test('аниқ категория тўлдирилади', () {
      final d = adapter.newDraft(clientRequestId: 'req-abc12345');
      adapter.prefillFromIntent(
        d,
        const IntentResult(
          rawText: 'кран оқяпти',
          module: DemandModule.service,
          categoryId: 'santexnik',
        ),
      );
      expect(d.categoryId, 'santexnik');
      expect(d.source, 'intent_card');
      expect(d.inputType, 'text');
      expect(d.rawText, 'кран оқяпти');
      expect(d.title, 'кран оқяпти');
    });

    test('КЎП МАЪНОЛИ сўзда категория ҚЎЙИЛМАЙДИ', () {
      // «котёл» → газ устаси ёки иситиш тизими. AVA ўзи танламайди.
      final d = adapter.newDraft(clientRequestId: 'req-abc12345');
      adapter.prefillFromIntent(
        d,
        const IntentResult(
          rawText: 'котёл ишламайди',
          module: DemandModule.service,
          needsChoice: true,
          candidateCategoryIds: ['gaz_ustasi', 'isitish_tizimi'],
        ),
      );
      expect(d.categoryId, isNull,
          reason: 'фойдаланувчи ўзи танлаши керак');
      expect(d.rawText, 'котёл ишламайди');
    });

    test('узун матн 120 белгига қисқартирилади', () {
      final d = adapter.newDraft(clientRequestId: 'req-abc12345');
      adapter.prefillFromIntent(
        d,
        IntentResult(rawText: 'a' * 300, module: DemandModule.service),
      );
      expect(d.title.length, 120);
    });
  });

  group('buildConfirmRows', () {
    testWidgets('асосий қаторлар бор', (tester) async {
      late List<ConfirmRow> rows;
      await _pump(
        tester,
        Builder(builder: (ctx) {
          rows = adapter.buildConfirmRows(ctx, draft(budgetMax: 200000));
          return const SizedBox();
        }),
      );

      final labels = rows.map((r) => r.labelKey).toList();
      expect(labels, contains('request_what_needed'));
      expect(labels, contains('request_where'));
      expect(labels, contains('request_when'));
      expect(labels, contains('request_budget'));
    });

    testWidgets('ҳар бир қатор тузатиш майдонини кўрсатади', (tester) async {
      late List<ConfirmRow> rows;
      await _pump(
        tester,
        Builder(builder: (ctx) {
          rows = adapter.buildConfirmRows(ctx, draft());
          return const SizedBox();
        }),
      );
      for (final r in rows) {
        expect(r.editField, isNotNull,
            reason: '«${r.labelKey}» қатори тузатилиши керак');
      }
    });

    testWidgets('тасдиқлашда фойдаланувчига ЎЗ манзили кўрсатилади',
        (tester) async {
      // Бу экран фойдаланувчининг ЎЗИГА кўрсатилади, шунинг учун аниқ
      // манзил тўғри. Таклифчига борадиган проекцияда эса бўлмайди.
      late List<ConfirmRow> rows;
      await _pump(
        tester,
        Builder(builder: (ctx) {
          rows = adapter.buildConfirmRows(ctx, draft());
          return const SizedBox();
        }),
      );
      final where = rows.firstWhere((r) => r.labelKey == 'request_where');
      expect(where.value, contains('15-uy'));
    });
  });

  group('МАХФИЙЛИК — таклифчи карточкаси', () {
    DemandMatch match({Map<String, dynamic>? projection}) {
      return DemandMatch.fromMap('dem123_998902220002', {
        'demandId': 'dem123',
        'providerId': '998902220002',
        'module': 'service',
        'mode': 'quote',
        'status': 'new',
        'score': 0.76,
        'sources': ['capabilities'],
        'consentGiven': true,
        'metrics': {'distanceKm': 1.4},
        'projection': projection ??
            {
              'title': 'Kran oqyapti',
              'description': 'Hammomdagi smesitel tomchilaydi',
              'categoryId': 'santexnik',
              'districtId': 'urganch_sh',
              'approxLat': 41.5538,
              'approxLng': 60.6271,
              'geohash': 'tr7h7',
              'budget': {'max': 200000},
            },
        'expiresAt': DateTime.now().add(const Duration(hours: 2))
            .toIso8601String(),
      });
    }

    testWidgets('карточка матнида манзил ва телефон чиқмайди',
        (tester) async {
      final m = match();
      await _pump(
        tester,
        Builder(builder: (ctx) => adapter.buildMatchCard(ctx, m)),
      );

      // Экрандаги БАРЧА матнни йиғамиз.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');

      expect(texts.contains('15-uy'), isFalse,
          reason: 'аниқ манзил карточкада чиқди');
      expect(texts.contains('3-xonadon'), isFalse,
          reason: 'хонадон рақами карточкада чиқди');
      expect(RegExp(r'998\d{9}').hasMatch(texts), isFalse,
          reason: 'телефон карточкада чиқди');
      // Лекин ишлаш учун керакли маълумот БОР.
      expect(texts.contains('Kran oqyapti'), isTrue);
      expect(texts.contains('1.4'), isTrue, reason: 'масофа кўрсатилиши керак');
    });

    testWidgets('тахминий жой изоҳи кўрсатилади', (tester) async {
      final m = match();
      await _pump(
        tester,
        Builder(builder: (ctx) => adapter.buildMatchCard(ctx, m)),
      );
      // Фойдаланувчи «нега аниқ манзил йўқ?» деб ўйламаслиги керак.
      expect(find.text('match_approx_location'), findsOneWidget);
    });

    testWidgets('атрибутлардан манзил чиқиб кетмайди', (tester) async {
      // Ҳимоя: кимдир проекцияга `accessNotes` ичида манзил ёзса ҳам
      // (сервер буни кесади), карточка уни кўрсатмайди.
      final m = match(projection: {
        'title': 'Kran oqyapti',
        'districtId': 'urganch_sh',
        'geohash': 'tr7h7',
        'attributes': {
          'accessNotes': 'Al-Xorazmiy 15-uy, 3-xonadon, tel 998901234567',
        },
      });
      await _pump(
        tester,
        Builder(builder: (ctx) => adapter.buildMatchCard(ctx, m)),
      );
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');
      expect(texts.contains('15-uy'), isFalse);
      expect(RegExp(r'998\d{9}').hasMatch(texts), isFalse);
    });
  });

  group('Таклиф карточкаси', () {
    Offer offer({num? price = 150000, bool delivery = false, double? rating}) {
      final o = Offer.fromMap('998902220002', {
        'providerId': '998902220002',
        'demandId': 'dem123',
        'status': 'active',
        'price': price,
        'message': '18:00 gacha boraman',
        'etaMinutes': 40,
        'delivery': delivery,
      });
      return o.withProviderInfo(name: 'Alisher', rating: rating);
    }

    testWidgets('нарх ва ETA кўрсатилади', (tester) async {
      await _pump(
        tester,
        Builder(builder: (ctx) => adapter.buildOfferCard(ctx, offer(), null)),
      );
      expect(find.textContaining('150 000'), findsOneWidget);
      expect(find.textContaining('40'), findsOneWidget);
      expect(find.text('Alisher'), findsOneWidget);
    });

    testWidgets('нархсиз таклиф — «Келишамиз»', (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (ctx) => adapter.buildOfferCard(ctx, offer(price: null), null),
        ),
      );
      expect(find.text('offer_price_negotiable'), findsOneWidget);
    });

    testWidgets('рейтингсиз таклифчи «Янги» белгиси билан', (tester) async {
      await _pump(
        tester,
        Builder(builder: (ctx) => adapter.buildOfferCard(ctx, offer(), null)),
      );
      expect(find.text('offer_no_rating'), findsWidgets);
    });

    testWidgets('«Танлаш» тугмаси onChoose берилганда', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        Builder(
          builder: (ctx) => adapter.buildOfferCard(
            ctx,
            offer(),
            () => tapped = true,
          ),
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(tapped, isTrue);
    });

    testWidgets('onChoose йўқ бўлса тугма ҳам йўқ', (tester) async {
      await _pump(
        tester,
        Builder(builder: (ctx) => adapter.buildOfferCard(ctx, offer(), null)),
      );
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
