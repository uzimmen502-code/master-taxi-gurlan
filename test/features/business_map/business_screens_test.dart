import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/admin_web/screens/business_admin_screen.dart';
import 'package:ava_gurlan/features/business_map/data/business_repository.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/screens/business_form_screen.dart';
import 'package:ava_gurlan/features/business_map/screens/my_businesses_screen.dart';
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

  @override
  Future<void> deleteMine(String businessId) async => calls.add('delete:$businessId');

  @override
  Future<void> adminUpdate(Business b, {required String reason}) async =>
      calls.add('adminUpdate:${b.id}:${b.name}:$reason');

  @override
  Future<void> adminDelete(String businessId, {required String reason}) async =>
      calls.add('adminDelete:$businessId:$reason');
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

void main() {
  group('BusinessAdminScreen', () {
    testWidgets('рўйхат, қидирув ва тур бўйича фильтр; «қўшиш» тугмаси ЙЎҚ (B-1)', (tester) async {
      final repo = _FakeRepo([
        _b('1', 'Авто Мойка', BusinessCategory.auto),
        _b('2', 'Нон дўкони', BusinessCategory.retail, owner: '998902222222'),
      ]);
      await _pump(tester, BusinessAdminScreen(repository: repo));
      expect(find.text('Авто Мойка'), findsOneWidget);
      expect(find.text('Нон дўкони'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byIcon(Icons.add_business_rounded), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'нон');
      await tester.pumpAndSettle();
      expect(find.text('Авто Мойка'), findsNothing);
      expect(find.text('Нон дўкони'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '998902222222'); // эга рақами бўйича
      await tester.pumpAndSettle();
      expect(find.text('Нон дўкони'), findsOneWidget);
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

  group('MyBusinessesScreen', () {
    testWidgets('бўш рўйхат — тушунтириш матни ва «қўшиш» тугмаси', (tester) async {
      final empty = _FakeRepo([]);
      await _pump(tester, MyBusinessesScreen(repository: empty, ownerId: '998901111111'));
      expect(find.text('bizmap_my_empty'), findsOneWidget);
      expect(find.text('bizmap_add_mine'), findsOneWidget);
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
