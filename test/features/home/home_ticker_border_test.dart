import 'dart:math' as math;

import 'package:ava_gurlan/features/home/widgets/home_info_ticker.dart';
import 'package:ava_gurlan/models/home_ticker_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Бош экран баннери — 3 px қора хошия (эга, 2026-10-31).
HomeTickerAd _ad(String id, String text) => HomeTickerAd(
      id: id, text: text, audience: 'all', durationSec: 6, scrollSpeed: 45,
      animationStyle: 'auto', fontSize: 13, priority: 0, active: true,
    );

Widget _app(String text, {double width = 360}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: width, child: HomeInfoTicker(ads: [_ad('a', text)], random: math.Random(1))),
      ),
    );

BoxDecoration _decoration(WidgetTester t) => t
    .widget<Container>(find.descendant(of: find.byType(HomeInfoTicker), matching: find.byType(Container)).first)
    .decoration! as BoxDecoration;

void main() {
  testWidgets('хошия: қора, 3 px, сариқ фон ва 8 px бурчак сақланган', (t) async {
    await t.pumpWidget(_app('Тошкентга такси? -- Шаҳарлараро такси!'));
    final d = _decoration(t);
    final b = d.border! as Border;
    expect(b.top.color, const Color(0xFF000000));
    expect(b.top.width, 3);
    expect(b.left.width, 3);
    expect(b.bottom.width, 3);
    expect(b.right.width, 3);
    expect(d.color, const Color(0xFFFFFF00));
    expect(d.borderRadius, BorderRadius.circular(8));
    expect(t.getSize(find.byType(HomeInfoTicker)).height, HomeInfoTicker.height, reason: 'баландлик 86 px ўзгармайди');
  });

  testWidgets('чегара: энг узун матн тор экранда ҳам тошиб кетмайди (хошия жой олади)', (t) async {
    final long = 'Иловада истаган одам - Курьер бўлиши мумкин. Курьерлик қилинг ва даромад топинг! ' * 3;
    await t.pumpWidget(_app(long, width: 300));
    expect(t.takeException(), isNull);
    final rich = t.widget<RichText>(find.descendant(of: find.byType(HomeInfoTicker), matching: find.byType(RichText)));
    expect(rich.maxLines, 4);
  });
}
