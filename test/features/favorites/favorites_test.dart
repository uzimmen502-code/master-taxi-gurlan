// «Бозорлар» STAGE 10 — ❤ Танланганлар: калит, оптимистик босиш/қайтариш, ҳисоблагич, «Мавжуд эмас», меҳмон.
import 'dart:async';

import 'package:ava_gurlan/features/favorites/data/favorites_repository.dart';
import 'package:ava_gurlan/features/favorites/domain/favorite_ref.dart';
import 'package:ava_gurlan/features/favorites/favorites_controller.dart';
import 'package:ava_gurlan/features/favorites/screens/favorites_screen.dart';
import 'package:ava_gurlan/features/favorites/widgets/favorite_heart.dart';
import 'package:ava_gurlan/features/favorites/widgets/favorites_top_chip.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = '998901234567';

class _FakeRepo implements FavoritesRepository {
  final StreamController<List<FavoriteRef>> ctrl = StreamController<List<FavoriteRef>>.broadcast();
  final List<String> watched = [];
  final List<String> added = [];
  final List<String> removed = [];
  Completer<void>? gate;
  Object? failWith;
  Map<String, Map<String, dynamic>?> sources = {};
  int fetchCalls = 0;

  @override
  Stream<List<FavoriteRef>> watch(String uid) {
    watched.add(uid);
    return ctrl.stream;
  }

  Future<void> _maybe() async {
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> add(String uid, FavoriteRef ref) async {
    await _maybe();
    added.add(ref.key);
  }

  @override
  Future<void> remove(String uid, String key) async {
    await _maybe();
    removed.add(key);
  }

  @override
  Future<Map<String, Map<String, dynamic>?>> fetchSources(List<FavoriteRef> refs) async {
    fetchCalls++;
    return {for (final r in refs) if (sources.containsKey(r.key)) r.key: sources[r.key]};
  }
}

TvShopItem _item(String id, {int price = 85000, PriceUnit unit = PriceUnit.kg}) => TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'S',
      title: 'Гўшт $id',
      price: price,
      photoUrl: 'https://x/$id.jpg',
      kind: 'product',
      districtId: 'gurlan',
      districtLabel: '',
      market: 'meat',
      priceUnit: unit,
    );

FavoriteRef _ref(String collection, String id, {String market = ''}) =>
    FavoriteRef(collection: collection, itemId: id, title: 'T $id', market: market);

