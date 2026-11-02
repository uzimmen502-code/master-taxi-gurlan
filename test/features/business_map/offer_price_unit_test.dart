// S2 (2026-11-03): таклиф нарх бирлиги — модел, форма ва карточка/варақдаги кўриниш.

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_pin.dart';
import 'package:ava_gurlan/features/business_map/domain/business_type_profile.dart';
import 'package:ava_gurlan/features/business_map/screens/business_product_form_screen.dart';
import 'package:ava_gurlan/features/business_map/screens/business_products_screen.dart';
import 'package:ava_gurlan/features/business_map/widgets/business_detail_sheet.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_shop_item_card.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_shop_item_grid_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Тест учун минимал ҳужжат (fake_cloud_firestore лойиҳада йўқ).
// ignore: subtype_of_sealed_class
class _Doc implements DocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic> _data;
  @override
  Map<String, dynamic>? data() => _data;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeShop implements TvShopRepository {
  _FakeShop([List<TvShopItem>? items]) : items = items ?? [];
  List<TvShopItem> items;
  TvShopItem? created;
  Map<String, dynamic>? patch;

  @override
  Future<List<TvShopItem>> fetchByBusiness(String businessId,
          {String ownerPhone = '', bool onlyActive = true, int limit = 200}) async =>
      TvShopRepository.visibleBusinessItems(items, ownerPhone: ownerPhone, onlyActive: onlyActive);

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

Business _biz(BusinessCategory c) => Business(
      id: 'b1',
      ownerId: '998901111111',
      name: 'Объект',
      category: c,
      phone: '998901234567',
      lat: 41.3,
      lng: 69.2,
      districtId: 'gurlan',
    );

TvShopItem _item(String id, {int price = 0, PriceUnit unit = PriceUnit.fixed, String title = 'Товар'}) => TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'x',
      title: title,
      price: price,
      photoUrl: 'https://x/$id.jpg',
      photoUrls: ['https://x/$id.jpg'],
      kind: 'service',
      districtId: 'gurlan',
      districtLabel: '',
      businessId: 'b1',
      priceUnit: unit,
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420 * 2, 1400 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

/// Виджет тестларида `context.tr` калитнинг ўзини қайтаради.
String _key(String k) => k;

void main() {
  group('TvShopItem.priceUnit — модел', () {
    test('эски ҳужжат (priceUnit йўқ) → fixed; toMap майдон ёзмайди (эски шакл)', () {
      final old = TvShopItem.fromFirestore(_Doc('a', {'ownerPhone': '1', 'title': 'Нон', 'price': 5000}));
      expect(old.priceUnit, PriceUnit.fixed);
      expect(old.toMap().containsKey('priceUnit'), isFalse);
    });

    test('ҳар бирлик сақланади ва қайта ўқилади (round-trip)', () {
      for (final u in PriceUnit.values) {
        final m = _item('a', price: 100, unit: u).toMap();
        expect(m.containsKey('priceUnit'), u != PriceUnit.fixed, reason: u.name);
        final back = TvShopItem.fromFirestore(_Doc('a', {...m, 'createdAt': null}));
        expect(back.priceUnit, u, reason: u.name);
      }
    });

    test('номаълум/нотўғри тур қиймат → fixed', () {
      expect(TvShopItem.fromFirestore(_Doc('a', {'priceUnit': 'week'})).priceUnit, PriceUnit.fixed);
      expect(TvShopItem.fromFirestore(_Doc('a', {'priceUnit': 7})).priceUnit, PriceUnit.fixed);
    });

    test('priceLabel: fixed — аввалги formatMoney билан айнан; 0 + negotiable — «Келишилади»; 0 + бошқа — бўш', () {
      expect(_item('a', price: 150000).priceLabel(_key), formatMoney(150000));
      expect(_item('a', price: 150000, unit: PriceUnit.hour).priceLabel(_key),
          '${formatMoney(150000)} / price_unit_short_hour');
      expect(_item('a', price: 0, unit: PriceUnit.negotiable).priceLabel(_key), 'yuk_negotiable');
      expect(_item('a', price: 0).priceLabel(_key), '');
      expect(_item('a', price: 0, unit: PriceUnit.kg).priceLabel(_key), '');
    });
  });

  group('Форма — нарх бирлиги танлови', () {
    testWidgets('хизмат (Шахсий хизматлар): профил рўйхати, бошланғич — profile.defaultPriceUnit', (tester) async {
      final profile = BusinessTypeProfile.of(BusinessCategory.personal);
      await _pump(tester, BusinessProductFormScreen(
          business: _biz(BusinessCategory.personal), repository: _FakeShop(), ownerPhone: '998901111111'));
      for (final u in PriceUnit.values) {
        expect(find.byKey(ValueKey('bizprod_unit_${u.name}')), profile.priceUnits.contains(u) ? findsOneWidget : findsNothing,
            reason: u.name);
      }
      final chip = tester.widget<ChoiceChip>(find.byKey(ValueKey('bizprod_unit_${profile.defaultPriceUnit.name}')));
      expect(chip.selected, isTrue);
      expect(find.text('price_unit_label'), findsOneWidget);
    });

    testWidgets('дўкон: маҳсулот бирликлари (соат/ой йўқ, кг/дона бор)', (tester) async {
      await _pump(tester, BusinessProductFormScreen(
          business: _biz(BusinessCategory.retail), repository: _FakeShop(), ownerPhone: '998901111111'));
      expect(find.byKey(const ValueKey('bizprod_unit_kg')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_unit_piece')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_unit_hour')), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_unit_month')), findsNothing);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('bizprod_unit_fixed'))).selected, isTrue);
    });

    testWidgets('битта бирлик (ресторан менюси) — танлов умуман кўринмайди', (tester) async {
      expect(BusinessTypeProfile.of(BusinessCategory.food).priceUnits, [PriceUnit.fixed]);
      await _pump(tester, BusinessProductFormScreen(
          business: _biz(BusinessCategory.food), repository: _FakeShop(), ownerPhone: '998901111111'));
      expect(find.byKey(const ValueKey('bizprod_unit')), findsNothing);
    });

    testWidgets('«Келишилади» + нарх бўш → price 0, priceUnit negotiable сақланади', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, BusinessProductFormScreen(
        business: _biz(BusinessCategory.personal),
        repository: shop,
        ownerPhone: '998901111111',
        pickPhotos: (room) async => ['a.jpg'],
        uploadPhotos: (phone, paths) async => ['https://cdn/a.jpg'],
      ));
      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Соч олиш');
      await tester.tap(find.byKey(const ValueKey('bizprod_unit_negotiable')));
      await tester.pump();
      expect(find.text('yuk_negotiable'), findsOneWidget, reason: 'нарх остида харидор кўриниши');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(shop.created!.price, 0);
      expect(shop.created!.priceUnit, PriceUnit.negotiable);
      expect(shop.created!.toMap()['priceUnit'], 'negotiable');
    });

    testWidgets('соатбай нарх: кўриниш «50 000 сўм / соат», сақланади', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, BusinessProductFormScreen(
        business: _biz(BusinessCategory.personal),
        repository: shop,
        ownerPhone: '998901111111',
        pickPhotos: (room) async => ['a.jpg'],
        uploadPhotos: (phone, paths) async => ['https://cdn/a.jpg'],
      ));
      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Массаж');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '50 000');
      await tester.tap(find.byKey(const ValueKey('bizprod_unit_hour')));
      await tester.pump();
      expect(find.text('${formatMoney(50000)} / price_unit_short_hour'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(shop.created!.price, 50000);
      expect(shop.created!.priceUnit, PriceUnit.hour);
    });

    testWidgets('таҳрир: сақланган бирлик танланган; fixed га қайтса — майдон ўчирилади', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, BusinessProductFormScreen(
        business: _biz(BusinessCategory.personal),
        existing: _item('i1', price: 9000, unit: PriceUnit.session),
        repository: shop,
        ownerPhone: '998901111111',
      ));
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('bizprod_unit_session'))).selected, isTrue);
      await tester.tap(find.byKey(const ValueKey('bizprod_unit_fixed')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(shop.patch!['priceUnit'], isA<FieldValue>(), reason: 'FieldValue.delete()');
      expect(shop.patch!['price'], 9000);
    });

    testWidgets('таҳрир: бирлик ўзгармаса (fixed) — patch да priceUnit йўқ (эски шакл)', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, BusinessProductFormScreen(
        business: _biz(BusinessCategory.retail),
        existing: _item('i2', price: 9000),
        repository: shop,
        ownerPhone: '998901111111',
      ));
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(shop.patch!.containsKey('priceUnit'), isFalse);
    });

    testWidgets('таҳрир: профилда йўқ сақланган бирлик ҳам кўрсатилади (қиймат йўқолмайди)', (tester) async {
      await _pump(tester, BusinessProductFormScreen(
        business: _biz(BusinessCategory.retail),
        existing: _item('i3', price: 9000, unit: PriceUnit.hour),
        repository: _FakeShop(),
        ownerPhone: '998901111111',
      ));
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('bizprod_unit_hour'))).selected, isTrue);
    });
  });

  group('Кўриниш — карточка ва варақ', () {
    final hour = _item('h', title: 'Массаж', price: 50000, unit: PriceUnit.hour);
    final neg = _item('n', title: 'Қўй', unit: PriceUnit.negotiable);
    final fixed = _item('f', title: 'Нон', price: 5000);

    // Карточкалар тармоқ расмини юклайди — pumpAndSettle ўрнига битта кадр етарли (матн дарров чизилади).
    Future<void> pumpCard(WidgetTester tester, Widget body) async {
      tester.view.physicalSize = const Size(900 * 2, 1400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: body)));
      await tester.pump();
    }

    testWidgets('TvShopItemGridCard', (tester) async {
      await pumpCard(tester, Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final it in [hour, neg, fixed])
          Expanded(child: TvShopItemGridCard(item: it, onTap: () {})),
      ]));
      expect(find.text('${formatMoney(50000)} / price_unit_short_hour'), findsOneWidget);
      expect(find.text('yuk_negotiable'), findsOneWidget);
      expect(find.text(formatMoney(5000)), findsOneWidget, reason: 'fixed — аввалгидек');
    });

    testWidgets('TvShopItemCard', (tester) async {
      await pumpCard(tester, SingleChildScrollView(child: TvShopItemCard(item: hour)));
      expect(find.text('${formatMoney(50000)} / price_unit_short_hour'), findsOneWidget);
    });

    testWidgets('BusinessDetailSheet маҳсулотлар қатори', (tester) async {
      await _pump(tester, Scaffold(body: BusinessDetailSheet(
        pin: BusinessPin.fromBusiness(_biz(BusinessCategory.personal)),
        shopRepository: _FakeShop([hour, neg, fixed]),
      )));
      expect(find.text('${formatMoney(50000)} / price_unit_short_hour'), findsOneWidget);
      expect(find.text('yuk_negotiable'), findsOneWidget);
      expect(find.text(formatMoney(5000)), findsOneWidget);
    });

    testWidgets('BusinessProductsScreen (эга рўйхати)', (tester) async {
      await _pump(tester, BusinessProductsScreen(
          business: _biz(BusinessCategory.personal), repository: _FakeShop([hour])));
      expect(find.textContaining('${formatMoney(50000)} / price_unit_short_hour'), findsOneWidget);
    });
  });
}
