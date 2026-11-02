// «Ўхшаш маҳсулотлар» картаси — Аралаш ва Улгуржида БИР ХИЛ (эга, 2026-11-03).
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_item_detail_screen.dart';
import 'package:ava_gurlan/shared/widgets/product_mini_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TvShopItem _item(String id, String title) => TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'Дилноза дўкони',
      title: title,
      price: 25000,
      photoUrl: '',
      kind: 'product',
      districtId: 'd',
      districtLabel: '',
      status: 'active',
    );

void main() {
  testWidgets('ўлчам Улгуржиники: эни 108, лента 178 (шрифт 1.0); бўш сатр чизилмайди', (t) async {
    late double strip;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) {
          strip = ProductMiniTile.stripHeight(ctx);
          return Row(children: [
            ProductMiniTile(imageUrl: '', title: 'Ун', price: '25 000 сўм', subtitle: 'Гурлан', onTap: () {}),
            ProductMiniTile(imageUrl: '', title: 'Шакар', onTap: () {}),
          ]);
        }),
      ),
    ));
    expect(strip, 178);
    expect(t.getSize(find.byType(ProductMiniTile).first).width, 108);
    expect(find.text('25 000 сўм'), findsOneWidget);
    expect(find.text('Гурлан'), findsOneWidget);
    // Нарх ва туман йўқ — фақат ном (бўш Text йўқ).
    final second = find.byType(ProductMiniTile).last;
    expect(find.descendant(of: second, matching: find.byType(Text)), findsOneWidget);
  });

  testWidgets('катта шрифтда лента ўсади (1.6 гача) — матн қирқилмайди', (t) async {
    late double strip;
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Builder(builder: (ctx) {
        strip = ProductMiniTile.stripHeight(ctx);
        return const SizedBox();
      }),
    ));
    expect(strip, 108 + 70 * 1.6);
  });

  testWidgets('Аралаш дўкон маҳсулоти: ўхшашлар — ProductMiniTile (ном, нарх, сотувчи)', (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final pool = [_item('a', 'Қизил кўйлак'), _item('b', 'Кўк кўйлак')];
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: TvShopItemDetailScreen(item: pool.first, similarPool: pool, loadLatest: (_) async => pool.first),
    ));
    await t.pumpAndSettle();
    final tile = find.byKey(const ValueKey('shop-similar-b'));
    await t.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
    expect(tile, findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Кўк кўйлак')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Дилноза дўкони')), findsOneWidget);
    expect(t.getSize(tile).width, ProductMiniTile.width);
  });
}
