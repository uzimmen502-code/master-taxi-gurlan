import 'dart:io';

import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:flutter_test/flutter_test.dart';

/// Расмлар сони 1..7 (эга қарори, 2026-10-17): Аҳоли ва Улгуржи бозорида
/// клиент, `firestore.rules` ва `functions/market_images.js` БИР ХИЛ бўлиши
/// шарт. Биттаси орқада қолса, фойдаланувчи 6–7-расмни юклайди-ю, сервер
/// сақлашни рад этади (ёки аксинча — клиент чегараси серверникидан тор).
void main() {
  const limit = 7;

  test('клиент константалари 7', () {
    expect(AdModel.maxImages, limit);
    expect(WholesaleProduct.maxImages, limit);
  });

  test('firestore.rules: ҳар учала жойда imageUrls.size() <= 7', () {
    final rules = File('firestore.rules').readAsStringSync();
    final matches = RegExp(r'imageUrls\.size\(\)\s*<=\s*(\d+)')
        .allMatches(rules)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    // Аҳоли (таҳрир), Улгуржи (яратиш), Улгуржи (таҳрир).
    expect(matches, [limit, limit, limit]);
  });

  test('functions/market_images.js: MARKET_MAX_IMAGES = 7', () {
    final js = File('functions/market_images.js').readAsStringSync();
    final m = RegExp(r'MARKET_MAX_IMAGES\s*=\s*(\d+)').firstMatch(js);
    expect(m, isNotNull);
    expect(int.parse(m!.group(1)!), limit);
  });

  test('Улгуржи сотувчи товари: 8-расм сақлаш маплигидан кесилади', () {
    final p = WholesaleProduct(
      id: 'x',
      sellerId: 's',
      sellerCompanyName: 'c',
      title: 'Тест',
      titleLower: 'тест',
      description: 'тавсиф',
      priceTiers: const [PriceTier(minQty: 1, price: 1000)],
      imageUrls: [for (var i = 0; i < 9; i++) 'https://x/$i.jpg'],
    );
    expect((p.toFirestoreCreate()['imageUrls'] as List).length, limit);
    expect((p.toFirestoreOwnerUpdate()['imageUrls'] as List).length, limit);
  });
}
