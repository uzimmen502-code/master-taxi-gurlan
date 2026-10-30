import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/admin_web/screens/business_admin_screen.dart';
import 'package:ava_gurlan/features/business_map/data/business_repository.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/screens/business_form_screen.dart';
import 'package:ava_gurlan/features/business_map/screens/my_businesses_screen.dart';
import 'package:ava_gurlan/features/home/widgets/home_business_section.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Firebase'сиз: репозиторийнинг тармоқ қисмлари алмаштирилган.
class _FakeRepo extends BusinessRepository {
  _FakeRepo(this.rows);

  List<Business> rows;
  final calls = <String>[];
  Object? failWith;
  final _mine = StreamController<List<Business>>.broadcast();

  @override
  Future<List<Business>> fetchRecent({int limit = 200}) async => rows;

  @override
  Stream<List<Business>> watchMine(String ownerId) async* {
    yield rows;
    yield* _mine.stream;
  }

  @override
  Future<String> upsertMine(Business b, {String? businessId, required String clientRequestId}) async {
    calls.add('upsert:${businessId ?? 'new'}:${b.name}:${b.category.wire}:$clientRequestId');
    if (failWith != null) throw failWith!;
    return 'id1';
  }

  Object? deleteFailsWith;

  @override
  Future<void> deleteMine(String businessId) async {
    if (deleteFailsWith != null) throw deleteFailsWith!;
    calls.add('delete:$businessId');
  }

  @override
  Future<String> adminCreate(
    Business b, {
    required String reason,
    required String clientRequestId,
    String ownerPhone = '',
  }) async {
    calls.add('adminCreate:${b.name}:${b.category.wire}:${b.lat},${b.lng}:owner=$ownerPhone:$reason');
    return 'admin_new';
  }

  @override
  Future<void> adminUpdate(Business b, {required String reason}) async =>
      calls.add('adminUpdate:${b.id}:${b.name}:$reason');

  @override
  Future<void> adminDelete(String businessId, {required String reason}) async =>
      calls.add('adminDelete:$businessId:$reason');
}

/// Обуна кейинроқ янгиланади (янги объект бирданига рўйхатга тушмайди).
class _LateRepo extends _FakeRepo {
  _LateRepo() : super([]);

  final live = StreamController<List<Business>>.broadcast();

  @override
  Stream<List<Business>> watchMine(String ownerId) => live.stream;
}

