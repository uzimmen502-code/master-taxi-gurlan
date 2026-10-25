import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/data/business_repository.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_pin.dart';
import 'package:ava_gurlan/features/business_map/screens/business_form_screen.dart';
import 'package:ava_gurlan/features/business_map/widgets/business_detail_sheet.dart';
import 'package:ava_gurlan/features/tv_market/domain/clip_product_link.dart';
import 'package:ava_gurlan/features/tv_market/domain/similar_items.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_item_detail_screen.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_clip_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 3-босқич (эга қарори 2026-10-25): харидор Аҳоли бозори, АВАГрам ва харитадан АЙНАН тегишли дўкон/маҳсулотга ўтади.
const _owner = '998901111111';
const _alien = '998909999999';

TvShopItem _item(String id, String title, {String owner = _owner, String biz = '', String status = 'active', String kind = 'product'}) =>
    TvShopItem(
      id: id,
      ownerPhone: owner,
      ownerName: 'x',
      title: title,
      price: 1000,
      photoUrl: '',
      kind: kind,
      districtId: 'd',
      districtLabel: '',
      status: status,
      businessId: biz,
    );

TvClip _clip({String shopItemId = '', String owner = '+998901111111'}) => TvClip(
      id: 'c1',
      videoUrl: 'https://example.test/a.mp4',
      posterUrl: '',
      title: 'Видео',
      price: 0,
      districtId: 'd1',
      districtLabel: 'Гурлан',
      ownerPhone: owner,
      ownerName: 'Сидабилла',
      category: 'product',
      shopItemId: shopItemId,
    );

