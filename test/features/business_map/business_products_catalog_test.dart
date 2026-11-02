import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_type_profile.dart';
import 'package:ava_gurlan/features/business_map/screens/business_product_form_screen.dart';
import 'package:ava_gurlan/features/business_map/screens/business_products_screen.dart';
import 'package:ava_gurlan/features/my_shop/widgets/shop_link_sheet.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// S5 (2026-11-03): эга каталог экрани — сарлавҳа/бўш ҳолат тур профилидан, «Тез бошлаш» шаблон чиплари,
/// «Мижоз кўзи билан» ва «Ҳавола ва QR». Дўкон ва асосий дўкон — аввалгидек.
class _FakeShop implements TvShopRepository {
  _FakeShop([List<TvShopItem>? items]) : items = items ?? [];

  final List<TvShopItem> items;

  @override
  Future<List<TvShopItem>> fetchByBusiness(
    String businessId, {
    String ownerPhone = '',
    bool onlyActive = true,
    int limit = 200,
  }) async =>
      TvShopRepository.visibleBusinessItems(items, ownerPhone: ownerPhone, onlyActive: onlyActive);

  @override
  Future<List<TvShopItem>> fetchOwnShopItems(String ownerPhone, {bool onlyActive = false}) async => items;

  @override
  Future<TvShop?> fetchShop(String ownerPhone) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

const _owner = '998901111111';

Business _biz(BusinessCategory c, {String subtype = '', String status = 'active'}) => Business(
      id: 'b1',
      ownerId: _owner,
      name: 'Объект',
      category: c,
      subtype: subtype,
      phone: '998901234567',
      lat: 41.3,
      lng: 69.2,
      districtId: 'gurlan',
      status: status,
    );

TvShopItem _item(String id) => TvShopItem(
      id: id,
      ownerPhone: _owner,
      ownerName: 'x',
      title: 'Т $id',
      price: 1000,
      photoUrl: 'https://x/$id.jpg',
      photoUrls: ['https://x/$id.jpg'],
      kind: 'service',
      districtId: 'gurlan',
      districtLabel: '',
      status: 'active',
      businessId: 'b1',
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420 * 2, 900 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

/// Тест муҳитида l10n делегати йўқ — `tr` калитнинг ўзини қайтаради.
String _title(String key) => '$key · Объект';

void main() {
  group('сарлавҳа ва бўш ҳолат — тур профилидан', () {
    final cases = <String, (BusinessCategory, String, String)>{
      'хизмат (сартарош)': (BusinessCategory.personal, 'biz_catalog_services', 'biz_empty_services'),
      'маҳсулот (ишлаб чиқариш)': (BusinessCategory.manufacturing, 'bizprod_title_products', 'bizprod_empty'),
      'аралаш (бошқа)': (BusinessCategory.other, 'bizprod_title', 'biz_empty_mixed'),
      'аралаш (ташқи савдо)': (BusinessCategory.foreignTrade, 'bizprod_title', 'biz_empty_mixed'),
    };
    for (final e in cases.entries) {
      testWidgets(e.key, (tester) async {
        final (cat, titleKey, emptyKey) = e.value;
        final p = BusinessTypeProfile.of(cat);
        expect(p.catalogTitleKey, titleKey, reason: 'профил — ягона манба');
        await _pump(tester, BusinessProductsScreen(business: _biz(cat), repository: _FakeShop()));
        expect(find.text(_title(titleKey)), findsOneWidget);
        expect(find.text(emptyKey), findsOneWidget);
        expect(find.byKey(const ValueKey('bizprod_templates')), findsOneWidget);
        for (final t in p.templateTitles('uz_Cyrl')) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.byKey(const ValueKey('bizprod_fab')), findsOneWidget);
      });
    }

    testWidgets('аниқроқ тур профилни ўзгартиради: auto + «Шина савдоси» — маҳсулот', (tester) async {
      await _pump(tester,
          BusinessProductsScreen(business: _biz(BusinessCategory.auto, subtype: 'Шина савдоси'), repository: _FakeShop()));
      expect(find.text(_title('bizprod_title_products')), findsOneWidget);
      expect(find.text('Аккумулятор'), findsOneWidget, reason: 'эҳтиёт қисм шаблонлари');
    });

    testWidgets('таклиф бор — шаблонлар чиқмайди, рўйхат кўринади', (tester) async {
      await _pump(tester, BusinessProductsScreen(business: _biz(BusinessCategory.personal), repository: _FakeShop([_item('a')])));
      expect(find.text('Т a'), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_templates')), findsNothing);
      expect(find.text(_title('biz_catalog_services')), findsOneWidget);
    });

    testWidgets('блокланган объект — шаблонлар ва «қўшиш» йўқ (rules ҳам рад этади)', (tester) async {
      await _pump(tester,
          BusinessProductsScreen(business: _biz(BusinessCategory.personal, status: 'blocked'), repository: _FakeShop()));
      expect(find.byKey(const ValueKey('bizprod_blocked_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_templates')), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_fab')), findsNothing);
      expect(find.text('biz_empty_services'), findsOneWidget);
    });

    testWidgets('овқатланиш объекти: менюни ресторан бўлимида — шаблон чиплари йўқ', (tester) async {
      await _pump(tester, BusinessProductsScreen(business: _biz(BusinessCategory.food), repository: _FakeShop()));
      expect(find.text(_title('restaurants_m_tab_menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_templates')), findsNothing);
    });
  });

  group('шаблон чипи → форма олдиндан тўлдирилган', () {
    testWidgets('hook: ном (uz_Cyrl), тур ва нарх бирлиги узатилади', (tester) async {
      Business? gotBiz;
      TvShopItem? gotExisting;
      BusinessOfferPrefill? got;
      await _pump(
        tester,
        BusinessProductsScreen(
          business: _biz(BusinessCategory.personal),
          repository: _FakeShop(),
          formScreen: (b, existing, prefill) {
            gotBiz = b;
            gotExisting = existing;
            got = prefill;
            return const Scaffold(body: Text('FORM'));
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bizprod_tpl_0')));
      await tester.pumpAndSettle();
      expect(find.text('FORM'), findsOneWidget);
      expect(gotBiz?.id, 'b1');
      expect(gotExisting, isNull);
      expect(got, (title: 'Соч олиш', kind: 'service', priceUnitWire: PriceUnit.from.wire));
    });

    testWidgets('«қўшиш» тугмаси — prefill йўқ', (tester) async {
      var called = false;
      BusinessOfferPrefill? got = (title: 'x', kind: 'x', priceUnitWire: 'x');
      await _pump(
        tester,
        BusinessProductsScreen(
          business: _biz(BusinessCategory.personal),
          repository: _FakeShop(),
          formScreen: (b, existing, prefill) {
            called = true;
            got = prefill;
            return const Scaffold(body: Text('FORM'));
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bizprod_fab')));
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(got, isNull);
    });

    testWidgets('ҳақиқий форма: ном майдони тўлдирилган, тур — шаблондаги', (tester) async {
      // ташқи савдо: бошланғич тур — product; биринчи шаблон — хизмат.
      await _pump(tester, BusinessProductsScreen(business: _biz(BusinessCategory.foreignTrade), repository: _FakeShop()));
      await tester.tap(find.byKey(const ValueKey('bizprod_tpl_0')));
      await tester.pumpAndSettle();
      expect(find.byType(BusinessProductFormScreen), findsOneWidget);
      final name = tester.widget<TextField>(find.byKey(const ValueKey('bizprod_name')));
      expect(name.controller!.text, 'Хитойдан юк келтириш');
      final seg = tester.widget<SegmentedButton<String>>(find.byKey(const ValueKey('bizprod_kind')));
      expect(seg.selected, {'service'});
      final form = tester.widget<BusinessProductFormScreen>(find.byType(BusinessProductFormScreen));
      expect(form.initialOffer?.priceUnitWire, 'kg');
    });

    testWidgets('форма: initialOffer дўконда турни ўзгартирмайди, таҳрирда номни ўзгартирмайди', (tester) async {
      await _pump(
        tester,
        BusinessProductFormScreen(
          business: _biz(BusinessCategory.retail),
          repository: _FakeShop(),
          ownerPhone: _owner,
          initialOffer: (title: 'Шакар 1 кг', kind: 'service', priceUnitWire: ''),
        ),
      );
      expect(find.byKey(const ValueKey('bizprod_kind')), findsNothing, reason: 'дўконда фақат маҳсулот');
      expect(find.text('Шакар 1 кг'), findsOneWidget);

      await _pump(
        tester,
        BusinessProductFormScreen(
          key: UniqueKey(),
          business: _biz(BusinessCategory.personal),
          existing: _item('e1'),
          repository: _FakeShop(),
          ownerPhone: _owner,
          initialOffer: (title: 'Соч олиш', kind: 'service', priceUnitWire: 'from'),
        ),
      );
      expect(find.text('Т e1'), findsOneWidget);
      expect(find.text('Соч олиш'), findsNothing);
    });
  });

  group('AppBar: «Мижоз кўзи билан» ва «Ҳавола ва QR»', () {
    testWidgets('мижоз кўзи — шу объект билан очилади', (tester) async {
      Business? viewed;
      await _pump(
        tester,
        BusinessProductsScreen(
          business: _biz(BusinessCategory.personal),
          repository: _FakeShop(),
          customerViewScreen: (b) {
            viewed = b;
            return const Scaffold(body: Text('PUBLIC'));
          },
        ),
      );
      expect(find.byTooltip('biz_customer_view'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bizprod_customer_view')));
      await tester.pumpAndSettle();
      expect(find.text('PUBLIC'), findsOneWidget);
      expect(viewed?.id, 'b1');
      expect(viewed?.ownerId, _owner);
    });

    testWidgets('ҳавола ва QR — мавжуд варақ, businessId билан', (tester) async {
      final asked = <String>[];
      await _pump(
        tester,
        BusinessProductsScreen(
          business: _biz(BusinessCategory.personal),
          repository: _FakeShop(),
          loadLink: ({String businessId = ''}) async {
            asked.add(businessId);
            return 'https://ava.example/s/abc';
          },
        ),
      );
      expect(find.byTooltip('biz_link_qr'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bizprod_link_qr')));
      await tester.pumpAndSettle();
      expect(find.byType(ShopLinkSheet), findsOneWidget);
      expect(asked, ['b1']);
    });
  });

  group('дўкон ва асосий дўкон — ўзгармаган', () {
    testWidgets('чакана: «Маҳсулотлар», bizprod_empty, шаблон ва AppBar тугмалари йўқ', (tester) async {
      await _pump(tester, BusinessProductsScreen(business: _biz(BusinessCategory.retail), repository: _FakeShop()));
      expect(find.text(_title('bizprod_title_products')), findsOneWidget);
      expect(find.text('bizprod_empty'), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_templates')), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_customer_view')), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_link_qr')), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_fab')), findsOneWidget);
    });

    testWidgets('асосий дўкон: сарлавҳа — дўкон номи; шаблон ва тугмалар йўқ', (tester) async {
      await _pump(tester,
          BusinessProductsScreen(business: Business.ownShop(ownerId: _owner, name: 'Менинг'), repository: _FakeShop()));
      expect(find.text('Менинг'), findsOneWidget);
      expect(find.text('bizprod_empty'), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_templates')), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_customer_view')), findsNothing);
    });

    testWidgets('embedded: AppBar йўқ (тугмалар ҳам), бўш ҳолат профилдан', (tester) async {
      await _pump(tester,
          BusinessProductsScreen(business: _biz(BusinessCategory.personal), repository: _FakeShop(), embedded: true));
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_customer_view')), findsNothing);
      expect(find.text('biz_empty_services'), findsOneWidget);
    });
  });
}
