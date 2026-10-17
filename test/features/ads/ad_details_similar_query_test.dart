import 'package:ava_gurlan/features/ads/screens/ad_details_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Ўхшаш маҳсулотлар → Барчаси»: Аҳоли бозори қидирув сатри эълон номининг
/// биринчи маъноли сўзи билан очилади.
void main() {
  test('биринчи сўз (≥3 ҳарф) олинади, регистр тушади', () {
    expect(adSimilarQuery('Велосипед ёш болалар учун'), 'велосипед');
  });

  test('қисқа сўзлар ва белгилар ўтказиб юборилади', () {
    expect(adSimilarQuery('А, б — Телефон (янги)'), 'телефон');
  });

  test('лотин ва рақамлар', () {
    expect(adSimilarQuery('iPhone 13'), 'iphone');
    expect(adSimilarQuery('A1 12345'), '12345');
  });

  test('маъноли сўз йўқ — бўш (қидирув сатри бўш очилади)', () {
    expect(adSimilarQuery('А б'), '');
    expect(adSimilarQuery(''), '');
    expect(adSimilarQuery('   !!! '), '');
  });
}
