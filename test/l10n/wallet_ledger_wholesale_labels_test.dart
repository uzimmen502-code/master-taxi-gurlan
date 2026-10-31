// Hamyon tarixi: Ulgurji (+ relay yo'qolgan posilka) wallet_ledger turlari 3 tilda yorliqli.
// Tur nomlari — jonli server kodi (feat/ulg-card 2fec8ce8):
//   functions/wholesale_orders.js  mirrorWallet(..., '<type>') va walletLedgerType: '<type>'
//   functions/relay_escrow.js      walletLedgerType: 'logistics_lost_refund' (mirrorBonus —
//                                  mijoz + kuryer ikkalasiga, ishorasi bilan)
// Noma'lum tur — eski umumiy fallback (modul nomi yoki tur nomi).
//
//   flutter test test/l10n/wallet_ledger_wholesale_labels_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/core/utils/wallet_ledger_labels.dart';
import 'package:ava_gurlan/models/wallet_ledger_entry.dart';

const _wholesaleTypes = <String>[
  'wholesale_hold',
  'wholesale_card_hold',
  'wholesale_refund',
  'wholesale_refusal_refund',
  'wholesale_payout',
  'wholesale_unearned_delivery_refund',
  'wholesale_return_hold',
  'wholesale_lost_refund',
  'wholesale_lost_fee_refund',
  'wholesale_lost_fee_charge',
  'wholesale_lost_fee_payment',
];

String _tr(String key, [Map<String, String>? params]) => '<$key>';

WalletLedgerEntry _e(String type, {int amount = 1000, String module = 'wholesale'}) => WalletLedgerEntry(
      id: 'w', type: type, amount: amount, createdAt: DateTime(2026, 10, 31),
      module: module, refType: 'wholesale_order', refId: 'ORD1',
    );

Map<String, dynamic> _load(String lang) =>
    jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final langs = {for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) l: _load(l)};

  test('har Ulgurji turi o\'z kalitiga (modul bilan ham, modulsiz ham)', () {
    for (final t in _wholesaleTypes) {
      expect(walletLedgerTitle(_e(t), _tr), '<wlt_l_$t>', reason: t);
      expect(walletLedgerTitle(_e(t, module: ''), _tr), '<wlt_l_$t>', reason: '$t modulsiz');
    }
  });

  test('relay logistics_lost_refund: mijoz (+) — qoplandi, kuryer (−) — undirildi', () {
    expect(walletLedgerTitle(_e('logistics_lost_refund', amount: 50000, module: ''), _tr), '<wlt_l_logistics_lost_refund>');
    expect(walletLedgerTitle(_e('logistics_lost_refund', amount: -50000, module: ''), _tr), '<wlt_l_logistics_lost_charge>');
  });

  test('har kalit 3 tilda bor, bo\'sh emas, tur nomining o\'zi emas; tillar farqli', () {
    final keys = [for (final t in _wholesaleTypes) 'wlt_l_$t', 'wlt_l_logistics_lost_refund', 'wlt_l_logistics_lost_charge'];
    for (final k in keys) {
      final values = <String>{};
      for (final m in langs.entries) {
        final v = m.value[k];
        expect(v is String && v.trim().isNotEmpty, isTrue, reason: '$k / ${m.key}');
        expect(v, isNot(contains('wholesale_')), reason: '$k / ${m.key}');
        values.add(v as String);
      }
      expect(values.length, 3, reason: '$k: uch tilda bir xil matn — tarjima qilinmagan');
    }
  });

  test('haqiqiy tarjima bilan: uz_Cyrl topshiriqdagi matnlar', () {
    final cyr = langs['uz_Cyrl']!;
    String tr(String key, [Map<String, String>? p]) => (cyr[key] ?? key) as String;
    expect(walletLedgerTitle(_e('wholesale_hold', amount: -180000), tr), 'Улгуржи буюртма учун ушланди');
    expect(walletLedgerTitle(_e('wholesale_refund'), tr), 'Улгуржи буюртма бекор — қайтарилди');
    expect(walletLedgerTitle(_e('wholesale_payout'), tr), 'Улгуржи сотувдан тушум');
    expect(walletLedgerTitle(_e('wholesale_lost_refund'), tr), 'Йўқолган посилка — товар пули қайтарилди');
    expect(walletLedgerTitle(_e('wholesale_lost_fee_refund'), tr), 'Йўқолган посилка — етказиш пули қайтарилди');
    expect(walletLedgerTitle(_e('wholesale_lost_fee_charge', amount: -15000), tr), 'Йўқолган посилка учун етказиш пули ундирилди');
  });

  test('noma\'lum tur — eski umumiy fallback o\'zgarmagan', () {
    expect(walletLedgerTitle(_e('wholesale_future_thing'), _tr), 'wholesale', reason: 'modul nomi');
    expect(walletLedgerTitle(_e('wholesale_future_thing', module: ''), _tr), 'wholesale_future_thing');
    expect(walletLedgerTitle(_e('', module: ''), _tr), '<wlt_l_operation>');
    expect(walletLedgerTitle(_e('logistics_escrow', module: ''), _tr), 'logistics_escrow');
  });
}
