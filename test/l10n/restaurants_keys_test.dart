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
}
