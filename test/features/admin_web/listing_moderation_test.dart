// «Эълонлар модерацияси» (Бозорлар 2b, эга 2026-11-15): соф мантиқ ва экран (рад этиш сабабсиз юборилмайди,
// оптимистик олиб ташлаш, хатода жойига қайтиш + код).

import 'dart:async';

import 'package:ava_gurlan/features/admin_web/screens/listing_moderation_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_callable.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_listing_moderation_service.dart';
import 'package:ava_gurlan/features/admin_web/utils/listing_moderation.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ListingModItem _li(String id, {DateTime? at, String market = '', ListingModSource s = ListingModSource.shop}) =>
    ListingModItem(
      source: s,
      id: id,
      title: 'Эълон $id',
      priceText: '1 000 сўм',
      photoUrl: '',
      seller: 'Сотувчи',
      market: market,
      category: '',
      submittedAt: at,
    );

void main() {
  group('соф мантиқ', () {
    test('манба → коллекция (сервер COLLECTIONS билан бир хил)', () {
      expect({for (final s in ListingModSource.values) s.collection},
          {'tv_shop_items', 'wholesale_products', 'realty_listings', 'ads'});
    });

    test('fromRaw: ҳар манбанинг майдонлари; submittedAt йўқ — createdAt; бузилган тур — бўш', () {
      final t1 = DateTime.utc(2026, 11, 15, 10);
      final t0 = DateTime.utc(2026, 11, 14, 10);
      final shop = listingModItemFromRaw(ListingModSource.shop, 's1', {
        'title': 'Олма', 'price': 12000, 'priceUnit': 'kg', 'photoUrls': ['', 'https://p/1.jpg'],
        'ownerName': 'Ali', 'market': 'farm', 'submittedAt': Timestamp.fromDate(t1), 'createdAt': Timestamp.fromDate(t0),
      });
      expect((shop.title, shop.photoUrl, shop.seller, shop.market), ('Олма', 'https://p/1.jpg', 'Ali', 'farm'));
      expect(shop.priceText, endsWith('/ kg'));
      expect(shop.submittedAt, t1.toLocal());

      final w = listingModItemFromRaw(ListingModSource.china, 'w1', {
        'title': 'Телефон', 'sellerCompanyName': 'Sun', 'market': 'china', 'imageUrls': ['https://p/w.jpg'],
        'priceTiers': [{'minQty': 1, 'price': 9000}], 'unit': 'дона', 'currency': r'$', 'createdAt': Timestamp.fromDate(t0),
      });
      expect((w.title, w.seller, w.market, w.photoUrl), ('Телефон', 'Sun', 'china', 'https://p/w.jpg'));
      expect(w.submittedAt, t0.toLocal());

      final r = listingModItemFromRaw(ListingModSource.realty, 'r1', {'title': 'Уй', 'priceText': '50 000 \$', 'ownerName': 'Vali', 'imageUrls': []});
      expect((r.title, r.priceText, r.seller, r.photoUrl, r.submittedAt), ('Уй', '50 000 \$', 'Vali', '', null));

      final a = listingModItemFromRaw(ListingModSource.ads, 'a1', {'title': 7, 'price': 'x', 'sellerName': 'S', 'imageUrls': 'bad'});
      expect((a.title, a.priceText, a.photoUrl), ('', '', ''));
    });

    test('Улгуржи/Хитой ажратиш (market йўқ — Улгуржи); ads фақат cheap_product', () {
      expect(listingModMatchesSource(ListingModSource.wholesale, {}), isTrue);
      expect(listingModMatchesSource(ListingModSource.china, {}), isFalse);
      expect(listingModMatchesSource(ListingModSource.china, {'market': 'china'}), isTrue);
      expect(listingModMatchesSource(ListingModSource.wholesale, {'market': 'china'}), isFalse);
      expect(listingModMatchesSource(ListingModSource.ads, {'type': 'cheap_product'}), isTrue);
      expect(listingModMatchesSource(ListingModSource.ads, {'type': 'job'}), isFalse);
    });

    test('навбат: аввал юборилгани биринчи, вақтсиз — охирида', () {
      final out = sortListingModItems([
        _li('c'),
        _li('b', at: DateTime(2026, 11, 15)),
        _li('a', at: DateTime(2026, 11, 14)),
      ]);
      expect(out.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('сабаб: бўш/фақат бўшлиқ/301 — рад; 1 ва 300 — қабул', () {
      expect(listingRejectReasonValid(null), isFalse);
      expect(listingRejectReasonValid('   '), isFalse);
      expect(listingRejectReasonValid('x'), isTrue);
      expect(listingRejectReasonValid('x' * 300), isTrue);
      expect(listingRejectReasonValid('x' * 301), isFalse);
    });

    test('сервис: сабабсиз рад этиш callable чақирмасдан REASON_REQUIRED', () async {
      final s = AdminListingModerationService();
      await expectLater(
        s.moderate(source: ListingModSource.shop, id: 'x', approve: false, reason: ' '),
        throwsA(isA<AdminCallableException>().having((e) => e.reason, 'reason', 'REASON_REQUIRED')),
      );
    });

    test('хато матни: код кўринади, stack trace йўқ', () {
      expect(listingModErrorText(const AdminCallableException('failed-precondition', 'LISTING_NOT_PENDING', 'raw')),
          contains('(LISTING_NOT_PENDING)'));
      expect(listingModErrorText(const AdminCallableException('permission-denied', '', 'raw')), contains('Рухсат йўқ'));
      expect(listingModErrorText(StateError('boom')), 'Амал бажарилмади. Қайта уриниб кўринг. (CLIENT_ERROR)');
    });
  });

  group('тузатиб тасдиқлаш — соф мантиқ', () {
    final orig = ListingModItem(
      source: ListingModSource.shopRejected,
      id: 'r1',
      title: 'Сигир',
      priceText: '',
      photoUrl: 'p1',
      seller: '',
      market: 'livestock',
      category: 'cow',
      categoryValue: 'cow',
      submittedAt: null,
      description: 'эски',
      price: 500,
      priceUnit: '',
      photoUrls: const ['p1', 'p2', 'p3'],
      rejectReason: 'Расм',
    );
    ListingEditResult b({
      String? title,
      String? description,
      String? price,
      String? unit,
      String? category,
      List<String>? photos,
      ListingModItem? item,
    }) =>
        buildListingEdits(
          item ?? orig,
          title: title ?? orig.title,
          description: description ?? orig.description,
          priceText: price ?? '${orig.price}',
          priceUnit: unit ?? orig.priceUnit,
          category: category ?? orig.categoryValue,
          keptPhotos: photos ?? orig.photoUrls,
        );

    test('ўзгармаса — бўш edits; фақат ўзгарганлари юборилади (trim, нарх бўшлиқ билан, тартиб сақланади)', () {
      expect(b().edits, isEmpty);
      expect(b().ok, isTrue);
      final r = b(title: '  Сигир соғин ', description: 'янги', price: '7 000 000', unit: 'ton', category: 'heifer', photos: ['p3', 'p1']);
      expect(r.ok, isTrue);
      expect(r.edits, {
        'title': 'Сигир соғин',
        'description': 'янги',
        'price': 7000000,
        'priceUnit': 'ton',
        'category': 'heifer',
        'photoUrls': ['p1', 'p3'],
      });
    });

    test('negative: бўш сарлавҳа, 201 белги, нарх матн/каср/манфий/10 рақам, бегона расм, бўлим marketсиз', () {
      expect(b(title: '   ').error, contains('Сарлавҳа'));
      expect(b(title: 'x' * 201).ok, isFalse);
      expect(b(description: 'x' * 2001).ok, isFalse);
      for (final p in ['abc', '1.5', '-1', '', '1000000000']) {
        expect(b(price: p).error, contains('Нарх'), reason: p);
      }
      expect(b(unit: 'tonna').ok, isFalse);
      expect(b(photos: ['p1', 'https://evil/x.jpg']).error, contains('Расмлар'));
      expect(b(photos: ['p1', 'p1', 'p2']).ok, isFalse);
      final noMarket = ListingModItem(
        source: ListingModSource.shop, id: 'x', title: 'a', priceText: '', photoUrl: '', seller: '', market: '',
        category: 'product', submittedAt: null,
      );
      expect(buildListingEdits(noMarket, title: 'a', description: '', priceText: '0', priceUnit: '', category: 'cow', keptPhotos: const []).ok,
          isFalse);
      expect(b(category: '').ok, isFalse, reason: 'бўлимни ўчириб бўлмайди');
    });

    test('boundary: 200 / 2000 / 999999999 / барча расм олинади — ўтади', () {
      final r = b(title: 't' * 200, description: 'd' * 2000, price: '999999999', photos: const []);
      expect(r.ok, isTrue);
      expect(r.edits['photoUrls'], isEmpty);
      expect(r.edits['price'], 999999999);
    });

    test('fromRaw (рад этилганлар): description, price, unit, photoUrls айнан, rejectReason, categoryValue', () {
      final it = listingModItemFromRaw(ListingModSource.shopRejected, 'r', {
        'title': 'A', 'description': 'D', 'price': 10, 'priceUnit': 'kg', 'photoUrls': ['u1', '', 3, 'u2'],
        'rejectReason': 'R', 'kind': 'product',
      });
      expect((it.description, it.price, it.priceUnit, it.rejectReason, it.categoryValue, it.category),
          ('D', 10, 'kg', 'R', '', 'product'));
      expect(it.photoUrls, ['u1', 'u2']);
    });

    test('taxonomy → бўлимлар (all ташланади, номи uz_Cyrl); бузилган шакл — бўш', () {
      final m = listingModCategoriesFromTaxonomy({
        'markets': {
          'livestock': {
            'categories': [
              {'id': 'all', 'names': {'uz_Cyrl': 'Барчаси'}},
              {'id': 'cow', 'names': {'uz_Cyrl': 'Қорамол'}},
              {'id': 'sheep'},
            ],
          },
          'bad': 'x',
        },
      });
      expect(m.keys, ['livestock']);
      expect(m['livestock']!.map((c) => '${c.id}:${c.name}'), ['cow:Қорамол', 'sheep:sheep']);
      expect(listingModCategoriesFromTaxonomy(null), isEmpty);
      expect(listingModCategoriesFromTaxonomy({'markets': []}), isEmpty);
    });

    test('сервис payload: approve+edits; бўш edits юборилмайди; reject да edits йўқ', () {
      expect(
        listingModPayload(source: ListingModSource.shopRejected, id: 'r1', approve: true, edits: {'price': 5}),
        {'collection': 'tv_shop_items', 'id': 'r1', 'decision': 'approve', 'edits': {'price': 5}},
      );
      expect(listingModPayload(source: ListingModSource.shop, id: 's', approve: true, edits: {}),
          {'collection': 'tv_shop_items', 'id': 's', 'decision': 'approve'});
      expect(listingModPayload(source: ListingModSource.shop, id: 's', approve: false, reason: ' r ', edits: {'a': 1}),
          {'collection': 'tv_shop_items', 'id': 's', 'decision': 'reject', 'reason': 'r'});
    });

    test('сервис: edits Улгуржида / reject билан — callable чақирмасдан рад', () async {
      final s = AdminListingModerationService();
      await expectLater(
        s.moderate(source: ListingModSource.wholesale, id: 'w', approve: true, edits: {'title': 'x'}),
        throwsA(isA<AdminCallableException>().having((e) => e.reason, 'reason', 'EDITS_NOT_SUPPORTED')),
      );
      await expectLater(
        s.moderate(source: ListingModSource.shop, id: 's', approve: false, reason: 'r', edits: {'title': 'x'}),
        throwsA(isA<AdminCallableException>().having((e) => e.reason, 'reason', 'EDITS_REQUIRE_APPROVE')),
      );
    });

    test('манбалар: рад этилганлар — status rejected, рад этиш тугмасиз; фақат tv_shop_items тузатилади', () {
      expect(ListingModSource.shopRejected.status, 'rejected');
      expect(ListingModSource.shopRejected.canReject, isFalse);
      expect(ListingModSource.shop.status, 'pending');
      expect([for (final s in ListingModSource.values) if (s.editable) s], [ListingModSource.shop, ListingModSource.shopRejected]);
      expect(listingModErrorText(const AdminCallableException('invalid-argument', 'INVALID_EDITS', 'raw')), contains('(INVALID_EDITS)'));
    });
  });

  group('экран', () {
    late List<String> calls;
    late Map<ListingModSource, List<ListingModItem>> data;
    late StreamController<bool> autoCtrl;
    Object? failWith;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListingModerationScreen(
            loadPending: (s) async => List.of(data[s] ?? const []),
            moderate: (s, id, {required approve, reason}) async {
              calls.add('${s.collection}:$id:${approve ? 'approve' : 'reject'}:${reason ?? '-'}');
              final f = failWith;
              if (f != null) throw f;
            },
            editApprove: (s, id, edits) async {
              calls.add('${s.collection}:$id:edit:${edits.keys.join(',')}:${edits['price'] ?? '-'}:${edits['photoUrls'] ?? '-'}');
              final f = failWith;
              if (f != null) throw f;
            },
            loadCategories: () async => {
              'livestock': const [ListingModCategory('cow', 'Қорамол'), ListingModCategory('heifer', 'Ғунажин')],
            },
            watchShopAutoApprove: () => autoCtrl.stream,
            setShopAutoApprove: (enabled) async {
              calls.add('auto:$enabled');
              final f = failWith;
              if (f != null) throw f;
              autoCtrl.add(enabled);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    ListingModItem rejected(String id) => ListingModItem(
          source: ListingModSource.shopRejected,
          id: id,
          title: 'Сигир $id',
          priceText: '',
          photoUrl: '',
          seller: '',
          market: 'livestock',
          category: 'cow',
          categoryValue: 'cow',
          submittedAt: null,
          price: 500,
          photoUrls: const ['https://p/1.jpg', 'https://p/2.jpg'],
          rejectReason: 'Нарх нотўғри',
        );

    testWidgets('рад этилганлар таби: сабаб кўринади, рад этиш тугмаси йўқ; тузатиш → нарх, ton, бўлим чипи, расм олиш → edits', (tester) async {
      data[ListingModSource.shopRejected] = [rejected('r1')];
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('lmod_tab_shopRejected')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lmod_card_r1')), findsOneWidget);
      expect(find.text('Рад этиш сабаби: Нарх нотўғри'), findsOneWidget);
      expect(find.byKey(const ValueKey('lmod_reject_r1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('lmod_edit_r1')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      // Нотўғри нарх — диалог ёпилмайди, чақирув йўқ.
      await tester.enterText(find.byKey(const ValueKey('ledit_price')), '12abc');
      await tester.tap(find.byKey(const ValueKey('ledit_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ledit_error')), findsOneWidget);
      expect(calls, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('ledit_price')), '7 000 000');
      await tester.tap(find.byKey(const ValueKey('ledit_unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('тонна').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ledit_cat_heifer')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ledit_photo_0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ledit_submit')));
      await tester.pumpAndSettle();
      expect(calls, ['tv_shop_items:r1:edit:price,priceUnit,category,photoUrls:7000000:[https://p/2.jpg]']);
      expect(find.byKey(const ValueKey('lmod_card_r1')), findsNothing, reason: 'оптимистик олиб ташланди');
    });

    testWidgets('тузатиш хатоси — карточка жойига қайтади, код кўринади; бекор — чақирув йўқ', (tester) async {
      data[ListingModSource.shop] = [rejected('s9')];
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('lmod_edit_s9')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Бекор'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      failWith = const AdminCallableException('invalid-argument', 'INVALID_EDITS', 'raw');
      await tester.tap(find.byKey(const ValueKey('lmod_edit_s9')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ledit_title')), 'Янги сарлавҳа');
      await tester.tap(find.byKey(const ValueKey('ledit_submit')));
      await tester.pumpAndSettle();
      expect(calls.single, startsWith('tv_shop_items:s9:edit:title:'));
      expect(find.byKey(const ValueKey('lmod_card_s9')), findsOneWidget);
      expect(find.textContaining('INVALID_EDITS'), findsOneWidget);
    });

    testWidgets('Улгуржи карточкасида «Тузатиш ва тасдиқлаш» йўқ', (tester) async {
      data[ListingModSource.wholesale] = [_li('w1', s: ListingModSource.wholesale)];
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('lmod_tab_wholesale')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lmod_card_w1')), findsOneWidget);
      expect(find.byKey(const ValueKey('lmod_edit_w1')), findsNothing);
    });

    setUp(() {
      calls = [];
      failWith = null;
      autoCtrl = StreamController<bool>.broadcast();
      data = {
        ListingModSource.shop: [
          _li('s1', at: DateTime(2026, 11, 15, 9), market: 'farm'),
          _li('s2', at: DateTime(2026, 11, 15, 10)),
        ],
      };
    });

    testWidgets('рад этиш: сабабсиз тасдиқ тугмаси ўчиқ; бекор — чақирув йўқ; сабаб билан — reject', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('lmod_reject_s1')));
      await tester.pumpAndSettle();
      final confirm = find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Рад этиш'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'сабаб мажбурий');
      await tester.tap(find.text('Бекор'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.byKey(const ValueKey('lmod_card_s1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lmod_reject_s1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '  Расм сифатсиз ');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(calls, ['tv_shop_items:s1:reject:Расм сифатсиз']);
      expect(find.byKey(const ValueKey('lmod_card_s1')), findsNothing, reason: 'оптимистик олиб ташланди');
    });

    testWidgets('тасдиқлаш: рўйхатдан олинади; хато — жойига қайтади ва код кўрсатилади', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('lmod_approve_s2')));
      await tester.pumpAndSettle();
      expect(calls, ['tv_shop_items:s2:approve:-']);
      expect(find.byKey(const ValueKey('lmod_card_s2')), findsNothing);

      failWith = const AdminCallableException('failed-precondition', 'LISTING_NOT_PENDING', 'raw');
      await tester.tap(find.byKey(const ValueKey('lmod_approve_s1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lmod_card_s1')), findsOneWidget, reason: 'хатода қайтди');
      expect(find.textContaining('LISTING_NOT_PENDING'), findsOneWidget);
    });

    testWidgets('бозор чипи: market бор ҳужжатлар бўйича фильтр', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('lmod_market_farm')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lmod_market_farm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lmod_card_s1')), findsOneWidget);
      expect(find.byKey(const ValueKey('lmod_card_s2')), findsNothing);
    });

    testWidgets('«Авто тасдиқ / Қўлда»: майдон йўқ — Қўлда; Автога тасдиқ диалоги (бекор — ёзилмайди); Қўлдага дарҳол', (tester) async {
      await pump(tester);
      // Ҳужжатда майдон йўқ (оқим ҳали ҳеч нарса бермаган) — Қўлда.
      expect(find.byKey(const ValueKey('lmod_auto_bar')), findsOneWidget);
      expect(find.textContaining('Қўлда тасдиқ'), findsOneWidget);
      expect(find.textContaining('бозорлардаги янги ва таҳрирланган'), findsOneWidget);
      final manualBtn = find.byKey(const ValueKey('lmod_auto_manual'));
      final autoBtn = find.byKey(const ValueKey('lmod_auto_on'));
      expect(tester.widget<OutlinedButton>(manualBtn).onPressed, isNull);

      await tester.tap(autoBtn);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lmod_auto_confirm')), findsOneWidget);
      await tester.tap(find.text('Бекор'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'бекор — ёзилмайди');

      await tester.tap(autoBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lmod_auto_confirm')));
      await tester.pumpAndSettle();
      expect(calls, ['auto:true']);
      expect(find.textContaining('Авто тасдиқ'), findsWidgets);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('lmod_auto_on'))).onPressed, isNull);

      // Қўлдага қайтиш — диалогсиз.
      await tester.tap(find.byKey(const ValueKey('lmod_auto_manual')));
      await tester.pumpAndSettle();
      expect(calls, ['auto:true', 'auto:false']);
      expect(find.textContaining('Қўлда тасдиқ'), findsOneWidget);
    });

    testWidgets('«Авто тасдиқ»: ёзиш хатоси — код кўринади, ҳолат Қўлда қолади', (tester) async {
      await pump(tester);
      autoCtrl.add(false);
      await tester.pump();
      failWith = StateError('boom');
      await tester.tap(find.byKey(const ValueKey('lmod_auto_on')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lmod_auto_confirm')));
      await tester.pumpAndSettle();
      expect(calls, ['auto:true']);
      expect(find.textContaining('CLIENT_ERROR'), findsOneWidget);
      expect(find.textContaining('Қўлда тасдиқ'), findsOneWidget);
    });

    testWidgets('бошқа таб (Хитой) ўз манбасини юклайди; бўш — матн', (tester) async {
      data[ListingModSource.china] = [_li('c1', s: ListingModSource.china)];
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('lmod_tab_china')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lmod_card_c1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lmod_tab_realty')));
      await tester.pumpAndSettle();
      expect(find.text('Текширувни кутаётган эълон йўқ'), findsOneWidget);
    });
  });
}
