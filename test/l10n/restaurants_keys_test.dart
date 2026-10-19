// Uch til qoidasi (CLAUDE.md / xotira): `restaurants_*` va `home_*_restaurants`
// kalitlari uchala lokal faylda ham bo'lishi shart. Bu test kodda ishlatilgan
// kalitlar bilan fayllarni solishtiradi — tarjimasi unutilgan kalit CI'da
// yiqiladi, qurilmada xom kalit sifatida chiqmaydi.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('assets/lang/$name.json').readAsStringSync()) as Map<String, dynamic>;

Set<String> _keysInSource() {
  final out = <String>{};
  final re = RegExp(r"'(restaurants_[a-z0-9_]+|home_(module|section)_restaurants)'");
  for (final f in Directory('lib/features/restaurants').listSync(recursive: true).whereType<File>()) {
    for (final m in re.allMatches(f.readAsStringSync())) {
      out.add(m.group(1)!);
    }
  }
  for (final path in [
    'lib/features/home/widgets/home_restaurants_section.dart',
    'lib/features/home/home_services_catalog.dart',
    'lib/features/profile/widgets/order_card.dart',
    'lib/features/courier/screens/courier_screen.dart',
  ]) {
    for (final m in re.allMatches(File(path).readAsStringSync())) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

void main() {
  final cyrl = _load('uz_Cyrl');
  final latn = _load('uz_Latn');
  final ru = _load('ru');

  test('restaurants_* kalitlari uchala tilda bir xil to\'plam', () {
    Set<String> pick(Map<String, dynamic> m) =>
        m.keys.where((k) => k.startsWith('restaurants_') || k.endsWith('_restaurants')).toSet();
    final a = pick(cyrl);
    expect(pick(latn), a, reason: 'uz_Latn');
    expect(pick(ru), a, reason: 'ru');
    expect(a, isNotEmpty);
  });

  test('kodda ishlatilgan statik kalitlar fayllarda bor', () {
    final used = _keysInSource();
    final missing = used.where((k) => !cyrl.containsKey(k)).toList()..sort();
    expect(missing, isEmpty, reason: 'uz_Cyrl da yo\'q: $missing');
  });

  test('status va to\'lov usuli kalitlari — dinamik qurilganlar ham bor', () {
    for (final s in ['placed', 'accepted', 'ready', 'picked', 'arrived', 'delivered', 'rejected', 'cancelled', 'delivery_failed']) {
      expect(cyrl.containsKey('restaurants_status_$s'), isTrue, reason: s);
    }
    for (final p in ['prepay', 'cash_buyout', 'cash_to_restaurant']) {
      expect(cyrl.containsKey('restaurants_food_payment_$p'), isTrue, reason: p);
      expect(cyrl.containsKey('restaurants_food_payment_${p}_hint'), isTrue, reason: '$p hint');
    }
  });

  test('restoran paneli — dinamik kalitlar (status, xato, oshxona, rejim, bucket)', () {
    for (final s in ['applied', 'approved', 'rejected', 'suspended', 'closed']) {
      expect(cyrl.containsKey('restaurants_m_status_$s'), isTrue, reason: s);
    }
    for (final e in ['name', 'location', 'address', 'legal_type', 'delivery_mode', 'delivery_or_pickup', 'payment_method', 'card_number', 'prep_time', 'min_order', 'max_qty', 'own_fee', 'hours', 'item']) {
      expect(cyrl.containsKey('restaurants_m_err_$e'), isTrue, reason: e);
    }
    for (final c in ['milliy', 'fastfood', 'pizza', 'shashlik', 'sweets', 'drinks', 'home']) {
      expect(cyrl.containsKey('restaurants_cuisine_$c'), isTrue, reason: c);
    }
    for (final k in ['individual', 'yatt', 'llc']) {
      expect(cyrl.containsKey('restaurants_m_legal_$k'), isTrue, reason: k);
    }
    for (final k in ['ava', 'own', 'none']) {
      expect(cyrl.containsKey('restaurants_m_delivery_$k'), isTrue, reason: k);
    }
    for (final k in ['delivery', 'pickup', 'own']) {
      expect(cyrl.containsKey('restaurants_m_mode_$k'), isTrue, reason: k);
    }
    for (final k in ['fresh', 'active', 'history']) {
      expect(cyrl.containsKey('restaurants_m_bucket_$k'), isTrue, reason: k);
    }
  });

  test('kuryer (B3) — dinamik kalitlar: sabab, xato kodlari', () {
    for (final r in ['customer_absent', 'customer_refused', 'courier_problem', 'other']) {
      expect(cyrl.containsKey('restaurants_courier_fail_$r'), isTrue, reason: r);
    }
    for (final e in [
      'COURIER_ASSIGNMENT_CONFLICT', 'NOT_AVA_COURIER_ORDER', 'ORDER_NOT_CLAIMABLE', 'COURIER_OWN_ORDER',
      'COURIER_IS_RESTAURANT_MEMBER', 'BUYOUT_LIMIT_EXCEEDED', 'PICKUP_CODE_MISMATCH', 'PICKUP_CODE_LOCKED',
      'RESTAURANT_NOT_READY', 'USE_RESTAURANT_PICKUP', 'USE_RESTAURANT_ARRIVE', 'QTY_LIMIT_EXCEEDED',
    ]) {
      expect(cyrl.containsKey('restaurants_err_$e'), isTrue, reason: e);
    }
  });
}
