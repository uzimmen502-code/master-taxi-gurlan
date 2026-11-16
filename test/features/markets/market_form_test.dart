// «Бозорлар» 5-босқич: ягона форма — «Қаерда сотасиз?» чиплари (модул дарвозаси), бозордан prefill,
// Гўштда кг мажбурий + «Импорт», динамик майдонлар текшируви ва ёзиладиган майдонлар.
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/screens/business_product_form_screen.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'taxonomy_fixture.dart';

class _FakeShop implements TvShopRepository {
  TvShopItem? created;
  Map<String, dynamic>? patch;

  @override
  Future<void> ensureShop({required String ownerPhone, required String name}) async {}

  @override
  Future<String> createItem(TvShopItem item) async {
    created = item;
    return 'item1';
  }

  @override
  Future<void> updateItem(String itemId, Map<String, dynamic> p) async => patch = p;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final _own = Business.ownShop(ownerId: '998901111111', name: 'Дўкон', districtId: 'gurlan');

Widget _form(
  _FakeShop shop, {
  Business? business,
  String? market,
  String? category,
  Set<String> open = const {'livestock_market', 'auto_market', 'meat_market', 'farm_market'},
  TvShopItem? existing,
  Future<MarketTaxonomy> Function()? load,
}) =>
    BusinessProductFormScreen(
      business: business ?? _own,
      existing: existing,
      repository: shop,
      ownerPhone: '998901111111',
      initialMarket: market,
      initialCategory: category,
      loadTaxonomy: load ?? () async => kTaxonomyV1,
      isModuleOpenable: open.contains,
      resolveRegionId: (d) async => d == 'gurlan' ? 'xorazm' : '',
      pickPhotos: (_) async => ['/tmp/a.jpg'],
      uploadPhotos: (_, __) async => ['https://x/a.jpg'],
    );

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(420 * 2, 2400 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: w));
  await tester.pumpAndSettle();
}

Future<void> _fillBasics(WidgetTester tester, {String price = '85000'}) async {
  await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Эълон');
  await tester.enterText(find.byKey(const ValueKey('bizprod_price')), price);
  await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('bizprod_save')));
  await tester.tap(find.byKey(const ValueKey('bizprod_save')));
  await tester.pumpAndSettle();
}

