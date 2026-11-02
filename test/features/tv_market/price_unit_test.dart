// S0 (2026-11-03): нарх бирлиги модели ва ягона форматтер.

import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _load(String lang) =>
    jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;

String Function(String) _tr(Map<String, dynamic> m) => (k) => (m[k] as String?) ?? k;

void main() {
  final cyr = _load('uz_Cyrl');
  final lat = _load('uz_Latn');
  final ru = _load('ru');

  group('PriceUnit wire', () {
    test('wire қийматлари S2 rules рўйхати билан бир хил', () {
      expect(PriceUnit.wires,
          ['', 'from', 'hour', 'day', 'month', 'session', 'person', 'kg', 'm2', 'piece', 'negotiable']);
    });

    test('fromWire: ҳар қиймат ўзига қайтади', () {
      for (final u in PriceUnit.values) {
        expect(PriceUnit.fromWire(u.wire), u, reason: u.name);
      }
    });

    test('fromWire: йўқ / бўш / номаълум / сон → fixed (эски ҳужжат бузилмайди)', () {
      expect(PriceUnit.fromWire(null), PriceUnit.fixed);
      expect(PriceUnit.fromWire(''), PriceUnit.fixed);
      expect(PriceUnit.fromWire('week'), PriceUnit.fixed);
      expect(PriceUnit.fromWire('HOUR'), PriceUnit.fixed);
      expect(PriceUnit.fromWire(3), PriceUnit.fixed);
      expect(PriceUnit.fromWire(' hour '), PriceUnit.hour);
    });
  });

  group('l10n', () {
    test('ҳар бирлик калити (ном + қисқа) 3 тилда бор ва бўш эмас', () {
      for (final u in PriceUnit.values) {
        for (final (name, m) in [('uz_Cyrl', cyr), ('uz_Latn', lat), ('ru', ru)]) {
          expect((m[u.labelKey] as String?)?.trim(), isNotEmpty, reason: '$name ${u.labelKey}');
          final s = u.suffixKey;
          if (s != null) expect((m[s] as String?)?.trim(), isNotEmpty, reason: '$name $s');
        }
      }
      for (final k in ['home_price_from', 'yuk_negotiable']) {
        for (final m in [cyr, lat, ru]) {
          expect(m[k], isA<String>(), reason: k);
        }
      }
    });
  });

  group('formatOfferPrice', () {
    final t = _tr(cyr);

    test('ҳар бирлик (uz_Cyrl)', () {
      expect(formatOfferPrice(150000, PriceUnit.fixed, t), '150 000 сўм');
      expect(formatOfferPrice(150000, PriceUnit.from, t), 'дан 150 000 сўм');
      expect(formatOfferPrice(50000, PriceUnit.hour, t), '50 000 сўм / соат');
      expect(formatOfferPrice(300000, PriceUnit.day, t), '300 000 сўм / кун');
      expect(formatOfferPrice(2000000, PriceUnit.month, t), '2 000 000 сўм / ой');
      expect(formatOfferPrice(80000, PriceUnit.session, t), '80 000 сўм / сеанс');
      expect(formatOfferPrice(250000, PriceUnit.person, t), '250 000 сўм / киши');
      expect(formatOfferPrice(12000, PriceUnit.kg, t), '12 000 сўм / кг');
      expect(formatOfferPrice(45000, PriceUnit.m2, t), '45 000 сўм / м²');
      expect(formatOfferPrice(7000, PriceUnit.piece, t), '7 000 сўм / дона');
      expect(formatOfferPrice(100000, PriceUnit.negotiable, t), '100 000 сўм · Келишилади');
    });

    test('нарх 0: negotiable → «Келишилади», қолгани — бўш (нарх кўрсатилмайди)', () {
      expect(formatOfferPrice(0, PriceUnit.negotiable, t), 'Келишилади');
      for (final u in PriceUnit.values.where((u) => u != PriceUnit.negotiable)) {
        expect(formatOfferPrice(0, u, t), '', reason: u.name);
      }
      expect(formatOfferPrice(-5, PriceUnit.hour, t), '');
    });

    test('чегара: 1 сўм ва 9 хонали нарх', () {
      expect(formatOfferPrice(1, PriceUnit.fixed, t), '1 сўм');
      expect(formatOfferPrice(999999999, PriceUnit.kg, t), '999 999 999 сўм / кг');
    });

    test('uz_Latn ва ru', () {
      expect(formatOfferPrice(50000, PriceUnit.hour, _tr(lat)), '50 000 сўм / soat');
      expect(formatOfferPrice(150000, PriceUnit.from, _tr(ru)), 'от 150 000 сўм');
      expect(formatOfferPrice(7000, PriceUnit.piece, _tr(ru)), '7 000 сўм / шт');
      expect(formatOfferPrice(0, PriceUnit.negotiable, _tr(ru)), 'Договорная');
      expect(formatOfferPrice(2000000, PriceUnit.month, _tr(ru)), '2 000 000 сўм / мес.');
    });
  });
}
