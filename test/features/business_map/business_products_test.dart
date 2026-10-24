import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_pin.dart';
import 'package:ava_gurlan/features/business_map/domain/product_kind.dart';
import 'package:ava_gurlan/features/business_map/screens/business_product_form_screen.dart';
import 'package:ava_gurlan/features/business_map/screens/business_products_screen.dart';
import 'package:ava_gurlan/features/business_map/widgets/business_detail_sheet.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_ad_prefill.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга қарори (2026-10-24): объект маҳсулотлари = мавжуд витрина ҳужжати + `businessId`; сони чекланмаган;
/// модерациясиз (дарҳол `active`); 7 тагача расм; видео ихтиёрий.
class _FakeShop implements TvShopRepository {
  _FakeShop([List<TvShopItem>? items]) : items = items ?? [];

  List<TvShopItem> items;
  final calls = <String>[];
  TvShopItem? created;
  Map<String, dynamic>? patch;

  @override
  Future<List<TvShopItem>> fetchByBusiness(
    String businessId, {
    String ownerPhone = '',
    bool onlyActive = true,
    int limit = 200,
  }) async {
    calls.add('fetch:$businessId:$ownerPhone:$onlyActive');
    return TvShopRepository.visibleBusinessItems(items, ownerPhone: ownerPhone, onlyActive: onlyActive);
  }

  @override
  Future<void> ensureShop({required String ownerPhone, required String name}) async =>
      calls.add('ensureShop:$ownerPhone:$name');

  @override
  Future<String> createItem(TvShopItem item) async {
    created = item;
    calls.add('create');
    return 'item1';
  }

  @override
  Future<void> updateItem(String itemId, Map<String, dynamic> p) async {
    patch = p;
    calls.add('update:$itemId');
  }

