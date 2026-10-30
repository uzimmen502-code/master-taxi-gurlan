import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_item_detail_screen.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_item_swipe_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Аҳоли бозори дўкон маҳсулоти (эга, 2026-10-31): эълонлардагидек
/// маҳсулотдан маҳсулотга свайп; ўхшашлар бўлса саҳифа «чўзилмайди».
TvShopItem _item(String id, String title, {String owner = '998901111111'}) =>
    TvShopItem(
      id: id,
      ownerPhone: owner,
      ownerName: 'x',
      title: title,
      price: 1000,
      photoUrl: '',
      kind: 'product',
      districtId: 'd',
      districtLabel: '',
      status: 'active',
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(400 * 2, 800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

void main() {
  // Номлари бир сўзли умумий «кўйлак» — бир-бирига «ўхшаш» (similarItems).
  final items = [
    _item('a', 'Қизил кўйлак'),
    _item('b', 'Кўк кўйлак'),
    _item('c', 'Оқ кўйлак'),
  ];
  Future<TvShopItem?> latest(String id) async =>
      items.firstWhere((i) => i.id == id);

  testWidgets('«›» тугмаси кейинги маҳсулотни очади, ҳисоблагич 2 / 3',
      (tester) async {
    await _pump(
      tester,
      TvShopItemSwipeScreen(items: items, initialIndex: 0, loadLatest: latest),
    );
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ad-swipe-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Кўк кўйлак'), findsOneWidget);
  });

  testWidgets('саҳифа охирида юқорига суриш — кейинги маҳсулот (ўхшашлар билан)',
      (tester) async {
    await _pump(
      tester,
      TvShopItemSwipeScreen(
        items: items,
        initialIndex: 0,
        similarPool: items,
        loadLatest: latest,
      ),
    );
    expect(find.byKey(const ValueKey('shop_item_similar')), findsOneWidget,
        reason: 'ўхшашлар бор — саҳифа экрандан узун');
    final list = find.byType(ListView).first;
    // 1-свайп: охиригача айлантиради (ўхшашлар саҳифани узайтиради).
    await tester.drag(list, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget,
        reason: 'ўртадан бошланган свайп ўтказмайди — фақат охиригача');
    // 2-свайп охиридан бошланади — кейингига ўтади.
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('чўзилиш (stretch) эффекти йўқ — алоҳида экранда ҳам',
      (tester) async {
    await _pump(
      tester,
      TvShopItemDetailScreen(
        item: items.first,
        similarPool: items,
        loadLatest: latest,
      ),
    );
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
  });

  testWidgets('битта маҳсулот — свайп тугмалари йўқ', (tester) async {
    await _pump(
      tester,
      TvShopItemSwipeScreen(
        items: [items.first],
        initialIndex: 0,
        loadLatest: latest,
      ),
    );
    expect(find.byKey(const ValueKey('ad-swipe-next')), findsNothing);
    expect(find.widgetWithText(AppBar, 'Қизил кўйлак'), findsOneWidget);
  });
}
