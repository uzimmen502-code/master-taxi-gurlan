import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_entry_flow.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Бир фойдаланувчи БИР НЕЧТА кафе-ресторан очади (эга, 2026-10-17; сервер
/// чегара қўймайди, D-REST-15). Аввал битта кафеда варақсиз панелга тушарди ва
/// иккинчисини очиш йўли йўқ эди.
class _FakeRepo implements RestaurantsRepository {
  _FakeRepo(this.mine);

  final List<Restaurant> mine;

  @override
  Stream<List<Restaurant>> watchMine(String ownerUid) => Stream.value(mine);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _cafe1 = Restaurant(id: 'c1', name: 'Gurlan osh', legalType: 'yatt', ownerUid: 'u1', status: 'approved');
const _cafe2 = Restaurant(id: 'c2', name: 'Plov markazi', legalType: 'llc', ownerUid: 'u1', status: 'applied');
const _home1 = Restaurant(id: 'h1', name: 'Oshxona', legalType: 'individual', ownerUid: 'u1', status: 'approved');

Future<void> _open(WidgetTester t, _FakeRepo repo, {required bool homeCook}) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => openRestaurantBusiness(
            context,
            ownerUid: 'u1',
            homeCook: homeCook,
            repository: repo,
          ),
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('кафеси йўқ — тўғридан-тўғри рўйхатдан ўтиш', (t) async {
    await _open(t, _FakeRepo(const []), homeCook: false);
    expect(find.byType(RestaurantRegisterScreen), findsOneWidget);
  });

  testWidgets('БИТТА кафе бор — варақ очилади (панелга тўғридан-тўғри эмас) ва «яна очиш» бор', (t) async {
    await _open(t, _FakeRepo(const [_cafe1]), homeCook: false);
    expect(find.text('restaurants_m_choose_cafe'), findsOneWidget);
    expect(find.text('Gurlan osh'), findsOneWidget);
    expect(find.text('restaurants_m_status_approved'), findsOneWidget);
    expect(find.text('restaurants_m_open_cafe'), findsOneWidget);
    expect(find.byType(RestaurantRegisterScreen), findsNothing);
  });

  testWidgets('«яна очиш» босилса — иккинчи кафени рўйхатдан ўтказиш экрани (кафе: homeCook=false)', (t) async {
    await _open(t, _FakeRepo(const [_cafe1]), homeCook: false);
    await t.tap(find.text('restaurants_m_open_cafe'));
    await t.pumpAndSettle();
    final screen = t.widget<RestaurantRegisterScreen>(find.byType(RestaurantRegisterScreen));
    expect(screen.homeCook, isFalse);
  });

  testWidgets('бир нечта кафе — ҳаммаси ўз ҳолати билан, яна очиш ҳам бор', (t) async {
    await _open(t, _FakeRepo(const [_cafe1, _cafe2]), homeCook: false);
    expect(find.text('Gurlan osh'), findsOneWidget);
    expect(find.text('Plov markazi'), findsOneWidget);
    expect(find.text('restaurants_m_status_approved'), findsOneWidget);
    expect(find.text('restaurants_m_status_applied'), findsOneWidget);
    expect(find.text('restaurants_m_open_cafe'), findsOneWidget);
  });

  testWidgets('кафе банди уй ошпазини КЎРСАТМАЙДИ — фақат уй ошпази бўлса янги кафе экрани', (t) async {
    await _open(t, _FakeRepo(const [_home1]), homeCook: false);
    expect(find.byType(RestaurantRegisterScreen), findsOneWidget);
    expect(find.text('Oshxona'), findsNothing);
  });

  testWidgets('уй ошпази: битта бор — варақ ва «уй ошпази бўлиш» (яна очиш), homeCook=true', (t) async {
    await _open(t, _FakeRepo(const [_home1, _cafe1]), homeCook: true);
    expect(find.text('Oshxona'), findsOneWidget);
    expect(find.text('Gurlan osh'), findsNothing);
    await t.tap(find.text('home_create_home_cook'));
    await t.pumpAndSettle();
    final screen = t.widget<RestaurantRegisterScreen>(find.byType(RestaurantRegisterScreen));
    expect(screen.homeCook, isTrue);
  });

  testWidgets('уй ошпази варағи «ресторан» эмас: ўз сарлавҳаси ва ошхона белгиси', (t) async {
    await _open(t, _FakeRepo(const [_home1]), homeCook: true);
    expect(find.text('restaurants_m_choose_home_cook'), findsOneWidget);
    expect(find.text('restaurants_m_choose_cafe'), findsNothing);
    expect(find.byIcon(Icons.soup_kitchen_rounded), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_rounded), findsNothing);
  });
}
