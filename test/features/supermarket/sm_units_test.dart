// «AVA Супермаркет» ўлчов бирликлари ва намуна нархи (эга 2026-11-28):
//   «намуналар нархи ёнига керакмас, лекин ҳақиқий маҳсулотлар учун: дона, кг, литр ва бошқа ўлчов бирликлар керак».
//
//   flutter test test/features/supermarket/sm_units_test.dart
//
// Паритет: мижоз рўйхати (sm_units.dart) ва `assets/lang` `sm_unit_<id>` — ЯГОНА МАНБА `functions/supermarket_units.json`
// (сервер supermarket.js шу файлни ўқийди) билан бир хил бўлиши шарт. Тест репо илдизидан ишга туширилади.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/supermarket/domain/sm_offer.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';
import 'package:ava_gurlan/features/supermarket/partner/sm_partner_service.dart';
import 'package:ava_gurlan/features/supermarket/widgets/sm_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

Map<String, String> _n(String s) => {'uz_Cyrl': s, 'uz_Latn': s, 'ru': s};

final _tx = SmTaxonomy.fromMap({
  'version': 1,
  'categories': [
    {
      'id': 'oil_spices', 'order': 1, 'icon': 'oil', 'names': _n('Ёғ'),
      'groups': [
        {'id': 'sunflower_oil', 'order': 1, 'names': _n('Кунгабоқар ёғи'), 'unit': 'l', 'step': 1, 'weighed': false, 'synonyms': []},
        {'id': 'cumin', 'order': 2, 'names': _n('Зира'), 'unit': 'g', 'step': 50, 'weighed': false, 'synonyms': []},
      ],
    },
  ],
});

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final src = File('functions/supermarket_units.json');

  group('паритет: functions/supermarket_units.json ↔ sm_units.dart ↔ lang', () {
    test('манба файли бор (акс ҳолда паритет текширилмай қолади)', () {
      expect(src.existsSync(), isTrue, reason: 'топилмади: ${src.path} (тест репо илдизидан ишга туширилади)');
    });

    test('id тартиби ва 3 тилдаги ёрлиқлар — сервер манбаи билан айнан бир хил', () {
      final units = (_json(src.path)['units'] as List).cast<Map<String, dynamic>>();
      expect(kSmUnitIds, [for (final u in units) u['id']]);
      expect(kSmUnits, kSmUnitIds.toSet());
      for (final u in units) {
        expect(kSmUnitLabels[u['id']], Map<String, String>.from(u['labels'] as Map), reason: '${u['id']}');
      }
      // Эга рўйхати (PROPOSED): камида дона, кг, г, литр, мл, қадоқ/пачка, қути, метр.
      for (final id in const ['piece', 'kg', 'g', 'l', 'ml', 'pack', 'box', 'm']) {
        expect(kSmUnits, contains(id));
      }
    });

    test('assets/lang: sm_unit_<id> ҳар 3 тилда — манбадаги ёрлиқ; uz_Latn янги алифбода; smp_ бирлик калитлари', () {
      for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final j = _json('assets/lang/$l.json');
        for (final id in kSmUnitIds) {
          expect(j['sm_unit_$id'], kSmUnitLabels[id]![l], reason: '$l sm_unit_$id');
        }
        for (final k in const ['smp_f_unit', 'smp_unit_group_default', 'smp_err_unit']) {
          expect((j[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
        }
      }
      final latn = _json('assets/lang/uz_Latn.json');
      for (final k in [...kSmUnitIds.map((u) => 'sm_unit_$u'), 'smp_f_unit', 'smp_unit_group_default', 'smp_err_unit']) {
        expect(RegExp(r"o'|g'|sh|ch", caseSensitive: false).hasMatch('${latn[k]}'), isFalse, reason: k);
      }
    });
  });

  group('SmOffer.fromMap бирлиги', () {
    final oil = _tx.group('sunflower_oil');

    test('намуна: бирлик ЙЎҚ (гуруҳнинг «л» бирлиги ҳам, эски «дона» матни ҳам олинмайди)', () {
      final s = SmOffer.fromMap('pp_1', {'smGroupId': 'sunflower_oil', 'price': 25000, 'unit': 'дона', 'smSample': true}, group: oil);
      expect(s.unit, '');
      final s2 = SmOffer.fromMap('pp_2', {'smGroupId': 'sunflower_oil', 'price': 25000, 'smSample': true}, group: oil);
      expect(s2.unit, '');
    });

    test('ҳақиқий таклиф: маълум бирлик (янгилари ҳам) → ўзи', () {
      for (final u in const ['piece', 'kg', 'g', 'l', 'ml', 'pack', 'box', 'm', 'bunch']) {
        expect(SmOffer.fromMap('ps_$u', {'smGroupId': 'sunflower_oil', 'price': 1000, 'unit': u}, group: oil).unit, u);
      }
    });

    test('номаълум бирлик → \'\' (нотўғри «/л» эмас); майдон йўқ (эски шакл) → гуруҳники', () {
      expect(SmOffer.fromMap('ps_x', {'smGroupId': 'sunflower_oil', 'price': 1000, 'unit': 'ton'}, group: oil).unit, '');
      expect(SmOffer.fromMap('ps_y', {'smGroupId': 'sunflower_oil', 'price': 1000, 'unit': 'дона'}, group: oil).unit, '');
      expect(SmOffer.fromMap('ps_z', {'smGroupId': 'sunflower_oil', 'price': 1000}, group: oil).unit, 'l');
    });

    test('таксономия: янги бирликли гуруҳ (г) ташланмайди; номаълум бирликли гуруҳ — ташланади', () {
      expect(_tx.group('cumin')?.unit, 'g');
      final bad = SmTaxonomy.fromMap({
        'version': 1,
        'categories': [
          {'id': 'c', 'order': 1, 'icon': 'x', 'names': _n('C'), 'groups': [
            {'id': 'a', 'order': 1, 'names': _n('A'), 'unit': 'tonna', 'step': 1, 'weighed': false, 'synonyms': []},
          ]},
        ],
      });
      expect(bad.group('a'), isNull);
    });
  });

  testWidgets('нарх матни: намуна — «25 000 сўм» (бирликсиз); ҳақиқий — «…/қути»; номаълум бирлик — бирликсиз', (t) async {
    final d = JsonL10nDelegate();
    late BuildContext ctx;
    await t.pumpWidget(l10nApp(delegate: d, home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    await t.pumpAndSettle();
    final sample = SmOffer.fromMap('pp_1', {'smGroupId': 'sunflower_oil', 'price': 25000, 'unit': 'дона', 'smSample': true}, group: _tx.group('sunflower_oil'));
    final p1 = smPricePerUnit(ctx, sample.price, sample.unit);
    expect(p1.contains('/'), isFalse, reason: p1);
    final real = SmOffer.fromMap('ps_1', {'smGroupId': 'sunflower_oil', 'price': 25000, 'unit': 'box'}, group: _tx.group('sunflower_oil'));
    expect(smPricePerUnit(ctx, real.price, real.unit), endsWith('/${d.tr('sm_unit_box')}'));
    expect(smUnitLabel(ctx, 'ton'), '');
    expect(smUnitLabel(ctx, ''), '');
    expect(smUnitLabel(ctx, 'kg'), d.tr('sm_unit_kg'));
  });

  test('ҳамкор шакли: бирлик ихтиёрий — бўш → offer\'да йўқ (гуруҳники); маълум → юборилади; номаълум → smp_err_unit', () {
    ({Map<String, dynamic> offer, List<String> problems}) f(String unit) => smPartnerOfferFromForm(
          sku: 'oil-1', groupId: 'sunflower_oil', varietyId: 'std', varietyNames: _n('Оддий'), qualityNames: const {},
          packLabel: '', price: '25000', stock: '5', status: 'active', unit: unit,
        );
    expect(f('').offer.containsKey('unit'), isFalse);
    expect(f('').problems, isEmpty);
    expect(f('ml').offer['unit'], 'ml');
    expect(f('box').offer['unit'], 'box');
    expect(f('tonna').problems, ['smp_err_unit']);
    expect(f('tonna').offer.containsKey('unit'), isFalse);
  });
}
