// Аралаш бозордан Улгуржи/Хитой маҳсулоти (эга, 2026-11-13): орқага — ўша бозор,
// яна орқага — асосий экран (Аралаш стекдан олинади). Тепа ўнгда бозор белгиси.
import 'package:ava_gurlan/features/ads/screens/cheap_products_screen.dart' show withPinnedFirst;
import 'package:ava_gurlan/features/ads/widgets/market_corner_badge.dart';
import 'package:ava_gurlan/features/ads/widgets/platform_market_card.dart';
import 'package:ava_gurlan/features/home/home_market_nav.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_product_card.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('стек: Асосий → Бозор → Тафсилот; орқага бозорга, яна орқага асосий экранга', (t) async {
    final navKey = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('HOME')),
    ));
    // Асосий → Аралаш
    navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ARALASH'))));
    await t.pumpAndSettle();
    expect(find.text('ARALASH'), findsOneWidget);

    // Аралашдан Улгуржи маҳсулоти
    openDetailOverOtherMarket(
      navKey.currentState!,
      market: const Scaffold(body: Text('ULGURJI')),
      detail: MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('DETAIL'))),
    );
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);

    navKey.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.text('ULGURJI'), findsOneWidget);
    expect(find.text('ARALASH'), findsNothing, reason: 'Аралаш стекдан олинган');

    navKey.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(navKey.currentState!.canPop(), isFalse);
  });

  test('бош саҳифада босилган Хитой маҳсулоти Аралашда биринчи, такрорсиз', () {
    WholesaleProduct p(String id) => WholesaleProduct(
          id: id,
          sellerId: '998901110001',
          sellerCompanyName: 'AVA',
          title: id,
          titleLower: id,
          description: 'd',
          priceTiers: const [WholesalePriceTier(minQty: 1, price: 5)],
          market: WholesaleProduct.marketChina,
        );
    final list = [p('a'), p('b'), p('c')];
    expect(withPinnedFirst(list, p('c'), (e) => e.id).map((e) => e.id), ['c', 'a', 'b']);
    // Лентада йўқ бўлса ҳам кўринади (рўйхат ҳали юкланмаган).
    expect(withPinnedFirst(const <WholesaleProduct>[], p('x'), (e) => e.id).map((e) => e.id), ['x']);
  });

  group('бозор белгиси (тепа ўнг)', () {
    void quiet() {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed by')) return; // Ahem шрифти артефакти
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
    }

    Widget host(Widget card) => MaterialApp(
          home: Scaffold(body: Center(child: SizedBox(width: 180, height: 300, child: card))),
        );

    testWidgets('AVA карточкаси: «Улгуржи» ўнгда, «AVA» чапда; босиш — берилган onTap', (t) async {
      quiet();
      var taps = 0;
      await t.pumpWidget(host(PlatformMarketCard(
        product: const PlatformProduct(id: 'p1', name: 'Ун', price: 1000),
        cornerBadge: 'Улгуржи',
        onTap: () => taps++,
      )));
      expect(find.text('Улгуржи'), findsOneWidget);
      final right = t.getTopRight(find.byKey(const ValueKey('market_corner_badge')));
      final left = t.getTopLeft(find.byKey(const ValueKey('platform_ava_badge')));
      expect(right.dx, greaterThan(left.dx));
      await t.tap(find.byType(PlatformMarketCard));
      expect(taps, 1);
    });

    testWidgets('белги берилмаса — йўқ (Улгуржи бозорнинг ўзида)', (t) async {
      quiet();
      await t.pumpWidget(host(const PlatformMarketCard(product: PlatformProduct(id: 'p1', name: 'Ун', price: 1000))));
      expect(find.byType(MarketCornerBadge), findsNothing);
    });

    testWidgets('Хитой карточкаси: «Хитой» белгиси', (t) async {
      quiet();
      await t.pumpWidget(host(WholesaleProductCard(
        product: const WholesaleProduct(
          id: 'c1',
          sellerId: '998901110001',
          sellerCompanyName: 'AVA',
          title: 'Чой',
          titleLower: 'чой',
          description: 'd',
          priceTiers: [WholesalePriceTier(minQty: 1, price: 5)],
          market: WholesaleProduct.marketChina,
        ),
        cornerBadge: 'Хитой',
        onTap: () {},
      )));
      expect(find.text('Хитой'), findsOneWidget);
    });
  });
}
