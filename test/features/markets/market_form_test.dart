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
  Future<Map<String, String>?> Function(String phone)? car,
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
      loadCarInfo: car,
    );

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(420 * 2, 2400 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  // UniqueKey: бир тестда қайта pump — янги State (форма майдонлари late final).
  await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: AppTheme.light, home: w));
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
          _form(_FakeShop(), open: {'electronics_market', 'appliances_market'}, load: () async => kTaxonomyV3));
      expect(find.byKey(const ValueKey('market_choice_electronics')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_choice_appliances')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_choice_meat')), findsNothing);
      await _pump(tester, _form(_FakeShop(), open: {'electronics_market'}, load: () async => kTaxonomyV3));
      expect(find.byKey(const ValueKey('market_choice_electronics')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_choice_appliances')), findsNothing);
    });

    testWidgets('бирорта бозор очиқ эмас — чиплар йўқ', (tester) async {
      await _pump(tester, _form(_FakeShop(), open: const {}));
      expect(find.byKey(const ValueKey('market_choice')), findsNothing);
    });
  });

  group('харита объекти (2026-11-16): чиплар + фаолият туридан олдиндан танлов', () {
    Business biz(BusinessCategory c, [String subtype = '']) => Business(
        id: 'b1', ownerId: '998901111111', name: 'O', category: c, subtype: subtype, phone: '1', lat: 0, lng: 0,
        districtId: 'gurlan');
    const allOpen = {
      'livestock_market', 'auto_market', 'meat_market', 'farm_market', 'electronics_market', 'appliances_market'
    };
    bool sel(WidgetTester t, String key) => t.widget<ChoiceChip>(find.byKey(ValueKey(key))).selected;

    testWidgets('мос тури йўқ (retail, бўш) — чиплар бор, Аралаш танланган', (tester) async {
      await _pump(tester, _form(_FakeShop(), business: biz(BusinessCategory.retail), open: allOpen,
          load: () async => kTaxonomyV3));
      expect(find.byKey(const ValueKey('market_choice_aralash')), findsOneWidget);
      expect(sel(tester, 'market_choice_aralash'), isTrue);
      expect(find.byKey(const ValueKey('market_choice_electronics')), findsOneWidget);
    });

    testWidgets('«Телефон» дўкони → Электроника · Телефонлар; сақланганда ёзилади', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, business: biz(BusinessCategory.retail, 'Телефоны'), open: allOpen,
          load: () async => kTaxonomyV3));
      expect(sel(tester, 'market_choice_electronics'), isTrue);
      expect(sel(tester, 'market_cat_phones'), isTrue);
      expect(sel(tester, 'market_choice_aralash'), isFalse);
      await _fillBasics(tester);
      await _save(tester);
      final c = shop.created!;
      expect((c.market, c.category, c.businessId, c.regionId, c.status), ('electronics', 'phones', 'b1', 'xorazm', 'pending'));
    });

    testWidgets('«Балиқ дўкони» → Гўшт · Балиқ; сотувчи Аралашга алмаштира олади', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, business: biz(BusinessCategory.retail, 'Балиқ дўкони'), open: allOpen,
          load: () async => kTaxonomyV3));
      expect(sel(tester, 'market_choice_meat'), isTrue);
      expect(sel(tester, 'market_cat_fish'), isTrue);
      await tester.tap(find.byKey(const ValueKey('market_choice_aralash')));
      await tester.pumpAndSettle();
      await _fillBasics(tester);
      await _save(tester);
      expect(shop.created!.market, '');
      expect(shop.created!.businessId, 'b1');
    });

    testWidgets('бозор туманда очилмаса — олдиндан танланмайди', (tester) async {
      await _pump(tester, _form(_FakeShop(), business: biz(BusinessCategory.auto, 'Автосалон'),
          open: const {'farm_market'}, load: () async => kTaxonomyV3));
      expect(find.byKey(const ValueKey('market_choice_auto')), findsNothing);
      expect(sel(tester, 'market_choice_aralash'), isTrue);
    });

    testWidgets('таҳрирда чиплар йўқ ва бозор тегилмайди', (tester) async {
      final existing = TvShopItem(
          id: 'i1', ownerPhone: '998901111111', ownerName: 'O', title: 'X', price: 1, photoUrl: '', businessId: 'b1',
          kind: 'product', districtId: 'gurlan', districtLabel: '');
      await _pump(tester, _form(_FakeShop(), business: biz(BusinessCategory.retail, 'Телефон'), existing: existing,
          open: allOpen, load: () async => kTaxonomyV3));
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
      // Ёш — «йил + ой» (эга 2026-11-19); 51 йил = 612 ой > 600.
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months_y')), '51');
      await _save(tester);
      expect(shop.created, isNull);
      expect(find.text('market_err_max'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months_y')), '2');
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
      // 24 ой → «2 йил», ой бўш.
      expect(tester.widget<TextField>(find.byKey(const ValueKey('market_field_age_months_y'))).controller!.text, '2');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('market_field_age_months_m'))).controller!.text, '');
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months_m')), '6');
      await _save(tester);
      expect(shop.patch!['attrs'], {'age_months': 30});
      expect(shop.patch!['category'], 'all');
      expect(shop.patch!.containsKey('imported'), isFalse);
      expect(find.byKey(const ValueKey('bizprod_snack_submitted')), findsOneWidget);
    });
  });

  // Эга 2026-11-19: форма ўзгаришлари (5–11, 14, 16).
  group('2026-11-19 форма', () {
    const allOpen = {
      'livestock_market', 'auto_market', 'meat_market', 'farm_market', 'electronics_market', 'appliances_market'
    };
    TextField tf(WidgetTester t, String key) => t.widget<TextField>(find.byKey(ValueKey(key)));

    testWidgets('Мол: «Номи» изоҳи (чип эмас); бошқа бозорда изоҳ йўқ', (tester) async {
      await _pump(tester, _form(_FakeShop(), market: 'livestock'));
      expect(tf(tester, 'bizprod_name').decoration!.hintText, 'market_livestock_name_hint');
      await _pump(tester, _form(_FakeShop(), market: 'farm', category: 'fruits'));
      expect(tf(tester, 'bizprod_name').decoration!.hintText, isNull);
    });

    testWidgets('Мол: ёш «йил + ой» → attrs.age_months (1 йил 7 ой = 19); ой 12 қабул қилинмайди, 11 — чегара',
        (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, market: 'livestock'));
      expect(find.text('market_age_label'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months_m')), '12');
      expect(tf(tester, 'market_field_age_months_m').controller!.text, '', reason: '0–11');
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months_m')), '11');
      expect(tf(tester, 'market_field_age_months_m').controller!.text, '11');
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months_y')), '1');
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months_m')), '7');
      await _fillBasics(tester);
      await _save(tester);
      expect(shop.created!.attrs['age_months'], 19);
    });

    testWidgets('Мол: ёш бўш — attrs да йўқ; фақат ой «0» — 0', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, market: 'livestock'));
      await _fillBasics(tester);
      await _save(tester);
      expect(shop.created!.attrs.containsKey('age_months'), isFalse);
      final shop2 = _FakeShop();
      await _pump(tester, _form(shop2, market: 'livestock'));
      await tester.enterText(find.byKey(const ValueKey('market_field_age_months_m')), '0');
      await _fillBasics(tester);
      await _save(tester);
      expect(shop2.created!.attrs['age_months'], 0);
    });

    testWidgets('«Тахминий вазн» Мол/Гўшт/Деҳқонда йўқ; Электроника ва Аралашда бор', (tester) async {
      for (final m in ['livestock', 'meat', 'farm']) {
        await _pump(tester, _form(_FakeShop(), market: m, load: () async => kTaxonomyV5));
        expect(find.byKey(const ValueKey('bizprod_weight')), findsNothing, reason: m);
      }
      await _pump(tester, _form(_FakeShop(), market: 'electronics', category: 'phones', load: () async => kTaxonomyV5));
      expect(find.byKey(const ValueKey('bizprod_weight')), findsOneWidget);
      await _pump(tester, _form(_FakeShop()));
      expect(find.byKey(const ValueKey('bizprod_weight')), findsOneWidget);
    });

    testWidgets('Гўшт: аввал ёзилган вазн киритилган бўлса ҳам ёзилмайди (майдон яширин)', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop));
      await tester.enterText(find.byKey(const ValueKey('bizprod_weight')), '1,5');
      await tester.tap(find.byKey(const ValueKey('market_choice_meat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('market_cat_beef')));
      await tester.pumpAndSettle();
      await _fillBasics(tester);
      await _save(tester);
      expect(shop.created!.unitWeightG, isNull);
    });

    testWidgets('таҳрир (Гўшт): эски unitWeightG тегилмайди (ўчирилмайди)', (tester) async {
      final shop = _FakeShop();
      const existing = TvShopItem(
          id: 'g1', ownerPhone: '998901111111', ownerName: 'x', title: 'Гўшт', price: 85000, photoUrl: 'u',
          kind: 'product', districtId: 'gurlan', districtLabel: '', status: 'active', market: 'meat',
          category: 'beef', unitWeightG: 1500);
      await _pump(tester, _form(shop, existing: existing));
      await _save(tester);
      expect(shop.patch!.containsKey('unitWeightG'), isFalse);
    });

    testWidgets('«Бўлим» сарлавҳаси йўқ, чиплар бор; хато матни қолади', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, market: 'meat'));
      expect(find.text('market_category'), findsNothing);
      expect(find.byKey(const ValueKey('market_category')), findsOneWidget);
      await _fillBasics(tester);
      await _save(tester);
      expect(find.text('market_err_category'), findsOneWidget);
    });

    testWidgets('чиплар ихчам: compact + shrinkWrap, Wrap 6/4', (tester) async {
      await _pump(tester, _form(_FakeShop(), open: allOpen, load: () async => kTaxonomyV5));
      await tester.tap(find.byKey(const ValueKey('market_choice_farm')));
      await tester.pumpAndSettle();
      for (final k in ['market_choice_farm', 'market_cat_fruits', 'bizprod_unit_kg']) {
        final chip = tester.widget<ChoiceChip>(find.byKey(ValueKey(k)));
        expect(chip.visualDensity, VisualDensity.compact, reason: k);
        expect(chip.materialTapTargetSize, MaterialTapTargetSize.shrinkWrap, reason: k);
      }
      for (final k in ['market_choice', 'market_category', 'bizprod_unit']) {
        final w = tester.widget<Wrap>(find.byKey(ValueKey(k)));
        expect((w.spacing, w.runSpacing), (6.0, 4.0), reason: k);
      }
    });

    testWidgets('Мошина (v5): бўлим номлари таксономиядан («Авто», «Махсус техникалар»)', (tester) async {
      await _pump(tester, _form(_FakeShop(), market: 'auto', category: 'cars', load: () async => kTaxonomyV5));
      expect(find.text('Авто'), findsOneWidget);
      expect(find.text('Махсус техникалар'), findsOneWidget);
      expect(find.text('Мошиналар'), findsNothing);
    });

    testWidgets('Мошина · Авто: «Номи» йўқ, марка/модель тепада (нархдан олдин); сарлавҳа «марка модель йил»',
        (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, market: 'auto', category: 'cars', load: () async => kTaxonomyV5));
      expect(find.byKey(const ValueKey('bizprod_name')), findsNothing);
      final priceY = tester.getTopLeft(find.byKey(const ValueKey('bizprod_price'))).dy;
      expect(tester.getTopLeft(find.byKey(const ValueKey('market_field_brand'))).dy, lessThan(priceY));
      expect(tester.getTopLeft(find.byKey(const ValueKey('market_field_model'))).dy, lessThan(priceY));
      expect(find.byKey(const ValueKey('market_field_brand')), findsOneWidget, reason: 'пастда такрорланмайди');
      await tester.enterText(find.byKey(const ValueKey('market_field_brand')), ' Chevrolet ');
      await tester.enterText(find.byKey(const ValueKey('market_field_model')), 'Cobalt');
      await tester.enterText(find.byKey(const ValueKey('market_field_year')), '2021');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '120000000');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await _save(tester);
      final c = shop.created!;
      expect(c.title, 'Chevrolet Cobalt 2021');
      expect(c.attrs, {'brand': 'Chevrolet', 'model': 'Cobalt', 'year': 2021});
    });

    testWidgets('Мошина: марка+модель < 2 белги — хато, ёзилмайди; 2 белги (чегара) — ўтади', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, market: 'auto', category: 'moto', load: () async => kTaxonomyV5));
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '1000');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(shop.created, isNull);
      expect(find.text('market_err_brand_model'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('market_field_brand')), 'A');
      await _save(tester);
      expect(shop.created, isNull);
      await tester.enterText(find.byKey(const ValueKey('market_field_model')), 'B');
      await _save(tester);
      expect(shop.created!.title, 'A B');
    });

    testWidgets('Мошина · Эҳтиёт қисмлар — «Номи» қолади', (tester) async {
      await _pump(tester, _form(_FakeShop(), market: 'auto', category: 'parts', load: () async => kTaxonomyV5));
      expect(find.byKey(const ValueKey('bizprod_name')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_car_choice')), findsNothing);
    });

    testWidgets('таҳрир (Мошина): attrs да марка бор — «Номи» йўқ; бўлмаса «Номи» ва марка пастда', (tester) async {
      const base = TvShopItem(
          id: 'c1', ownerPhone: '998901111111', ownerName: 'x', title: 'Эски ном', price: 1, photoUrl: 'u',
          kind: 'product', districtId: 'gurlan', districtLabel: '', status: 'active', market: 'auto', category: 'cars',
          attrs: {'brand': 'Lada', 'model': 'Niva'});
      final shop = _FakeShop();
      await _pump(tester, _form(shop, existing: base, load: () async => kTaxonomyV5));
      expect(find.byKey(const ValueKey('bizprod_name')), findsNothing);
      expect(tf(tester, 'market_field_brand').controller!.text, 'Lada');
      expect(find.byKey(const ValueKey('market_car_choice')), findsNothing, reason: 'таҳрирда йўқ');
      await _save(tester);
      expect(shop.patch!['title'], 'Lada Niva');

      const legacy = TvShopItem(
          id: 'c2', ownerPhone: '998901111111', ownerName: 'x', title: 'Эски ном', price: 1, photoUrl: 'u',
          kind: 'product', districtId: 'gurlan', districtLabel: '', status: 'active', market: 'auto', category: 'cars');
      await _pump(tester, _form(_FakeShop(), existing: legacy, load: () async => kTaxonomyV5));
      expect(find.byKey(const ValueKey('bizprod_name')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_field_brand')), findsOneWidget);
    });

    testWidgets('v4 шакли (model йўқ): фақат марка тепада, сарлавҳа маркадан', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, market: 'auto', category: 'cars'));
      expect(find.byKey(const ValueKey('bizprod_name')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('market_field_brand')), 'Nexia');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '1000');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(shop.created!.title, 'Nexia');
    });

    testWidgets('«Ўз автомобилим»: профилдан марка/модель/йил/ёқилғи (cng → methane)', (tester) async {
      final shop = _FakeShop();
      String? askedFor;
      await _pump(
          tester,
          _form(shop, market: 'auto', category: 'cars', load: () async => kTaxonomyV5, car: (p) async {
            askedFor = p;
            return {'carBrand': 'Chevrolet', 'carModel': 'Cobalt', 'carYear': '2021', 'carFuelType': 'cng'};
          }));
      expect(find.byKey(const ValueKey('market_car_own')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_car_other')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('market_car_own')));
      await tester.pumpAndSettle();
      expect(askedFor, '998901111111');
      expect(tf(tester, 'market_field_brand').controller!.text, 'Chevrolet');
      expect(tf(tester, 'market_field_model').controller!.text, 'Cobalt');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '1000');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await _save(tester);
      final c = shop.created!;
      expect(c.title, 'Chevrolet Cobalt 2021');
      expect(c.attrs, {'brand': 'Chevrolet', 'model': 'Cobalt', 'year': 2021, 'fuel': 'methane'});
    });

    testWidgets('«Ўз автомобилим»: профилда автомобиль йўқ — изоҳ; «Бошқа» — тозаланади', (tester) async {
      await _pump(tester,
          _form(_FakeShop(), market: 'auto', category: 'cars', load: () async => kTaxonomyV5, car: (_) async => null));
      await tester.tap(find.byKey(const ValueKey('market_car_own')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('market_car_none')), findsOneWidget);

      await _pump(tester, _form(_FakeShop(), market: 'auto', category: 'cars', load: () async => kTaxonomyV5,
          car: (_) async => {'carBrand': 'Kia', 'carModel': 'K5'}));
      await tester.tap(find.byKey(const ValueKey('market_car_own')));
      await tester.pumpAndSettle();
      expect(tf(tester, 'market_field_brand').controller!.text, 'Kia');
      await tester.tap(find.byKey(const ValueKey('market_car_other')));
      await tester.pumpAndSettle();
      expect(tf(tester, 'market_field_brand').controller!.text, '');
      expect(find.byKey(const ValueKey('market_car_none')), findsNothing);
    });

    testWidgets('«Ўз/Бошқа автомобил» фақат «Авто» бўлимида (Мото/Техникада йўқ)', (tester) async {
      await _pump(tester, _form(_FakeShop(), market: 'auto', category: 'moto', load: () async => kTaxonomyV5));
      expect(find.byKey(const ValueKey('market_car_choice')), findsNothing);
      await _pump(tester, _form(_FakeShop(), market: 'auto', category: 'tech', load: () async => kTaxonomyV5));
      expect(find.byKey(const ValueKey('market_car_choice')), findsNothing);
    });

    testWidgets('Электроника (v5): каробка ўлчамлари бир қаторда; қисман — хато; учаласи — attrs', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, _form(shop, market: 'electronics', category: 'phones', load: () async => kTaxonomyV5));
      expect(find.byKey(const ValueKey('market_box_dims')), findsOneWidget);
      final y = tester.getTopLeft(find.byKey(const ValueKey('market_field_box_w_cm'))).dy;
      expect(tester.getTopLeft(find.byKey(const ValueKey('market_field_box_l_cm'))).dy, y);
      expect(tester.getTopLeft(find.byKey(const ValueKey('market_field_box_h_cm'))).dy, y);
      await _fillBasics(tester);
      await tester.enterText(find.byKey(const ValueKey('market_field_box_w_cm')), '40');
      await _save(tester);
      expect(shop.created, isNull);
      expect(find.text('market_err_box_all'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('market_field_box_l_cm')), '30');
      await tester.enterText(find.byKey(const ValueKey('market_field_box_h_cm')), '1001');
      await _save(tester);
      expect(shop.created, isNull, reason: '1..1000');
      await tester.enterText(find.byKey(const ValueKey('market_field_box_h_cm')), '1000');
      await _save(tester);
      expect(shop.created!.attrs, {'box_w_cm': 40, 'box_l_cm': 30, 'box_h_cm': 1000});
    });

    testWidgets('Маиший техника v3 (каробка майдони йўқ) — қатор кўрсатилмайди', (tester) async {
      await _pump(tester, _form(_FakeShop(), market: 'appliances', category: 'fridges', load: () async => kTaxonomyV3));
      expect(find.byKey(const ValueKey('market_box_dims')), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_weight')), findsOneWidget);
    });

    testWidgets('расм ва видео — бир қаторда (ихчам); видео танланса сақлангач TvPublish занжири', (tester) async {
      var videoFor = '';
      final shop = _FakeShop();
      await _pump(
        tester,
        BusinessProductFormScreen(
          business: _own,
          repository: shop,
          ownerPhone: '998901111111',
          initialMarket: 'farm',
          initialCategory: 'fruits',
          loadTaxonomy: () async => kTaxonomyV5,
          isModuleOpenable: allOpen.contains,
          resolveRegionId: (_) async => 'xorazm',
          pickPhotos: (_) async => ['/tmp/a.jpg'],
          uploadPhotos: (_, __) async => ['https://x/a.jpg'],
          addVideo: (_, id) async => videoFor = id,
        ),
      );
      final photoY = tester.getTopLeft(find.byKey(const ValueKey('bizprod_add_photos'))).dy;
      expect(tester.getTopLeft(find.byKey(const ValueKey('bizprod_video_tile'))).dy, photoY);
      expect(tester.getSize(find.byKey(const ValueKey('bizprod_video_tile'))).height, lessThan(84));
      await _fillBasics(tester);
      await tester.tap(find.byKey(const ValueKey('bizprod_video_tile')));
      await tester.pump();
      await _save(tester);
      expect(videoFor, 'item1');
    });
  });
}
