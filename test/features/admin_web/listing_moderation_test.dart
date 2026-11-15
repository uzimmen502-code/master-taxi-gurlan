// «Эълонлар модерацияси» (Бозорлар 2b, эга 2026-11-15): соф мантиқ ва экран (рад этиш сабабсиз юборилмайди,
// оптимистик олиб ташлаш, хатода жойига қайтиш + код).

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

  group('экран', () {
    late List<String> calls;
    late Map<ListingModSource, List<ListingModItem>> data;
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
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() {
      calls = [];
      failWith = null;
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
