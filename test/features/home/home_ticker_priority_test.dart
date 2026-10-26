import 'dart:math' as math;

import 'package:ava_gurlan/features/home/widgets/home_info_ticker.dart';
import 'package:ava_gurlan/models/home_ticker_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Бош экран баннери: «Устуворлик» ишлайди (эга, 2026-10-26: «ишлайдиган қил»).
HomeTickerAd _ad(String id, int priority, [String? text]) => HomeTickerAd(
      id: id, text: text ?? 'Матн $id', audience: 'all', durationSec: 6, scrollSpeed: 45,
      animationStyle: 'auto', fontSize: 13, priority: priority, active: true,
    );

String _shown(WidgetTester t) =>
    t.widget<RichText>(find.descendant(of: find.byType(HomeInfoTicker), matching: find.byType(RichText))).text.toPlainText();

Widget _app(List<HomeTickerAd> ads, {int seed = 1}) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 360, child: HomeInfoTicker(ads: ads, random: math.Random(seed)))),
    );

void main() {
  group('displayOrder', () {
    test('юқори устуворлик аввал, тенглари гуруҳ ичида; ҳеч бири йўқолмайди', () {
      final ads = [_ad('a', 0), _ad('b', 50), _ad('c', 0), _ad('d', 100), _ad('e', 50)];
      final o = HomeInfoTicker.displayOrder(ads, math.Random(7)).map((a) => a.priority).toList();
      expect(o, [100, 50, 50, 0, 0]);
      expect(HomeInfoTicker.displayOrder(ads, math.Random(7)).map((a) => a.id).toSet(), {'a', 'b', 'c', 'd', 'e'});
    });

    test('ҳамма 0 (ҳозирги маълумот) — тўлиқ аралаш, аввалгидек', () {
      final ads = [for (var i = 0; i < 12; i++) _ad('x$i', 0)];
      final orders = {for (var s = 0; s < 6; s++) HomeInfoTicker.displayOrder(ads, math.Random(s)).map((a) => a.id).join(',')};
      expect(orders.length, greaterThan(1), reason: 'тенг устуворликда тартиб тасодифий');
      expect(HomeInfoTicker.displayOrder(ads, math.Random(3)), hasLength(12));
    });

    test('кириш рўйхати ўзгармайди', () {
      final ads = [_ad('a', 0), _ad('b', 9)];
      HomeInfoTicker.displayOrder(ads, math.Random(1));
      expect(ads.map((a) => a.id), ['a', 'b']);
    });
  });

  testWidgets('ҳар матн 5 сония (эга, 2026-10-26): 3 сонияда ҳали алмашмайди, 5 сонияда алмашади', (t) async {
    expect(HomeInfoTicker.textInterval, const Duration(seconds: 5));
    await t.pumpWidget(_app([_ad('a', 90, 'Биринчи'), _ad('b', 0, 'Иккинчи')]));
    expect(_shown(t), 'БИРИНЧИ');
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(_shown(t), 'БИРИНЧИ', reason: 'аввал 3 сонияда алмашарди');
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(_shown(t), 'ИККИНЧИ');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('биринчи кўрсатиладиган — энг юқори устуворлик; кейин навбат билан', (t) async {
    await t.pumpWidget(_app([_ad('a', 0, 'Паст'), _ad('b', 90, 'Юқори'), _ad('c', 40, 'Ўрта')]));
    expect(_shown(t), 'ЮҚОРИ');
    await t.pump(HomeInfoTicker.textInterval);
    await t.pumpAndSettle();
    expect(_shown(t), 'ЎРТА');
    await t.pump(HomeInfoTicker.textInterval);
    await t.pumpAndSettle();
    expect(_shown(t), 'ПАСТ');
  });

  testWidgets('ота виджет янги рўйхат объекти билан қайта чизса (ўша матнлар) — кўрсатилаётган матн сакрамайди', (t) async {
    final ads = [for (var i = 0; i < 8; i++) _ad('x$i', 0, 'Матн $i')];
    await t.pumpWidget(_app(ads));
    await t.pump(HomeInfoTicker.textInterval);
    await t.pumpAndSettle();
    final before = _shown(t);
    await t.pumpWidget(_app(List.of(ads.reversed)));
    expect(_shown(t), before);
    // Матн таҳрирланди (id ва устуворлик ўша) — ўрни сақланади, янги матн кўринади.
    final edited = [for (final a in ads) a.id == ads.firstWhere((x) => 'МАТН ${x.id.substring(1)}' == before).id ? _ad(a.id, 0, 'Таҳрир') : a];
    await t.pumpWidget(_app(edited));
    expect(_shown(t), 'ТАҲРИР');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('устуворлик ўзгарса — тартиб қайта ҳисобланади, янги энг юқориси биринчи', (t) async {
    await t.pumpWidget(_app([_ad('a', 0, 'Бир'), _ad('b', 0, 'Икки')]));
    await t.pumpWidget(_app([_ad('a', 0, 'Бир'), _ad('b', 80, 'Икки')]));
    expect(_shown(t), 'ИККИ');
    await t.pumpWidget(const SizedBox());
  });
}
