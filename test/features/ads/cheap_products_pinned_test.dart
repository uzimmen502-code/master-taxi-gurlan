// Асосий экрандаги «Аралаш бозор» карточкаси босилса — бозор рўйхати очилади,
// босилган эълон биринчи ўринда (эга, 2026-11-03).
import 'package:ava_gurlan/features/ads/screens/cheap_products_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String id(String s) => s.split(':').first;

  test('босилган эълон биринчи ўринда, қолган тартиб сақланади', () {
    expect(withPinnedFirst(['a:1', 'b:1', 'c:1'], 'c:1', id), ['c:1', 'a:1', 'b:1']);
  });

  test('рўйхатда ID такрорланмайди (сервердаги нусха олиб ташланади)', () {
    final out = withPinnedFirst(['a:old', 'b:old', 'c:old'], 'b:new', id);
    expect(out, ['b:new', 'a:old', 'c:old']);
    expect(out.where((e) => id(e) == 'b').length, 1);
  });

  test('рўйхатда йўқ бўлса ҳам кўринади (ҳудуд фильтри уни яширмайди)', () {
    expect(withPinnedFirst(['a', 'b'], 'z', id), ['z', 'a', 'b']);
    expect(withPinnedFirst(<String>[], 'z', id), ['z']);
  });

  test('pinned йўқ (қидирув ёки оддий очилиш) — рўйхат ўзгармайди', () {
    final list = ['a', 'b'];
    expect(identical(withPinnedFirst<String>(list, null, id), list), isTrue);
  });

  test('ID null бўлган элементлар (платформа/дўкон катаклари) тегилмайди', () {
    String? adId(String s) => s.startsWith('ad:') ? s.substring(3) : null;
    final grid = ['p:1', 'ad:7', 's:2', 'ad:9'];
    expect(withPinnedFirst(grid, 'ad:9', adId), ['ad:9', 'p:1', 'ad:7', 's:2']);
  });
}
