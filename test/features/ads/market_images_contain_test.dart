import 'dart:io';

import 'package:ava_gurlan/features/ads/widgets/ad_image_slider.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_product_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Аҳоли / Улгуржи / Хитой бозори: катта расм четлари ҚИРҚИЛМАЙДИ — катакка
/// сиғиб кичраяди (`BoxFit.contain`), бўш жойни фон тўлдиради
/// (эга қарори 2026-10-19).
///
/// Иккита қулф: (1) Firebase'сиз пумплаш мумкин виджетлар — ҳақиқий `fit`
/// текширилади; (2) қолган жойлар учун МАНБА-даражадаги сканер (виджет
/// Firebase/плагин талаб қилади) — бу файллар қайта `BoxFit.cover`
/// қилинса тест қизил бўлади.
void main() {
  group('виджет: fit == contain', () {
    testWidgets('AdImageSlider (Аҳоли/Улгуржи тафсилот) — contain + фон',
        (tester) async {
      const bg = Color(0xFF123456);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdImageSlider(
              imageUrls: ['https://example.invalid/a.jpg'],
              height: 200,
              backgroundColor: bg,
            ),
          ),
        ),
      );
      final img =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(img.fit, BoxFit.contain);
      final box = tester.widget<ColoredBox>(find.ancestor(
        of: find.byType(CachedNetworkImage),
        matching: find.byType(ColoredBox),
      ).first);
      expect(box.color, bg, reason: 'contain четидаги фон берилган ранг');
    });

    testWidgets('WholesaleProductCard (Улгуржи/Хитой катак) — contain + фон',
        (tester) async {
      const p = WholesaleProduct(
        id: 'p',
        sellerId: 's',
        sellerCompanyName: 'Фирма',
        title: 'Помидор',
        titleLower: 'помидор',
        description: '',
        imageUrls: ['https://example.invalid/a.jpg'],
        priceTiers: [PriceTier(minQty: 1, price: 14000)],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 300,
              child: WholesaleProductCard(product: p, onTap: () {}),
            ),
          ),
        ),
      );
      final img = tester.widget<Image>(find.byType(Image).first);
      expect(img.fit, BoxFit.contain);
      expect(
        find.ancestor(of: find.byType(Image), matching: find.byType(ColoredBox)),
        findsWidgets,
        reason: 'расм остида фон бўлиши шарт',
      );
    });
  });

  group('манба сканери: бозор расмларида BoxFit.cover қолмаган', () {
    // Фақат Аҳоли / Улгуржи / Хитой бозори эълон-товар расмлари.
    // ATАЙЛАБ кирмайдиган: аватар, ресторан, танишув, TV/AVAGram,
    // баннер/логотип, home_global_search (аралаш қидирув миниатюраси),
    // admin_web модерация экранлари.
    const files = <String>[
      'lib/features/ads/widgets/platform_market_card.dart',
      'lib/features/ads/widgets/ad_card.dart',
      'lib/features/ads/widgets/ad_image_slider.dart',
      'lib/features/ads/screens/ad_details_screen.dart',
      'lib/features/ads/screens/my_ads_screen.dart',
      'lib/features/ads/screens/edit_ad_screen.dart',
      'lib/features/ads/screens/create_ad_screen.dart',
      'lib/features/wholesale/widgets/wholesale_product_card.dart',
      'lib/features/wholesale/widgets/wholesale_product_strip.dart',
      'lib/features/wholesale/screens/wholesale_market_screen.dart',
      'lib/features/wholesale/screens/wholesale_product_form_screen.dart',
      'lib/features/home/widgets/home_market_section.dart',
      'lib/features/home/widgets/home_wholesale_section.dart',
    ];

    for (final path in files) {
      test(path, () {
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: '$path топилмади');
        final src = f.readAsStringSync();
        expect(
          src.contains('BoxFit.cover'),
          isFalse,
          reason: '$path: бозор расми BoxFit.cover — четлари қирқилади. '
              'BoxFit.contain + фон ишлатинг.',
        );
      });
    }
  });
}
