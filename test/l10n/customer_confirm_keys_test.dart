// Mijoz tasdig'i matnlari: 3 tilda to'liq, joy egalari bir xil, ichki terminlar yo'q.
//
//   flutter test test/l10n/customer_confirm_keys_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/models/customer_confirm.dart';

const _langs = ['uz_Cyrl', 'uz_Latn', 'ru'];

Map<String, dynamic> _load(String lang) =>
    json.decode(File('assets/lang/$lang.json').readAsStringSync())
        as Map<String, dynamic>;

/// Kod ishlatadigan barcha `customer_confirm_*` kalitlari.
List<String> _usedKeys() {
  const steps = [
    CustomerConfirmStep.handoverPickup,
    CustomerConfirmStep.handoverReturn,
    CustomerConfirmStep.received,
    CustomerConfirmStep.finalize,
    'unknown_step',
  ];
  const modules = [
    CustomerConfirmModule.restaurant,
    CustomerConfirmModule.carpet,
    CustomerConfirmModule.agro,
    CustomerConfirmModule.collection,
    'unknown_module',
  ];
  return {
    for (final s in steps) customerConfirmButtonKey(s),
    for (final s in steps) customerConfirmHintKey(s),
    for (final m in modules) customerConfirmModuleKey(m),
    for (final r in ['NOT_AWAITING', 'NOT_YOUR_ORDER', 'STATE_CHANGED', ''])
      customerConfirmErrorKey(r),
    // UI'da to'g'ridan-to'g'ri ishlatiladiganlar
    'customer_confirm_title',
    'customer_confirm_empty',
    'customer_confirm_refresh',
    'customer_confirm_more',
    'customer_confirm_done',
    'customer_confirm_details_qty',
    'customer_confirm_details_amount',
    'customer_confirm_err_load',
    'customer_confirm_waiting',
    'customer_confirm_waiting_hint',
  }.toList()
    ..sort();
}

Set<String> _placeholders(String s) =>
    RegExp(r'\{[a-zA-Z]+\}').allMatches(s).map((m) => m.group(0)!).toSet();

void main() {
  final keys = _usedKeys();

  for (final lang in _langs) {
    test('$lang: barcha customer_confirm kalitlari bor va bo\'sh emas', () {
      final m = _load(lang);
      for (final k in keys) {
        expect((m[k] ?? '').toString().trim(), isNotEmpty, reason: '$lang: $k');
      }
    });

    test('$lang: ichki terminlar yo\'q (45-qoida)', () {
      final m = _load(lang);
      final text = [for (final k in keys) m[k].toString()].join(' ').toLowerCase();
      for (final bad in ['leg', 'escrow', 'settlement', 'zone', 'reason', 'not_awaiting']) {
        expect(text.contains(bad), isFalse, reason: '$lang: "$bad"');
      }
    });
  }

  test('joy egalari ({n}, {qty}, {unit}, {amount}) 3 tilda bir xil', () {
    final maps = {for (final l in _langs) l: _load(l)};
    for (final k in keys) {
      final base = _placeholders(maps['uz_Latn']![k].toString());
      for (final l in _langs) {
        expect(_placeholders(maps[l]![k].toString()), base, reason: '$l: $k');
      }
    }
  });

  test('tugma matnlari: Kuryerga berdim / Oldim / Tasdiqlayman', () {
    final latn = _load('uz_Latn');
    expect(latn['customer_confirm_btn_handover'], 'Kuryerga berdim');
    expect(latn['customer_confirm_btn_received'], 'Oldim');
    expect(latn['customer_confirm_btn_confirm'], 'Tasdiqlayman');
    expect(latn['customer_confirm_waiting'], 'Mijoz tasdig\'i kutilmoqda');
  });
}