(FavoritesController, _FakeRepo, StreamController<String>) _started({String uid = _uid}) {
  final repo = _FakeRepo();
  // sync: uid дарров етади (testWidgets fakeAsync ичида Future.delayed осилиб қолмасин).
  final uidCtrl = StreamController<String>(sync: true);
  final c = FavoritesController(repository: repo, uidStream: uidCtrl.stream);
  c.ensureStarted();
  uidCtrl.add(uid);
  return (c, repo, uidCtrl);
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('калит ва шакл (rules билан бир хил)', () {
    test('favoriteKey = collection_itemId; барча 4 манба', () {
      expect(favoriteKey('tv_shop_items', 'a1'), 'tv_shop_items_a1');
      expect(FavoriteCollections.all, ['tv_shop_items', 'wholesale_products', 'realty_listings', 'ads']);
      expect(FavoriteRef.fromShopItem(_item('a1')).key, 'tv_shop_items_a1');
    });

    test('fromShopItem: нарх, бирлик wire, бозор, расм', () {
      final m = FavoriteRef.fromShopItem(_item('a1')).toCreateMap();
      expect(m, {
        'collection': 'tv_shop_items',
        'itemId': 'a1',
        'title': 'Гўшт a1',
        'photoUrl': 'https://x/a1.jpg',
        'price': 85000,
        'priceUnit': PriceUnit.kg.wire,
        'market': 'meat',
      });
      expect(m.containsKey('addedAt'), isFalse, reason: 'addedAt = serverTimestamp репозиторийда');
    });

    test('fixed бирлик ва 0 нарх ёзилмайди', () {
      final m = FavoriteRef.fromShopItem(_item('a2', price: 0, unit: PriceUnit.fixed)).toCreateMap();
      expect(m.containsKey('price'), isFalse);
      expect(m.containsKey('priceUnit'), isFalse);
    });

    test('чегаралар: нарх > 999999999 ташланади, сарлавҳа 200 га кесилади, узун URL ёзилмайди', () {
      final m = FavoriteRef(
        collection: 'ads',
        itemId: 'x',
        title: 't' * 250,
        photoUrl: 'u' * 1001,
        price: 1000000000,
        market: 'm' * 30,
      ).toCreateMap();
      expect(m.containsKey('price'), isFalse);
      expect((m['title'] as String).length, 200);
      expect(m.containsKey('photoUrl'), isFalse);
      expect((m['market'] as String).length, 20);
      expect(const FavoriteRef(collection: 'ads', itemId: 'x', price: 999999999).toCreateMap()['price'], 999999999);
    });

    test('isValid: номаълум манба, бўш/узун/`/` ли ID — йўқ', () {
      expect(_ref('ads', 'ok').isValid, isTrue);
      expect(_ref('orders', 'ok').isValid, isFalse);
      expect(_ref('ads', '').isValid, isFalse);
      expect(_ref('ads', 'a' * 129).isValid, isFalse);
      expect(_ref('ads', 'a' * 128).isValid, isTrue);
      expect(_ref('ads', 'a/b').isValid, isFalse);
    });

    test('Улгуржи: сўмдан бошқа валютада нарх снимоги йўқ', () {
      WholesaleProduct w(String cur) => WholesaleProduct.fromMap('w1', {
            'title': 'Т',
            'status': 'active',
            'currency': cur,
            'market': 'china',
            'priceTiers': [
              {'minQty': 1, 'price': 9000}
            ],
          });
      expect(FavoriteRef.fromWholesale(w('USD')).toCreateMap().containsKey('price'), isFalse);
      expect(FavoriteRef.fromWholesale(w('')).toCreateMap()['market'], 'china');
    });

    test('fromMap: эски/бузуқ майдонлар', () {
      final f = FavoriteRef.fromMap('ads_z9', {'collection': 'ads', 'price': 10.5});
      expect(f.itemId, 'z9');
      expect(f.price, isNull);
    });
  });

  group('контроллер', () {
    test('битта тингловчи; меҳмонда тингламайди', () async {
      final (c, repo, _) = _started();
      expect(repo.watched, [_uid]);
      final (g, grepo, _) = _started(uid: '');
      expect(g.isGuest, isTrue);
      expect(grepo.watched, isEmpty);
      expect(await g.toggle(_ref('ads', 'a')), FavoriteToggleOutcome.guest);
      expect(grepo.added, isEmpty);
      c.dispose();
      g.dispose();
    });

    test('оптимистик: жавобдан олдин юрак ёнади, иккинчи босиш — busy', () async {
      final (c, repo, _) = _started();
      repo.gate = Completer<void>();
      final ref = _ref('ads', 'a1');
      final f = c.toggle(ref);
      expect(c.isFavorite(ref.key), isTrue);
      expect(c.count, 1);
      expect(await c.toggle(ref), FavoriteToggleOutcome.busy);
      repo.gate!.complete();
      expect(await f, FavoriteToggleOutcome.added);
      expect(c.isFavorite(ref.key), isTrue);
      expect(repo.added, ['ads_a1']);
    });

    test('хато → олдинги ҳолатга қайтади (rollback), failed', () async {
      final (c, repo, _) = _started();
      repo.ctrl.add([_ref('ads', 'a1')]);
      await Future<void>.delayed(Duration.zero);
      expect(c.isFavorite('ads_a1'), isTrue);
      repo.gate = Completer<void>();
      repo.failWith = Exception('PERMISSION_DENIED');
      final f = c.toggle(_ref('ads', 'a1'));
      expect(c.isFavorite('ads_a1'), isFalse, reason: 'оптимистик олиб ташлаш');
      expect(c.count, 0);
      repo.gate!.complete();
      expect(await f, FavoriteToggleOutcome.failed);
      expect(c.isFavorite('ads_a1'), isTrue, reason: 'rollback');
      expect(c.count, 1);
      expect(repo.removed, isEmpty);
    });

    test('ҳисоб чиқса (uid ўзгарса) рўйхат тозаланади', () async {
      final (c, repo, uidCtrl) = _started();
      repo.ctrl.add([_ref('ads', 'a1')]);
      await Future<void>.delayed(Duration.zero);
      expect(c.count, 1);
      uidCtrl.add('');
      await Future<void>.delayed(Duration.zero);
      expect(c.count, 0);
      expect(c.isGuest, isTrue);
    });
  });

  group('«Мавжуд эмас»', () {
    final now = DateTime(2026, 11, 15);
    test('йўқ / status != active / муддати ўтган — мавжуд эмас', () {
      expect(favoriteSourceAvailable(null, now: now), isFalse);
      for (final s in ['deleted', 'expired', 'rejected', 'blocked', 'inactive', 'pending', '']) {
        expect(favoriteSourceAvailable({'status': s}, now: now), isFalse, reason: s);
      }
      expect(favoriteSourceAvailable({'status': 'active'}, now: now), isTrue);
      expect(favoriteSourceAvailable({'status': 'active', 'expiresAt': DateTime(2026, 11, 14)}, now: now), isFalse);
      expect(favoriteSourceAvailable({'status': 'active', 'expiresAt': DateTime(2026, 11, 16)}, now: now), isTrue);
    });

    test('аниқланмаган (тармоқ) — checking, «мавжуд эмас» эмас', () {
      expect(favoriteAvailabilityOf('k', const {}), FavoriteAvailability.checking);
      expect(favoriteAvailabilityOf('k', const {'k': null}), FavoriteAvailability.unavailable);
      expect(favoriteAvailabilityOf('k', const {'k': {'status': 'active'}}), FavoriteAvailability.available);
    });

    testWidgets('экран: ўчирилган элемент кулранг «Мавжуд эмас» + олиб ташлаш; чиплар манба бўйича', (t) async {
      final (c, repo, _) = _started();
      repo.sources = {
        'ads_gone': null,
        'wholesale_products_w1': {'status': 'active', 'title': 'W', 'market': 'china'},
      };
      await t.pumpWidget(MaterialApp(home: FavoritesScreen(controller: c)));
      repo.ctrl.add([_ref('ads', 'gone'), _ref('wholesale_products', 'w1', market: 'china')]);
      await t.pumpAndSettle();
      expect(repo.fetchCalls, 1);
      expect(find.byKey(const ValueKey('fav_unavailable_ads_gone')), findsOneWidget);
      expect(find.byKey(const ValueKey('fav_unavailable_wholesale_products_w1')), findsNothing);
      expect(find.byKey(const ValueKey('fav_chip_china')), findsOneWidget);
      expect(find.byKey(const ValueKey('fav_chip_aralash')), findsOneWidget);
      expect(find.byKey(const ValueKey('fav_chip_realty')), findsNothing);

      await t.tap(find.byKey(const ValueKey('fav_chip_china')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('fav_row_ads_gone')), findsNothing);
      await t.tap(find.byKey(const ValueKey('fav_chip_all')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('fav_remove_ads_gone')));
      await t.pumpAndSettle();
      expect(repo.removed, ['ads_gone']);
      expect(find.byKey(const ValueKey('fav_row_ads_gone')), findsNothing);
    });

    testWidgets('экран: бўш рўйхат', (t) async {
      final (c, _, _) = _started();
      await t.pumpWidget(MaterialApp(home: FavoritesScreen(controller: c)));
      await t.pump();
      expect(find.byKey(const ValueKey('fav_empty')), findsOneWidget);
    });
  });

  group('ҳисоблагич «❤ N»', () {
    testWidgets('N = 0 — кўринмайди; N > 0 — кўринади, босилса очилади', (t) async {
      final (c, repo, _) = _started();
      var opened = 0;
      await t.pumpWidget(_host(FavoritesTopChip(controller: c, onOpen: () => opened++)));
      expect(find.byKey(const ValueKey('fav_top_chip')), findsNothing);
      repo.ctrl.add([_ref('ads', 'a'), _ref('tv_shop_items', 'b')]);
      await t.pump();
      expect(find.byKey(const ValueKey('fav_top_chip')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('fav_top_chip')));
      expect(opened, 1);
      repo.ctrl.add(const []);
      await t.pump();
      expect(find.byKey(const ValueKey('fav_top_chip')), findsNothing);
    });
  });

  group('юрак виджети', () {
    testWidgets('меҳмон босса — «рўйхатдан ўтинг» чақируви, ёзув йўқ', (t) async {
      final (c, repo, _) = _started(uid: '');
      await t.pumpWidget(_host(FavoriteHeart(favorite: _ref('ads', 'a'), controller: c)));
      await t.tap(find.byKey(const ValueKey('fav_heart_ads_a')));
      await t.pump();
      expect(find.byKey(const ValueKey('fav_guest_prompt')), findsOneWidget);
      expect(find.text('fav_login_cta'), findsOneWidget);
      expect(repo.added, isEmpty);
    });

    testWidgets('босиш: юрак тўлади; хатода қайтади ва умумий хабар', (t) async {
      final (c, repo, _) = _started();
      await t.pumpWidget(_host(FavoriteHeart(favorite: _ref('ads', 'a'), controller: c)));
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('fav_heart_ads_a')));
      await t.pump();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(repo.added, ['ads_a']);

      repo.failWith = Exception('x');
      await t.tap(find.byKey(const ValueKey('fav_heart_ads_a')));
      await t.pump();
      await t.pump();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget, reason: 'rollback');
      expect(find.text('fav_toggle_failed'), findsOneWidget);
    });
  });
}