Business _biz({String owner = _owner, String status = 'active', bool online = false}) => Business(
      id: 'b1',
      ownerId: owner,
      name: 'Сидабилла — Кийим',
      category: BusinessCategory.retail,
      phone: '998905550000',
      lat: online ? 0 : 41.3,
      lng: online ? 0 : 69.2,
      status: status,
      online: online,
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(480 * 2, 1400 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

class _FakeShop implements TvShopRepository {
  _FakeShop(this.items);
  final List<TvShopItem> items;

  @override
  Future<List<TvShopItem>> fetchByBusiness(String businessId, {String ownerPhone = '', bool onlyActive = true, int limit = 200}) async =>
      TvShopRepository.visibleBusinessItems(items, ownerPhone: ownerPhone, onlyActive: onlyActive);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeBiz extends BusinessRepository {
  final saved = <Business>[];

  @override
  Future<String> upsertMine(Business b, {String? businessId, required String clientRequestId}) async {
    saved.add(b);
    return 'id1';
  }
}

void main() {
  group('similarItems — ўхшаш маҳсулотлар (янги ўқишсиз)', () {
    final pool = [
      _item('a', 'Қизил кўйлак'),
      _item('b', 'Кўк кўйлак'),
      _item('c', 'Телевизор Samsung'),
      _item('d', 'Кўйлак болалар', status: 'blocked'),
      // «кўйлаги» (к→г) CatalogSearch'да ҳам «кўйлак» эмас — бозор қидируви билан бир хил чегара.
      _item('e', 'Аёллар учун кўйлак', owner: _alien),
    ];

    test('сўз бўйича ўхшаш; ўзи, фаол бўлмагани ва номоси йўқ; бошқа сотувчиники ҳам бўлиши мумкин', () {
      final s = similarItems(pool.first, pool);
      final ids = [for (final i in s) i.id];
      expect(ids, containsAll(['b', 'e']));
      expect(ids, isNot(contains('a')), reason: 'ўзи');
      expect(ids, isNot(contains('c')), reason: 'ўхшаш эмас');
      expect(ids, isNot(contains('d')), reason: 'блокланган');
      expect(ids.first, 'b', reason: 'шу сотувчиники олдин');
    });

    test('ўхшаши йўқ — бўш (тасодифий тўлдириш йўқ); чегара [max]', () {
      expect(similarItems(_item('x', 'Самолёт'), pool), isEmpty);
      final many = [for (var i = 0; i < 30; i++) _item('k$i', 'Кўйлак $i')];
      expect(similarItems(_item('q', 'Кўйлак'), many).length, 10);
    });
  });

  group('productForClip — видео бошқа маҳсулотга адашиб боғланмайди', () {
    test('фаол, айнан шу ID, клип эгасиники — очилади (телефон форматлари фарқ қилса ҳам)', () {
      expect(productForClip(_clip(shopItemId: 'p1'), _item('p1', 'Нон')), isNotNull);
    });
    test('бошқа сотувчининг маҳсулоти, бошқа ID, блокланган, йўқ — null', () {
      expect(productForClip(_clip(shopItemId: 'p1'), _item('p1', 'Нон', owner: _alien)), isNull);
      expect(productForClip(_clip(shopItemId: 'p1'), _item('p2', 'Нон')), isNull);
      expect(productForClip(_clip(shopItemId: 'p1'), _item('p1', 'Нон', status: 'blocked')), isNull);
      expect(productForClip(_clip(shopItemId: 'p1'), null), isNull);
      expect(productForClip(_clip(), _item('p1', 'Нон')), isNull);
    });
  });

  group('АВАГрам: «Маҳсулот» тугмаси', () {
    Future<void> pumpOverlay(WidgetTester tester, {VoidCallback? onOpenProduct}) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            TvClipOverlay(
              clip: _clip(shopItemId: 'p1'),
              onContact: () {},
              onLike: () {},
              onComment: () {},
              onShare: () {},
              onSave: () {},
              onOpenProduct: onOpenProduct,
            ),
          ]),
        ),
      ));
    }

    testWidgets('маҳсулотга боғланган — тугма бор ва босилади; боғланмаган — йўқ', (tester) async {
      var taps = 0;
      await pumpOverlay(tester, onOpenProduct: () => taps++);
      await tester.tap(find.byKey(const ValueKey('tv-open-product')));
      expect(taps, 1);
      await pumpOverlay(tester);
      expect(find.byKey(const ValueKey('tv-open-product')), findsNothing);
    });
  });

  group('Маҳсулот экрани: дўконга ўтиш ва ўхшашлар', () {
    testWidgets('showShopButton — «Дўконга ўтиш»; ўхшашлар қатори пулдан', (tester) async {
      final pool = [_item('a', 'Қизил кўйлак'), _item('b', 'Кўк кўйлак')];
      await _pump(
        tester,
        TvShopItemDetailScreen(item: pool.first, showShopButton: true, similarPool: pool, loadLatest: (_) async => pool.first),
      );
      expect(find.byKey(const ValueKey('shop_item_go_shop')), findsOneWidget);
      expect(find.byKey(const ValueKey('shop_item_open_shop')), findsOneWidget);
      expect(find.byKey(const ValueKey('shop_item_similar')), findsOneWidget);
      expect(find.text('Кўк кўйлак'), findsOneWidget);
    });

    testWidgets('дўкон ичида (тугмасиз) ва ўхшаши йўқ — иккаласи ҳам йўқ', (tester) async {
      final it = _item('a', 'Самолёт');
      await _pump(tester, TvShopItemDetailScreen(item: it, similarPool: [it], loadLatest: (_) async => it));
      expect(find.byKey(const ValueKey('shop_item_go_shop')), findsNothing);
      expect(find.byKey(const ValueKey('shop_item_similar')), findsNothing);
    });
  });

  group('Харита: «Дўконга ўтиш»', () {
    testWidgets('сотувчининг объекти — тугма бор; эгасиз (админ) ёки блокланган — йўқ', (tester) async {
      await _pump(tester, Scaffold(body: BusinessDetailSheet(pin: BusinessPin.fromBusiness(_biz()), shopRepository: _FakeShop(const []))));
      expect(find.byKey(const ValueKey('biz_open_shop')), findsOneWidget);
      await _pump(tester, Scaffold(body: BusinessDetailSheet(pin: BusinessPin.fromBusiness(_biz(owner: 'admin')), shopRepository: _FakeShop(const []))));
      expect(find.byKey(const ValueKey('biz_open_shop')), findsNothing);
      await _pump(tester, Scaffold(body: BusinessDetailSheet(pin: BusinessPin.fromBusiness(_biz(status: 'blocked')), shopRepository: _FakeShop(const []))));
      expect(find.byKey(const ValueKey('biz_open_shop')), findsNothing);
    });
  });

  group('Фақат онлайн йўналиш', () {
    test('модель: online — координатасиз ўқилади; серверга lat/lng юборилмайди', () {
      final b = Business.tryFromMap('b1', {'name': 'Онлайн', 'category': 'retail', 'online': true})!;
      expect([b.online, b.lat, b.lng], [true, 0, 0]);
      final m = b.toCallable();
      expect([m['online'], m.containsKey('lat'), m.containsKey('lng')], [true, false, false]);
      final p = _biz().toCallable();
      expect([p.containsKey('online'), p['lat']], [false, 41.3]);
    });

    testWidgets('форма: «Фақат онлайн» ёқилса жой сўралмайди ва манзил майдони йўқ; online:true сақланади', (tester) async {
      final repo = _FakeBiz();
      await _pump(tester, BusinessFormScreen(repository: repo, initialCategory: BusinessCategory.retail, lockCategory: true));
      expect(find.text('bizmap_pick_location'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('biz_online_switch')));
      await tester.pumpAndSettle();
      expect(find.text('bizmap_pick_location'), findsNothing);
      expect(find.widgetWithText(TextField, 'bizmap_f_address'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Сидабилла онлайн');
      await tester.enterText(find.widgetWithText(TextField, 'bizmap_f_phone'), '998901112233');
      await tester.ensureVisible(find.text('bizmap_save'));
      await tester.tap(find.text('bizmap_save'));
      await tester.pumpAndSettle();
      expect(repo.saved.single.online, isTrue);
      expect(repo.saved.single.address, '');
    });
  });
}
