// Сават варағи ва checkout: UI/UX аудит (2026-10-24) тузатишлари қулфланади —
// −/+ тугмалари ≥44 px ва номли (tooltip), 3 тилда калитлар, иконка/матн ранглари контрасти.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ava_gurlan/core/theme/ava_tokens.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/widgets/restaurant_cart_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  const keys = ['restaurants_a11y_more', 'restaurants_a11y_utensils_less', 'restaurants_a11y_utensils_more'];

  test('3 тилда янги a11y калитлари мавжуд; {name} фақат сават тугмасида', () {
    for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final m = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
      for (final k in keys) {
        expect((m[k] as String?)?.trim() ?? '', isNotEmpty, reason: '$lang $k');
      }
      expect(m['restaurants_a11y_more'] as String, contains('{name}'), reason: lang);
      expect(m['restaurants_a11y_utensils_less'] as String, isNot(contains('{')), reason: lang);
      expect(m['restaurants_a11y_utensils_more'] as String, isNot(contains('{')), reason: lang);
    }
  });

  test('контраст: ёруғ мавзуда матн ink2 ≥4.5, иконка brandText ≥3 (оқ карточка ва крем фонда)', () {
    for (final bg in [AvaLight.surface, AvaLight.surface2]) {
      expect(_contrast(AvaLight.ink2, bg), greaterThanOrEqualTo(4.5), reason: 'ink2 матни');
    }
    expect(_contrast(AvaLight.brandText, AvaLight.surface), greaterThanOrEqualTo(3.0), reason: 'танланган radio / «+» иконкаси');
    expect(_contrast(AvaLight.ink2, AvaLight.surface), greaterThanOrEqualTo(3.0), reason: 'танланмаган radio чегараси');
    // Эски қиймат нега алмаштирилгани: ink3 матн сифатида ўтмайди, brand — иконка сифатида ҳам.
    expect(_contrast(AvaLight.ink3, AvaLight.surface), lessThan(4.5));
    expect(_contrast(AvaLight.brand, AvaLight.surface), lessThan(3.0));
  });

  group('Сават варағи: −/+ тугмалари', () {
    final plov = MenuItem.fromMap('plov', {'name': 'Plov', 'price': 35000});
    const r = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved');

    testWidgets('ҳар бири ≥44×44 ва тўлиқ номли (таом номи билан) tooltip', (t0) async {
      t0.view.physicalSize = const Size(390 * 3, 1800 * 3);
      t0.view.devicePixelRatio = 3;
      addTearDown(t0.view.reset);
      final cart = RestaurantCart()
        ..add(plov, restaurant: r)
        ..add(plov, restaurant: r);
      await t0.pumpWidget(l10nApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showRestaurantCartSheet(ctx, cart: cart, restaurant: r, onCheckout: () {}),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t0.tap(find.text('open'));
      await t0.pumpAndSettle();

      final less = tr('restaurants_a11y_remove').replaceAll('{name}', 'Plov');
      final more = tr('restaurants_a11y_more').replaceAll('{name}', 'Plov');
      for (final label in [less, more]) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
        // Босиш майдони = IconButton ўзи (Tooltip ичида — иконка + ички padding).
        final btn = find.ancestor(of: find.byTooltip(label), matching: find.byType(IconButton));
        expect(btn, findsOneWidget, reason: label);
        final size = t0.getSize(btn);
        expect(size.width, greaterThanOrEqualTo(44), reason: '$label eni');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$label balandligi');
      }

      // Таом номи — босиладиган майдон ≥44 баландликда.
      expect(t0.getSize(find.byKey(const ValueKey('cart-open-plov'))).height, greaterThanOrEqualTo(44));
    });
  });
}
