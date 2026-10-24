// UI/UX аудит (2026-10-24), уй ошпази занжири — қолган бандлар:
//  #3 хато майдон остида (фақат SnackBar эмас), #5 категорияни таҳрирлаш йўли
//  кўринади (узоқ босиш ёлғиз эмас), #6 категория чипи ≥48 dp босиш майдони.

import 'package:ava_gurlan/core/theme/ava_tokens.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/merchant_menu_tab.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'restaurants_l10n_harness.dart';

final _l10n = JsonL10nDelegate();
String _tr(String key) => _l10n.tr(key);

class _Repo implements RestaurantsRepository {
  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) =>
      Stream.value(const [MenuCategory(id: 'c1', name: 'Osh', sort: 0)]);

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) => Stream.value(const <MenuItem>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(390 * 3, 2400 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  group('рўйхатдан ўтиш: хато майдон остида (#3)', () {
    Future<void> openAndSubmit(WidgetTester t) async {
      SharedPreferences.setMockInitialValues({});
      _tall(t);
      await t.pumpWidget(l10nApp(delegate: _l10n, home: RestaurantRegisterScreen(repository: _Repo(), homeCook: true)));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, _tr('restaurants_m_submit')));
      await t.pumpAndSettle();
    }

    testWidgets('бўш форма: ном ва манзил майдони остида ўз хатоси, жойлашув қизил', (t) async {
      await openAndSubmit(t);
      final nameField = find.widgetWithText(TextField, _tr('restaurants_m_name'));
      final addressField = find.widgetWithText(TextField, _tr('restaurants_m_address'));
      expect(find.descendant(of: nameField, matching: find.text(_tr('restaurants_m_err_name'))), findsOneWidget);
      expect(find.descendant(of: addressField, matching: find.text(_tr('restaurants_m_err_address'))), findsOneWidget);
      final loc = t.widget<Text>(find.text(_tr('restaurants_m_err_location')));
      expect(loc.style!.color, AvaLight.danger, reason: 'хато ҳолатда огоҳлантириш эмас, хато ранги');
    });

    testWidgets('тузатилган майдоннинг хатоси кетади, қолгани туради', (t) async {
      await openAndSubmit(t);
      final nameField = find.widgetWithText(TextField, _tr('restaurants_m_name'));
      await t.enterText(nameField, 'Oshxona');
      await t.pump();
      expect(find.descendant(of: nameField, matching: find.text(_tr('restaurants_m_err_name'))), findsNothing);
      final addressField = find.widgetWithText(TextField, _tr('restaurants_m_address'));
      expect(find.descendant(of: addressField, matching: find.text(_tr('restaurants_m_err_address'))), findsOneWidget);
    });

    testWidgets('юборишдан олдин хато кўрсатилмайди', (t) async {
      SharedPreferences.setMockInitialValues({});
      _tall(t);
      await t.pumpWidget(l10nApp(delegate: _l10n, home: RestaurantRegisterScreen(repository: _Repo(), homeCook: true)));
      await t.pumpAndSettle();
      expect(find.text(_tr('restaurants_m_err_name')), findsNothing);
      expect(find.text(_tr('restaurants_m_err_address')), findsNothing);
    });
  });

  group('меню: категория амаллари (#5, #6)', () {
    const rest = Restaurant(id: 'r1', name: 'Oshxona', legalType: 'individual', ownerUid: 'u1', status: 'approved');

    Future<void> open(WidgetTester t) async {
      _tall(t);
      await t.pumpWidget(l10nApp(delegate: _l10n, home: Scaffold(body: MerchantMenuTab(restaurant: rest, repository: _Repo()))));
      await t.pumpAndSettle();
    }

    testWidgets('танланган категорияда «⋯» тугмаси чиқади ва таҳрирлаш/ўчириш варағини очади', (t) async {
      await open(t);
      const actions = ValueKey('category-actions');
      expect(find.byKey(actions), findsNothing);
      await t.tap(find.text('Osh'));
      await t.pumpAndSettle();
      expect(find.byKey(actions), findsOneWidget);
      expect(t.getSize(find.byKey(actions)).height, greaterThanOrEqualTo(48));
      await t.tap(find.byKey(actions));
      await t.pumpAndSettle();
      expect(find.text(_tr('restaurants_m_rename')), findsOneWidget);
      expect(find.text(_tr('restaurants_m_delete')), findsOneWidget);
    });

    testWidgets('категория чипининг босиш майдони ≥48 dp', (t) async {
      await open(t);
      expect(t.getSize(find.widgetWithText(ChoiceChip, 'Osh')).height, greaterThanOrEqualTo(48));
    });
  });
}