  @override
  Future<void> deleteItem(String itemId) async => calls.add('delete:$itemId');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Business _biz({BusinessCategory c = BusinessCategory.retail, String owner = '998901111111'}) => Business(
      id: 'b1',
      ownerId: owner,
      name: 'Мой Дўкон',
      category: c,
      phone: '998901234567',
      lat: 41.3,
      lng: 69.2,
      districtId: 'gurlan',
    );

TvShopItem _item(
  String id, {
  String title = 'Товар',
  String owner = '998901111111',
  String status = 'active',
  int price = 0,
  DateTime? at,
  List<String> clips = const [],
  String businessId = 'b1',
}) =>
    TvShopItem(
      id: id,
      ownerPhone: owner,
      ownerName: 'x',
      title: title,
      price: price,
      photoUrl: 'https://x/$id.jpg',
      photoUrls: ['https://x/$id.jpg'],
      kind: 'product',
      districtId: 'gurlan',
      districtLabel: '',
      status: status,
      createdAt: at,
      clipIds: clips,
      businessId: businessId,
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420 * 2, 900 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

void main() {
  group('модел ва соф қоидалар', () {
    test('7 тагача расм; businessId ёзилади ва фақат бўш бўлмаса', () {
      expect(TvShopItem.maxPhotos, 7);
      expect(TvShopItem.normalizePhotos(rawUrls: [for (var i = 0; i < 9; i++) 'u$i']).length, 7);
      expect(_item('a').toMap()['businessId'], 'b1');
      expect(_item('a', businessId: '').toMap().containsKey('businessId'), isFalse);
    });

    test('parseProductPrice: бўш — 0; бўшлиқ/вергул ҳисобга олинмайди; ҳарф ва узун — null', () {
      expect(parseProductPrice(''), 0);
      expect(parseProductPrice('15 000'), 15000);
      expect(parseProductPrice('15,000'), 15000);
      expect(parseProductPrice('12a'), isNull);
      expect(parseProductPrice('1234567890'), isNull);
      expect(parseProductPrice('-5'), isNull);
    });

    test('бошланғич тур: хизмат турлари — service, қолгани — product (14 тур тўлиқ қопланган)', () {
      const services = {
        BusinessCategory.personal,
        BusinessCategory.homeServices,
        BusinessCategory.health,
        BusinessCategory.education,
        BusinessCategory.leisure,
        BusinessCategory.logistics,
        BusinessCategory.professional,
        BusinessCategory.itMedia,
      };
      for (final c in BusinessCategory.values) {
        expect(defaultProductKind(c), services.contains(c) ? 'service' : 'product', reason: c.wire);
      }
    });

    test('visibleBusinessItems: ўчирилган, фаол эмас, ёт эга чиқарилади; энг янги биринчи', () {
      final t0 = DateTime(2026, 10, 1);
      final all = [
        _item('old', at: t0),
        _item('new', at: t0.add(const Duration(days: 2))),
        _item('del', status: 'deleted', at: t0),
        _item('pend', status: 'pending', at: t0),
        _item('alien', owner: '998909999999', at: t0),
      ];
      final pub = TvShopRepository.visibleBusinessItems(all, ownerPhone: '998901111111');
      expect(pub.map((e) => e.id), ['new', 'old']);
      final mine = TvShopRepository.visibleBusinessItems(all, ownerPhone: '+998 90 111 11 11', onlyActive: false);
      expect(mine.map((e) => e.id).toSet(), {'new', 'old', 'pend'}, reason: 'ўчирилган ва ёт эга йўқ, кутилаётган бор');
      expect(TvShopRepository.visibleBusinessItems(all, onlyActive: false).map((e) => e.id).contains('alien'), isTrue,
          reason: 'ownerPhone берилмаса эга фильтри йўқ');
    });
  });

  group('BusinessProductFormScreen', () {
    testWidgets('майдонлар текширилади: ном → нарх → расм; сервер чақирилмайди', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, BusinessProductFormScreen(business: _biz(), repository: shop, ownerPhone: '998901111111'));

      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(find.text('bizprod_err_name'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Нон');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '12 000');
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(find.text('tv_shop_photo_required'), findsOneWidget);
      expect(shop.calls, isEmpty);
    });

    testWidgets('яратиш: 7 тадан ортиқ расм кесилади, businessId/эга/тур/нарх тўғри, дарҳол active; видео «кейин»', (tester) async {
      final shop = _FakeShop();
      String? uploadedFor;
      List<String>? uploadedPaths;
      var videoFor = '';
      await _pump(
        tester,
        BusinessProductFormScreen(
          business: _biz(c: BusinessCategory.personal),
          repository: shop,
          ownerPhone: '998901111111',
          pickPhotos: (room) async => [for (var i = 0; i < 10; i++) 'p$i.jpg'],
          uploadPhotos: (phone, paths) async {
            uploadedFor = phone;
            uploadedPaths = paths;
            return [for (final p in paths) 'https://cdn/$p'];
          },
          addVideo: (ctx, id) async => videoFor = id,
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Стрижка');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '50 000');
      await tester.enterText(find.byKey(const ValueKey('bizprod_desc')), 'Тавсиф');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();

      expect(uploadedFor, '998901111111');
      expect(uploadedPaths!.length, 7, reason: '10 та танланса ҳам 7 таси');
      final c = shop.created!;
      expect(c.businessId, 'b1');
      expect(c.ownerPhone, '998901111111');
      expect(c.title, 'Стрижка');
      expect(c.price, 50000);
      expect(c.kind, 'service', reason: 'Шахсий хизматлар — бошланғич «хизмат»');
      expect(c.status, 'active', reason: 'модерациясиз');
      expect(c.districtId, 'gurlan');
      expect(c.photoUrls.length, 7);
      expect(shop.calls, containsAllInOrder(['ensureShop:998901111111:Мой Дўкон', 'create']));

      expect(find.text('bizprod_video_ask_title'), findsOneWidget);
      await tester.tap(find.text('bizprod_video_later'));
      await tester.pumpAndSettle();
      expect(videoFor, isEmpty, reason: '«кейин» — видео нашри очилмайди');
    });

    testWidgets('яратиш: «Видео қўшиш» — яратилган маҳсулот id си билан чақирилади', (tester) async {
      final shop = _FakeShop();
      var videoFor = '';
      await _pump(
        tester,
        BusinessProductFormScreen(
          business: _biz(),
          repository: shop,
          ownerPhone: '998901111111',
          pickPhotos: (room) async => ['a.jpg'],
          uploadPhotos: (phone, paths) async => ['https://cdn/a.jpg'],
          addVideo: (ctx, id) async => videoFor = id,
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Нон');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('bizprod_video_add'));
      await tester.pumpAndSettle();
      expect(videoFor, 'item1');
    });

    testWidgets('юклаш йиқилса — хато кўрсатилади, ҳужжат яратилмайди', (tester) async {
      final shop = _FakeShop();
      await _pump(
        tester,
        BusinessProductFormScreen(
          business: _biz(),
          repository: shop,
          ownerPhone: '998901111111',
          pickPhotos: (room) async => ['a.jpg'],
          uploadPhotos: (phone, paths) async => throw StateError('network'),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Нон');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(find.text('bizprod_err_generic'), findsOneWidget);
      expect(shop.created, isNull);
    });

    testWidgets('таҳрир: майдонлар тўлдирилган, фақат матн майдонлари updateItem билан ёзилади', (tester) async {
      final shop = _FakeShop();
      await _pump(
        tester,
        BusinessProductFormScreen(
          business: _biz(),
          existing: _item('i7', title: 'Эски ном', price: 9000),
          repository: shop,
          ownerPhone: '998901111111',
        ),
      );
      expect(find.text('Эски ном'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Янги ном');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '');
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(shop.calls, ['update:i7']);
      expect(shop.patch, {'title': 'Янги ном', 'price': 0, 'description': '', 'kind': 'product'});
      expect(shop.patch!.containsKey('photoUrls'), isFalse);
      expect(shop.patch!.containsKey('businessId'), isFalse, reason: 'боғланиш таҳрирда ўзгармайди');
    });
  });

  group('BusinessProductsScreen', () {
    testWidgets('бўш — тушунтириш; қўшиш тугмаси бор', (tester) async {
      await _pump(tester, BusinessProductsScreen(business: _biz(), repository: _FakeShop()));
      expect(find.text('bizprod_empty'), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_fab')), findsOneWidget);
    });

    testWidgets('эга ўз маҳсулотларини (кутилаётган ҳам) кўради; ўчириш — тасдиқдан кейин', (tester) async {
      final shop = _FakeShop([
        _item('a', title: 'Нон', price: 5000, clips: const ['c1']),
        _item('b', title: 'Кутилмоқда', status: 'pending'),
        _item('x', title: 'Ёт', owner: '998909999999'),
        _item('d', title: 'Ўчирилган', status: 'deleted'),
      ]);
      await _pump(tester, BusinessProductsScreen(business: _biz(), repository: shop));
      expect(find.text('Нон'), findsOneWidget);
      expect(find.text('Кутилмоқда'), findsOneWidget);
      expect(find.text('Ёт'), findsNothing);
      expect(find.text('Ўчирилган'), findsNothing);
      expect(find.textContaining('bizprod_has_video'), findsOneWidget);
      expect(shop.calls.first, 'fetch:b1:998901111111:false');

      await tester.tap(find.byTooltip('bizmap_delete').first);
      await tester.pumpAndSettle();
      expect(shop.calls.where((c) => c.startsWith('delete')), isEmpty, reason: 'тасдиқсиз ўчирилмайди');
      await tester.tap(find.widgetWithText(TextButton, 'bizmap_delete'));
      await tester.pumpAndSettle();
      expect(shop.calls.where((c) => c.startsWith('delete')).length, 1);
    });

    testWidgets('«Реклама қилиш»: фақат фаол маҳсулотда; босилса — шу маҳсулот билан чақирилади (янги тизим эмас)', (tester) async {
      TvShopItem? promoted;
      final shop = _FakeShop([
        _item('a', title: 'Нон', price: 5000),
        _item('p', title: 'Кутилмоқда', status: 'pending'),
      ]);
      await _pump(
        tester,
        BusinessProductsScreen(business: _biz(), repository: shop, onPromote: (ctx, it) => promoted = it),
      );
      expect(find.byKey(const ValueKey('bizprod_promote_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_promote_p')), findsNothing, reason: 'кутилаётган/блокли маҳсулот рекламаланмайди');
      await tester.tap(find.byKey(const ValueKey('bizprod_promote_a')));
      await tester.pump();
      expect(promoted?.id, 'a');
    });

    testWidgets('ўчириш — рўйхат қайта юкланади (кейинги сўров) ва маҳсулот йўқолади', (tester) async {
      final shop = _FakeShop([_item('a', title: 'Нон')]);
      await _pump(tester, BusinessProductsScreen(business: _biz(), repository: shop));
      await tester.tap(find.byTooltip('bizmap_delete').first);
      await tester.pumpAndSettle();
      shop.items = []; // сервер ўчиргандан кейин рўйхат бўш
      await tester.tap(find.widgetWithText(TextButton, 'bizmap_delete'));
      await tester.pumpAndSettle();
      expect(shop.calls.where((c) => c.startsWith('fetch')).length, 2, reason: 'ўчиргандан кейин қайта юкланган');
      expect(find.text('Нон'), findsNothing);
      expect(find.text('bizprod_empty'), findsOneWidget);
    });
    testWidgets('қўшиш тугмаси форма экранини очади', (tester) async {
      await _pump(tester, BusinessProductsScreen(business: _biz(), repository: _FakeShop()));
      await tester.tap(find.byKey(const ValueKey('bizprod_fab')));
      await tester.pumpAndSettle();
      expect(find.text('bizprod_new'), findsOneWidget);
    });
  });

  group('BusinessDetailSheet — маҳсулотлар қатори', () {
    BusinessPin pin(Business b) => BusinessPin.fromBusiness(b);

    testWidgets('фаол маҳсулот бор — қатор чиқади; кутилаётган/ёт чиқмайди', (tester) async {
      final shop = _FakeShop([
        _item('a', title: 'Нон', price: 5000),
        _item('p', title: 'Кутилмоқда', status: 'pending'),
        _item('x', title: 'Ёт', owner: '998909999999'),
      ]);
      await _pump(tester, Scaffold(body: BusinessDetailSheet(pin: pin(_biz()), shopRepository: shop)));
      expect(find.byKey(const ValueKey('biz_products_strip')), findsOneWidget);
      expect(find.text('Нон'), findsOneWidget);
      expect(find.text('Кутилмоқда'), findsNothing);
      expect(find.text('Ёт'), findsNothing);
      expect(shop.calls, ['fetch:b1:998901111111:true']);
    });

    testWidgets('маҳсулот йўқ — бўлим умуман чиқмайди', (tester) async {
      await _pump(tester, Scaffold(body: BusinessDetailSheet(pin: pin(_biz()), shopRepository: _FakeShop())));
      expect(find.byKey(const ValueKey('biz_products_strip')), findsNothing);
      expect(find.text('bizprod_section'), findsNothing);
    });
  });

  group('TvAdPrefill', () {
    test('маҳсулотдан: ном/нарх/тавсиф; узун матн реклама экрани чегарасигача қирқилади', () {
      final p = TvAdPrefill.fromItem(_item('a', title: ' Нон ', price: 5000));
      expect([p.title, p.price], ['Нон', 5000]);
      expect(p.shopItemId, 'a', reason: 'реклама шу каталог маҳсулотига боғланади');
      final long = _item('b', title: 'x' * 120).toMap();
      final cut = TvAdPrefill.fromItem(TvShopItem(
        id: 'b', ownerPhone: '1', ownerName: '', title: 'я' * 120, price: -5, photoUrl: '', kind: 'product',
        districtId: '', districtLabel: '', description: 'ў' * 700,
      ));
      expect(long['title'], isNotEmpty);
      expect(cut.title.length, TvAdPrefill.titleMax);
      expect(cut.description.length, TvAdPrefill.descriptionMax);
      expect(cut.price, 0, reason: 'манфий нарх — 0 (нарх майдони бўш)');
    });

    test('эмодзи (суррогат жуфт) ўртасидан қирқилмайди', () {
      final p = TvAdPrefill.fromItem(TvShopItem(
        id: 'c', ownerPhone: '1', ownerName: '', title: '😀' * 100, price: 0, photoUrl: '', kind: 'product',
        districtId: '', districtLabel: '',
      ));
      expect(p.title.runes.length, TvAdPrefill.titleMax);
      expect(p.title.runes.every((r) => r == 0x1F600), isTrue);
    });
  });}