void main() {
  group('«Қаерда сотасиз?» чиплари', () {
    testWidgets('ўз дўкони, янги: Аралаш танланган + фақат очиладиган бозорлар', (tester) async {
      await _pump(tester, _form(_FakeShop(), open: {'meat_market', 'farm_market'}));
      expect(find.byKey(const ValueKey('market_choice_aralash')), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('market_choice_aralash'))).selected, isTrue);
      expect(find.byKey(const ValueKey('market_choice_meat')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_choice_farm')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_choice_livestock')), findsNothing);
      expect(find.byKey(const ValueKey('market_choice_auto')), findsNothing);
    });

    testWidgets('v2: Электроника ва Маиший техника чиплари — фақат модули очиқ бўлса', (tester) async {
      await _pump(tester,
          _form(_FakeShop(), open: {'electronics_market', 'appliances_market'}, load: () async => kTaxonomyV2));
      expect(find.byKey(const ValueKey('market_choice_electronics')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_choice_appliances')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_choice_meat')), findsNothing);
      await _pump(tester, _form(_FakeShop(), open: {'electronics_market'}, load: () async => kTaxonomyV2));
      expect(find.byKey(const ValueKey('market_choice_electronics')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_choice_appliances')), findsNothing);
    });

    testWidgets('бирорта бозор очиқ эмас — чиплар йўқ; харита объекти — чиплар йўқ', (tester) async {
      await _pump(tester, _form(_FakeShop(), open: const {}));
      expect(find.byKey(const ValueKey('market_choice')), findsNothing);
      final biz = Business(
          id: 'b1', ownerId: '998901111111', name: 'O', category: BusinessCategory.retail, phone: '1', lat: 0, lng: 0);
      await _pump(tester, _form(_FakeShop(), business: biz));
      expect(find.byKey(const ValueKey('market_choice')), findsNothing);
    });

    testWidgets('Аралаш сақлаш — бозор майдонлари ёзилмайди (аввалги шакл)', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop));
      await _fillBasics(tester);
      await _save(tester);
      final c = shop.created!;
      expect(c.market, '');
      expect(c.toMap().containsKey('market'), isFalse);
      expect(c.toMap().containsKey('regionId'), isFalse);
      expect(c.status, 'pending');
    });

    testWidgets('таксономия юкланмаса — хато ва «Қайта»; Аралаш формаси ишлайди', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, load: () async => throw StateError('offline')));
      expect(find.byKey(const ValueKey('market_tax_retry')), findsOneWidget);
      await _fillBasics(tester);
      await _save(tester);
      expect(shop.created, isNotNull);
    });
  });

  group('бозор танланганда', () {
    testWidgets('бозор ичидаги «+»: бозор ва бўлим олдиндан, бозор чиплари йўқ', (tester) async {
      await _pump(tester, _form(_FakeShop(), market: 'farm', category: 'fruits'));
      expect(find.byKey(const ValueKey('market_choice')), findsNothing);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('market_cat_fruits'))).selected, isTrue);
      // Деҳқон бирликлари: кг / тонна / дона.
      expect(find.byKey(const ValueKey('bizprod_unit_kg')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_unit_ton')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_unit_piece')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_unit_fixed')), findsNothing);
      expect(find.byKey(const ValueKey('market_field_harvest_date')), findsOneWidget);
    });

    testWidgets('Гўшт: бирлик кг мажбурий (танлов йўқ), «Импорт», бўлим шарт; ёзиладиган майдонлар', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop));
      await tester.tap(find.byKey(const ValueKey('market_choice_meat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bizprod_unit')), findsNothing);
      expect(find.text('bizprod_f_price'), findsOneWidget);
      await _fillBasics(tester);
      await _save(tester);
      expect(shop.created, isNull);
      expect(find.text('market_err_category'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('market_cat_beef')));
      await tester.tap(find.byKey(const ValueKey('market_imported')));
      await tester.pumpAndSettle();
      await _save(tester);
      final c = shop.created!;
      expect(c.market, 'meat');
      expect(c.category, 'beef');
      expect(c.priceUnit, PriceUnit.kg);
      expect(c.price, 85000);
      expect(c.imported, isTrue);
      expect(c.regionId, 'xorazm');
      expect(c.taxonomyVersion, 1);
      expect(c.attrs, isEmpty);
      expect(c.toMap()['priceUnit'], 'kg');
    });

    testWidgets('Мол: бўлим `all` ўзи, чиплар йўқ; майдон min/max текшируви ва турли attrs', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, market: 'livestock'));
      expect(find.byKey(const ValueKey('market_category')), findsNothing);
      expect(find.byKey(const ValueKey('market_imported')), findsNothing);
      await _fillBasics(tester, price: '9000000');
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months')), '700');
      await _save(tester);
      expect(shop.created, isNull);
      expect(find.text('market_err_max'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months')), '24');
      await tester.enterText(find.byKey(const ValueKey('market_field_breed')), 'Ҳисори');
      await tester.ensureVisible(find.byKey(const ValueKey('market_field_pregnant')));
      await tester.tap(find.byKey(const ValueKey('market_field_pregnant')));
      await tester.pumpAndSettle();
      await _save(tester);
      final c = shop.created!;
      expect(c.category, 'all');
      expect(c.attrs, {'breed': 'Ҳисори', 'age_months': 24, 'pregnant': true});
      expect(c.imported, isNull);
      expect(c.priceUnit, PriceUnit.fixed);
    });

    testWidgets('Мошина: майдонлар бўлимга қараб алмашади', (tester) async {
      await _pump(tester, _form(_FakeShop(), market: 'auto', category: 'cars'));
      expect(find.byKey(const ValueKey('market_field_brand')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_field_fits_car')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('market_cat_parts')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('market_field_brand')), findsNothing);
      expect(find.byKey(const ValueKey('market_field_fits_car')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_field_condition')), findsOneWidget);
    });

    testWidgets('таҳрир: attrs тикланади, ўзгарса текширувга (submitted) ва patch', (tester) async {
      final shop = _FakeShop();
      const existing = TvShopItem(
        id: 'm1',
        ownerPhone: '998901111111',
        ownerName: 'x',
        title: 'Сигир',
        price: 9000000,
        photoUrl: 'u',
        kind: 'product',
        districtId: 'gurlan',
        districtLabel: 'Гурлан',
        status: 'active',
        market: 'livestock',
        category: 'all',
        attrs: {'age_months': 24},
      );
      tester.view.physicalSize = const Size(420 * 2, 2400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.of(c).push(MaterialPageRoute<bool>(builder: (_) => _form(shop, existing: existing))),
            child: const Text('go'),
          ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('market_choice')), findsNothing);
      expect(find.widgetWithText(TextField, '24'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months')), '30');
      await _save(tester);
      expect(shop.patch!['attrs'], {'age_months': 30});
      expect(shop.patch!['category'], 'all');
      expect(shop.patch!.containsKey('imported'), isFalse);
      expect(find.byKey(const ValueKey('bizprod_snack_submitted')), findsOneWidget);
    });
  });
}
