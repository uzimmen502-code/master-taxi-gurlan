// Эга 2026-11-19 (тезлик): Аралаш рўйхати эълонлар оқимини кутмайди — қайси манба аввал келса, шу кўрсатилади.
import 'dart:io';

import 'package:ava_gurlan/features/ads/screens/cheap_products_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AralashListView v({
    bool waiting = false,
    bool error = false,
    int ads = 0,
    int others = 0,
    bool platform = true,
    bool shop = true,
  }) =>
      aralashListView(
        adsWaiting: waiting,
        adsError: error,
        ads: ads,
        others: others,
        platformLoaded: platform,
        shopLoaded: shop,
      );

  test('эълонлар кутилмоқда, дўкон маҳсулотлари бор — рўйхат (спиннер эмас)', () {
    expect(v(waiting: true, others: 3), AralashListView.list);
    expect(v(waiting: true, others: 3, platform: false), AralashListView.list);
  });
  test('ҳеч нарса йўқ, бирор манба кутилмоқда — юкланиш', () {
    expect(v(waiting: true), AralashListView.loading);
    expect(v(shop: false), AralashListView.loading);
    expect(v(platform: false), AralashListView.loading);
  });
  test('эълонлар хатоси: бошқа манба бўлса — рўйхат; бўлмаса — хато', () {
    expect(v(error: true, others: 1), AralashListView.list);
    expect(v(error: true), AralashListView.error);
    expect(v(error: true, shop: false), AralashListView.error);
  });
  test('ҳаммаси келди, бўш — бўш; фақат эълонлар — рўйхат (чегара)', () {
    expect(v(), AralashListView.empty);
    expect(v(ads: 1), AralashListView.list);
  });
  test('экран шу функцияни ишлатади ва уй кешидан дарҳол чизади', () {
    final src = File('lib/features/ads/screens/cheap_products_screen.dart').readAsStringSync();
    expect(src.contains('final view = aralashListView('), isTrue);
    expect(src.contains('HomeShopFeed.cachedItems()'), isTrue);
    expect(src.contains('return const Center(child: CircularProgressIndicator());\n                }\n                if (snap.hasError) {'),
        isFalse);
  });
}
