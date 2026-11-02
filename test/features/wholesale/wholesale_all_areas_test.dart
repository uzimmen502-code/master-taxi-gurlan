// AVA маҳсулотлари барча ҳудудларда (эга, 2026-11-03).
//
// Белги `wholesale_sellers/{phone}.allAreas == true` — ФАҚАТ админ SDK ёзади.
// Мижоз уни ўзига қўя олмаслиги қоидалардаги `hasOnly` рўйхатларига боғлиқ:
// бу тест кимдир ўша рўйхатга `allAreas` қўшиб юборса йиқилади.
import 'dart:io';

import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/repositories/platform_products_repository.dart';
import 'package:flutter_test/flutter_test.dart';

String _fn(String rules, String name) {
  final start = rules.indexOf('function $name(');
  expect(start, greaterThanOrEqualTo(0), reason: '$name топилмади');
  final end = rules.indexOf('\n    }', start);
  return rules.substring(start, end);
}

void main() {
  group('allAreas — мижоз ёза олмайди (firestore.rules)', () {
    final rules = File('firestore.rules').readAsStringSync();

    for (final name in [
      'wholesaleSellerCreateOk',
      'wholesaleSellerOwnerUpdateOk',
      // `wholesaleSellerResubmitOk` — жонли қоидаларда бор (hasOnly, allAreas йўқ —
      // 2026-11-03 қўлда текширилди), лекин hosting линиясидаги файлда ҳали йўқ.
      'wholesaleSellerApprovalPatchOnly',
      'wholesaleProductCreateOk',
      'wholesaleProductOwnerUpdateOk',
    ]) {
      test('$name: hasOnly рўйхатида allAreas йўқ', () {
        final body = _fn(rules, name);
        expect(body.contains('hasOnly('), isTrue, reason: 'калитлар чекланган бўлсин');
        expect(body.contains("'allAreas'"), isFalse);
      });
    }
  });

  test('Улгуржи экрани: ҳудуд фильтри йўқ — доим бутун мамлакат (эга 2026-11-03, «А»)', () {
    final src = File('lib/features/wholesale/screens/wholesale_market_screen.dart').readAsStringSync();
    expect(src.contains('GeoTierBar('), isFalse, reason: 'ҳудуд чиплари қайтмасин');
    expect(src.contains('getActiveProducts(market: widget.market)'), isTrue);
    expect(RegExp(r'getActiveProducts\([^)]*geo:').hasMatch(src), isFalse);
  });

  group('Аралаш бозорга чиқадиган AVA товари (marketEligible)', () {
    PlatformProduct p(String id, {bool active = true, bool market = true, int price = 1000}) =>
        PlatformProduct(id: id, name: id, price: price, active: active, showInMarket: market);

    test('фаол + «бозор» белгиси + нархи бор — чиқади; қолганлари йўқ', () {
      final out = PlatformProductsRepository.marketEligible([
        p('ok'),
        p('off', active: false),
        p('hidden', market: false),
        p('free', price: 0),
      ]);
      expect(out.map((e) => e.id), ['ok']);
    });
  });
}