Business _b(String id, String name, BusinessCategory c, {String owner = '998901111111'}) => Business(
      id: id,
      ownerId: owner,
      name: name,
      category: c,
      phone: '998901234567',
      lat: 41.3,
      lng: 69.2,
      address: 'Тошкент',
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1200 * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

/// Обуна маълумот бермагунча спиннер айланади — `pumpAndSettle`сиз.
Future<void> _pumpNoSettle(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1200 * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
}

void main() {
  group('BusinessAdminScreen', () {
    testWidgets('рўйхат, қидирув ва тур бўйича фильтр; «қўшиш» тугмаси БОР (эга қарори 2026-10-23)', (tester) async {
      final repo = _FakeRepo([
        _b('1', 'Авто Мойка', BusinessCategory.auto),
        _b('2', 'Нон дўкони', BusinessCategory.retail, owner: '998902222222'),
      ]);
      await _pump(tester, BusinessAdminScreen(repository: repo));
      expect(find.text('Авто Мойка'), findsOneWidget);
      expect(find.text('Нон дўкони'), findsOneWidget);
      expect(find.byKey(const ValueKey('biz_admin_add')), findsOneWidget, reason: 'админ ҳам объект қўша олади');

      await tester.enterText(find.byType(TextField).first, 'нон');
      await tester.pumpAndSettle();
      expect(find.text('Авто Мойка'), findsNothing);
      expect(find.text('Нон дўкони'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '998902222222'); // эга рақами бўйича
      await tester.pumpAndSettle();
      expect(find.text('Нон дўкони'), findsOneWidget);
    });

    testWidgets('қўшиш: ном/координата/сабабсиз юборилмайди; тўлдирилса adminCreate (эга телефони билан)', (tester) async {
      final repo = _FakeRepo([]);
      await _pump(tester, BusinessAdminScreen(repository: repo));
      await tester.tap(find.byKey(const ValueKey('biz_admin_add')));
      await tester.pumpAndSettle();
      expect(find.text('Объект қўшиш'), findsWidgets);
      expect(find.byKey(const ValueKey('biz_admin_pick_map')), findsOneWidget, reason: 'пин билан белгилаш тугмаси');
      expect(find.widgetWithText(TextField, 'Эга телефони (ихтиёрий; бўш бўлса — эгасиз, фақат админ таҳрирлайди)'), findsOneWidget);

      // Координатасиз
      await tester.tap(find.text('Қўшиш'));
      await tester.pumpAndSettle();
      expect(find.text('Координата нотўғри'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Номи'), 'Янги мойка');
      await tester.enterText(find.widgetWithText(TextField, 'Телефон'), '998901234567');
      await tester.enterText(find.widgetWithText(TextField, 'Кенглик (lat)'), '41.84');
      await tester.enterText(find.widgetWithText(TextField, 'Узунлик (lng)'), '60.39');
      // Сабабсиз
      await tester.tap(find.text('Қўшиш'));
      await tester.pumpAndSettle();
      expect(find.text('Сабабни ёзинг'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Эга телефони (ихтиёрий; бўш бўлса — эгасиз, фақат админ таҳрирлайди)'), '998912000001');
      await tester.enterText(find.widgetWithText(TextField, 'Қўшиш сабаби (шарт)'), 'телефонда келишилди');
      await tester.tap(find.text('Қўшиш'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['adminCreate:Янги мойка:retail:41.84,60.39:owner=998912000001:телефонда келишилди']);
    });

    testWidgets('ўчириш: сабаб ёзилмагунча тугма ўчик; сабаб билан adminDelete чақирилади', (tester) async {
      final repo = _FakeRepo([_b('1', 'Авто Мойка', BusinessCategory.auto)]);
      await _pump(tester, BusinessAdminScreen(repository: repo));
      await tester.tap(find.byTooltip('Ўчириш'));
      await tester.pumpAndSettle();

      final confirm = find.widgetWithText(TextButton, 'Ўчириш');
      expect(tester.widget<TextButton>(confirm).onPressed, isNull, reason: 'сабабсиз ўчириб бўлмайди');
      await tester.enterText(find.byType(TextField).last, 'сохта эълон');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.calls, ['adminDelete:1:сохта эълон']);
    });

    testWidgets('таҳрир: сабабсиз сақланмайди; сабаб билан adminUpdate', (tester) async {
      final repo = _FakeRepo([_b('1', 'Авто Мойка', BusinessCategory.auto)]);
      await _pump(tester, BusinessAdminScreen(repository: repo));
      await tester.tap(find.byTooltip('Таҳрирлаш'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Сақлаш'));
      await tester.pumpAndSettle();
      expect(find.text('Сабабни ёзинг'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Таҳрир сабаби (шарт)'), 'имло');
      await tester.tap(find.text('Сақлаш'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['adminUpdate:1:Авто Мойка:имло']);
    });
  });

  group('HomeBusinessSection', () {
    testWidgets('тор экранда ҳам оверфлоу йўқ ва иккала тугма босилади', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      var opened = 0;
      var added = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: HomeBusinessSection(onOpenMap: () => opened++, onAddMine: () => added++),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'RenderFlex overflow бўлмаслиги керак');
      await tester.tap(find.text('bizmap_open_map'));
      await tester.tap(find.text('bizmap_add_mine'));
      expect([opened, added], [1, 1]);
    });
  });

  group('MyBusinessesScreen', () {
    testWidgets('бўш рўйхат — тушунтириш матни, FAB ва бўш ҳолатдаги «қўшиш» тугмаси форма очади', (tester) async {
      final empty = _FakeRepo([]);
      final opened = <Business?>[];
      await _pump(
        tester,
        MyBusinessesScreen(
          repository: empty,
          ownerId: '998901111111',
          openForm: (context, existing) async {
            opened.add(existing);
            return null;
          },
        ),
      );
      expect(find.text('bizmap_my_empty'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      final emptyAdd = find.byKey(const ValueKey('my_biz_empty_add'));
      expect(emptyAdd, findsOneWidget);
      expect(find.descendant(of: emptyAdd, matching: find.text('bizmap_add_mine')), findsOneWidget);
      await tester.tap(emptyAdd);
      await tester.pumpAndSettle();
      expect(opened, [null], reason: 'FAB каби — янги объект формаси');
    });

    testWidgets('рўйхат бор бўлса — бўш ҳолат тугмаси йўқ', (tester) async {
      final one = _FakeRepo([_b('1', 'Мой Дўкон', BusinessCategory.retail)]);
      await _pump(tester, MyBusinessesScreen(repository: one, ownerId: '998901111111'));
      expect(find.byKey(const ValueKey('my_biz_empty_add')), findsNothing);
    });

    testWidgets('телефон йўқ (бўш ownerId) — сўров юборилмайди, «профилда телефон» ҳолати', (tester) async {
      final repo = _FakeRepo([_b('1', 'Бегона', BusinessCategory.retail, owner: '')]);
      await _pump(tester, MyBusinessesScreen(repository: repo, ownerId: ''));
      expect(find.byKey(const ValueKey('my_biz_need_phone')), findsOneWidget);
      expect(find.text('need_phone_profile'), findsOneWidget);
      expect(find.text('Бегона'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    // Янги объектдан кейин: маҳсулот сотадиган тур — маҳсулотлар экрани дарров; бошқа тур — рўйхатда қолади.
    Future<void> createVia(WidgetTester tester, List<Business> rows, Object? formResult) async {
      await _pump(
        tester,
        MyBusinessesScreen(
          key: UniqueKey(),
          repository: _FakeRepo(rows),
          ownerId: '998901111111',
          openForm: (context, existing) async => formResult,
          productsScreen: (b) => Scaffold(body: Text('PRODUCTS ${b.id}')),
        ),
      );
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
    }

    testWidgets('янги чакана объект (ID қайтди) — маҳсулотлар экрани очилади', (tester) async {
      await createVia(tester, [_b('n1', 'Янги дўкон', BusinessCategory.retail)], 'n1');
      expect(find.text('PRODUCTS n1'), findsOneWidget);
    });

    testWidgets('янги улгуржи объект — маҳсулотлар экрани очилади', (tester) async {
      await createVia(tester, [_b('w1', 'Омбор', BusinessCategory.wholesale)], 'w1');
      expect(find.text('PRODUCTS w1'), findsOneWidget);
    });

    testWidgets('янги кафе (food) — маҳсулотлар экрани очилмайди, рўйхатда қолади', (tester) async {
      await createVia(tester, [_b('f1', 'Ошхона', BusinessCategory.food)], 'f1');
      expect(find.textContaining('PRODUCTS'), findsNothing);
      expect(find.text('Ошхона'), findsOneWidget);
    });

    testWidgets('таҳрир/филиал (true) ёки бекор (null) — маҳсулотлар экрани очилмайди', (tester) async {
      await createVia(tester, [_b('n1', 'Янги дўкон', BusinessCategory.retail)], true);
      expect(find.textContaining('PRODUCTS'), findsNothing);
      await createVia(tester, [_b('n1', 'Янги дўкон', BusinessCategory.retail)], null);
      expect(find.textContaining('PRODUCTS'), findsNothing);
    });

    testWidgets('янги объект кечикиб рўйхатга тушади — обуна орқали топилиб очилади', (tester) async {
      final repo = _LateRepo();
      await _pumpNoSettle(
        tester,
        MyBusinessesScreen(
          repository: repo,
          ownerId: '998901111111',
          openForm: (context, existing) async => 'late1',
          productsScreen: (b) => Scaffold(body: Text('PRODUCTS ${b.id}')),
        ),
      );
      repo.live.add([_b('old', 'Эски', BusinessCategory.auto)]);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(find.textContaining('PRODUCTS'), findsNothing, reason: 'ҳали рўйхатда йўқ');
      repo.live.add([_b('late1', 'Кечиккан', BusinessCategory.retail), _b('old', 'Эски', BusinessCategory.auto)]);
      await tester.pumpAndSettle();
      expect(find.text('PRODUCTS late1'), findsOneWidget);
    });

    testWidgets('янги объект муддат ичида рўйхатга тушмаса — ҳеч нарса очилмайди, рўйхатда қолади', (tester) async {
      final repo = _LateRepo();
      await _pumpNoSettle(
        tester,
        MyBusinessesScreen(
          repository: repo,
          ownerId: '998901111111',
          openForm: (context, existing) async => 'never',
          productsScreen: (b) => Scaffold(body: Text('PRODUCTS ${b.id}')),
        ),
      );
      repo.live.add([_b('old', 'Эски', BusinessCategory.auto)]);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.textContaining('PRODUCTS'), findsNothing);
      expect(find.text('Эски'), findsOneWidget);
    });

    testWidgets('ўчириш: блокланган объект — аниқ сабаб, хом хато йўқ', (tester) async {
      final repo = _FakeRepo([_b('1', 'Мой Дўкон', BusinessCategory.retail)])
        ..deleteFailsWith = FirebaseFunctionsException(
            code: 'failed-precondition', message: 'raw', details: {'code': 'BUSINESS_BLOCKED'});
      await _pump(tester, MyBusinessesScreen(repository: repo, ownerId: '998901111111'));
      await tester.tap(find.byTooltip('bizmap_delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'bizmap_delete'));
      await tester.pumpAndSettle();
      expect(find.text('bizmap_delete_blocked'), findsOneWidget);
      expect(find.text('raw'), findsNothing);
    });

    testWidgets('ўчириш: бошқа хато — умумий хабар', (tester) async {
      final repo = _FakeRepo([_b('1', 'Мой Дўкон', BusinessCategory.retail)])..deleteFailsWith = StateError('boom');
      await _pump(tester, MyBusinessesScreen(repository: repo, ownerId: '998901111111'));
      await tester.tap(find.byTooltip('bizmap_delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'bizmap_delete'));
      await tester.pumpAndSettle();
      expect(find.text('bizmap_err_generic'), findsOneWidget);
      expect(find.text('bizmap_delete_blocked'), findsNothing);
    });

    testWidgets('объект бор — карточка (ном, тур)', (tester) async {
      final one = _FakeRepo([_b('1', 'Мой Дўкон', BusinessCategory.retail)]);
      await _pump(tester, MyBusinessesScreen(repository: one, ownerId: '998901111111'));
      expect(find.text('Мой Дўкон'), findsOneWidget);
      expect(find.textContaining('business_cat_retail'), findsOneWidget);
    });

    testWidgets('ўчириш: тасдиқдан кейин deleteMine', (tester) async {
      final repo = _FakeRepo([_b('1', 'Мой Дўкон', BusinessCategory.retail)]);
      await _pump(tester, MyBusinessesScreen(repository: repo, ownerId: '998901111111'));
      await tester.tap(find.byTooltip('bizmap_delete'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty, reason: 'тасдиқсиз ўчирилмайди');
      await tester.tap(find.widgetWithText(TextButton, 'bizmap_delete'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['delete:1']);
    });
  });

  group('BusinessFormScreen', () {
    testWidgets('мажбурий майдонсиз сервер чақирилмайди ва хато матни чиқади', (tester) async {
      final repo = _FakeRepo([]);
      await _pump(tester, BusinessFormScreen(repository: repo));
      await tester.tap(find.text('bizmap_save'));
      await tester.pumpAndSettle();
      expect(find.text('bizmap_err_name'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.enterText(find.byType(TextField).first, 'Дўкон');
      await tester.tap(find.text('bizmap_save'));
      await tester.pumpAndSettle();
      expect(find.text('bizmap_err_category'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('таҳрирда майдонлар тўлдирилган; жой бор бўлса "белгиланди" ёзуви', (tester) async {
      final repo = _FakeRepo([]);
      await _pump(tester, BusinessFormScreen(repository: repo, existing: _b('1', 'Мой Дўкон', BusinessCategory.retail)));
      expect(find.text('bizmap_form_edit'), findsOneWidget);
      expect(find.text('Мой Дўкон'), findsOneWidget);
      expect(find.text('bizmap_location_set'), findsOneWidget);
    });

    testWidgets('тўлиқ мавжуд объект сақланади: businessId билан upsert, тур serverга wire кўринишида', (tester) async {
      final repo = _FakeRepo([]);
      await _pump(tester, BusinessFormScreen(repository: repo, existing: _b('7', 'Мой Дўкон', BusinessCategory.retail)));
      await tester.ensureVisible(find.text('bizmap_save'));
      await tester.tap(find.text('bizmap_save'));
      await tester.pumpAndSettle();
      expect(repo.calls.single, startsWith('upsert:7:Мой Дўкон:retail:'));
    });

    testWidgets('«Ўз сайтингиз»: изоҳ кўринади; @ҳандл рад этилади; тўғри сайт сақланади', (tester) async {
      final repo = _FakeRepo([]);
      await _pump(tester, BusinessFormScreen(repository: repo, existing: _b('7', 'Мой Дўкон', BusinessCategory.retail)));
      final field = find.widgetWithText(TextField, 'bizmap_f_website');
      await tester.ensureVisible(field);
      expect(find.text('bizmap_f_website_hint'), findsOneWidget);

      await tester.enterText(field, '@kafe_gurlan');
      await tester.ensureVisible(find.text('bizmap_save'));
      await tester.tap(find.text('bizmap_save'));
      await tester.pumpAndSettle();
      expect(find.text('bizmap_err_website'), findsOneWidget);
      expect(repo.calls, isEmpty, reason: 'яроқсиз сайт билан сервер чақирилмайди');

      await tester.enterText(field, 'kafe.uz');
      await tester.tap(find.text('bizmap_save'));
      await tester.pumpAndSettle();
      expect(repo.calls.single, startsWith('upsert:7:Мой Дўкон:retail:'));
    });

    // Янги дўкондан кейин маҳсулотлар экрани (эга, 2026-10-26): форма янги объект ID'сини қайтаради.
    Future<Object?> saveViaRoute(WidgetTester tester, Widget form, Future<void> Function() fill) async {
      Object? result = 'not-popped';
      tester.view.physicalSize = const Size(1200 * 2, 1800 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => result = await Navigator.of(context).push<Object?>(MaterialPageRoute(builder: (_) => form)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await fill();
      await tester.ensureVisible(find.text('bizmap_save'));
      await tester.tap(find.text('bizmap_save'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('янги (онлайн) дўкон сақланса — форма янги ID ни қайтаради', (tester) async {
      final repo = _FakeRepo([]);
      final result = await saveViaRoute(
        tester,
        BusinessFormScreen(repository: repo, initialCategory: BusinessCategory.retail, lockCategory: true),
        () async {
          await tester.enterText(find.widgetWithText(TextField, 'bizmap_f_name'), 'Yangi do‘kon');
          await tester.enterText(find.widgetWithText(TextField, 'bizmap_f_phone'), '998901234567');
          await tester.ensureVisible(find.byKey(const ValueKey('biz_online_switch')));
          await tester.tap(find.byKey(const ValueKey('biz_online_switch')));
          await tester.pump();
        },
      );
      expect(repo.calls.single, startsWith('upsert:new:Yangi do‘kon:retail:'));
      expect(result, 'id1');
    });

    testWidgets('таҳрир сақланса — форма `true` қайтаради (маҳсулотлар экрани очилмайди)', (tester) async {
      final repo = _FakeRepo([]);
      final result = await saveViaRoute(
          tester, BusinessFormScreen(repository: repo, existing: _b('7', 'Мой Дўкон', BusinessCategory.retail)), () async {});
      expect(result, true);
    });

    testWidgets('сервер BUSINESS_LIMIT_REACHED қайтарса — тушунарли хато, ёпилмайди', (tester) async {
      final repo = _FakeRepo([])..failWith = StateError('x');
      await _pump(tester, BusinessFormScreen(repository: repo, existing: _b('7', 'Мой Дўкон', BusinessCategory.retail)));
      await tester.ensureVisible(find.text('bizmap_save'));
      await tester.tap(find.text('bizmap_save'));
      await tester.pumpAndSettle();
      expect(find.text('bizmap_err_generic'), findsOneWidget);
      expect(find.text('bizmap_form_edit'), findsOneWidget);
    });
  });
}
