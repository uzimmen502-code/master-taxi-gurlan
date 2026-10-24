import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/features/ads/widgets/ad_card.dart';

AdModel _ad({required int price}) => AdModel(
      id: 'a1',
      ownerId: '998900000000',
      title: 'Тест эълон',
      titleLower: 'тест эълон',
      description: 'Тавсиф',
      price: price,
      phone: '998900000000',
      sellerName: '',
      imageUrls: const [],
      status: 'active',
      views: 0,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 180, height: 260, child: child)),
    );

/// UI/UX аудити (Аҳоли бозори, 2026-10-24): `AdCard` босилганда ripple бермас
/// эди (`GestureDetector`) ва нархсиз эълонда «0 сўм» чиқарди.
void main() {
  testWidgets('AdCard: InkWell бор (босиш эффекти)', (tester) async {
    await tester.pumpWidget(_host(AdCard(ad: _ad(price: 1000))));
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('AdCard: нарх бор — нарх кўринади', (tester) async {
    await tester.pumpWidget(_host(AdCard(ad: _ad(price: 1000))));
    expect(find.textContaining('1'), findsWidgets);
    expect(find.text('Тест эълон'), findsOneWidget);
  });

  testWidgets('AdCard: нарх 0 — «0» нарх қатори чиқмайди', (tester) async {
    await tester.pumpWidget(_host(AdCard(ad: _ad(price: 0))));
    // Сарлавҳа ва тавсиф бор, нарх қатори (0 + валюта) йўқ.
    expect(find.text('Тест эълон'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^0\b')), findsNothing);
  });
}
