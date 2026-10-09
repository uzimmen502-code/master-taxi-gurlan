import 'dart:io';

import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// `wholesale_products.createdAt` — фақат СЕРВЕР вақти (2026-10-09).
///
/// Admin рўйхати `orderBy('createdAt')` билан ўқийди: майдонсиз ҳужжат
/// рўйхатда кўринмайди. `firestore.rules` энди `createdAt == request.time`
/// ни талаб қилади — илова `FieldValue.serverTimestamp()` юборишда давом
/// этиши шарт, акс ҳолда сотувчи маҳсулот қўша олмай қолади. Таҳрир
/// эса `createdAt`га умуман тегмаслиги керак (rules рад этади).
/// Rules'нинг ўзи — emulator тести
/// `functions/test/wholesale_products_rules.test.js`.
WholesaleProduct _p({String market = WholesaleProduct.marketWholesale}) =>
    WholesaleProduct(
      id: '',
      sellerId: '998901234567',
      sellerCompanyName: 'Sunlight',
      title: 'трактор',
      titleLower: 'трактор',
      description: 'янги трактор',
      priceTiers: const [WholesalePriceTier(minQty: 1, price: 3800)],
      imageUrls: const ['https://example.test/a.jpg'],
      market: market,
    );

void main() {
  test('яратиш: createdAt — serverTimestamp (қўлда тасдиқ)', () {
    // Тенглик маъноли эканини текшириш: бошқа sentinel тенг эмас.
    expect(FieldValue.delete(), isNot(FieldValue.serverTimestamp()));
    final m = _p().toFirestoreCreate();
    expect(m['createdAt'], FieldValue.serverTimestamp());
    expect(m['createdAt'], isNot(isA<DateTime>()));
    expect(m['createdAt'], isNot(isA<Timestamp>()));
  });

  test('яратиш: createdAt — serverTimestamp (авто-тасдиқ, Хитой бозори)', () {
    final m = _p(market: WholesaleProduct.marketChina)
        .toFirestoreCreate(autoApproved: true);
    expect(m['createdAt'], FieldValue.serverTimestamp());
  });

  test("таҳрир: createdAt'га тегмайди (rules рад этарди)", () {
    expect(_p().toFirestoreOwnerUpdate().containsKey('createdAt'), isFalse);
    expect(
      _p(market: WholesaleProduct.marketChina)
          .toFirestoreOwnerUpdate()
          .containsKey('createdAt'),
      isFalse,
    );
  });

  test('firestore.rules: яратишда createdAt == request.time талаб қилинади', () {
    final src = File('firestore.rules').readAsStringSync();
    final start = src.indexOf('function wholesaleProductCreateOk()');
    expect(start, isNonNegative);
    final body = src.substring(start, src.indexOf('\n    }', start));
    expect(body, contains('request.resource.data.createdAt == request.time'));
  });
}
