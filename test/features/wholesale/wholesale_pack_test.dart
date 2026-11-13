import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_pack_editor.dart' show WholesalePackDraft;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Қадоқлар (эга, 2026-10-31): ≤5 қадоқ, ҳар бирининг ўз поғоналари;
/// эски (қадоқсиз) маҳсулот битта `default` қадоқ; маҳсулот даражасидаги
/// нарх/вазн — энг арзон қадоқдан нусха (эски илова ва Rules учун).
Map<String, dynamic> _pack(String id, String label, List<List<int>> tiers, {int? w, String photo = ''}) => {
      'id': id,
      'label': label,
      'priceTiers': [for (final t in tiers) {'minQty': t[0], 'price': t[1]}],
      if (w != null) 'unitWeightG': w,
      if (photo.isNotEmpty) 'photoUrl': photo,
    };

WholesaleProduct _product({List<Map<String, dynamic>>? packs}) => WholesaleProduct.fromMap('x', {
      'sellerId': '998901111111',
      'title': 'Гуруч',
      'description': 'Лазер',
      'priceTiers': [
        {'minQty': 1, 'price': 15000},
      ],
      'unit': 'кг',
      'unitWeightG': 1000,
      if (packs != null) 'packs': packs,
    });

void main() {
  group('parse', () {
    test('эски маҳсулот: битта default қадоқ маҳсулот майдонларидан', () {
      final p = _product();
      expect(p.hasPacks, isFalse);
      expect(p.effectivePacks, hasLength(1));
      final d = p.effectivePacks.single;
      expect(d.id, WholesalePack.defaultId);
      expect(d.basePrice, 15000);
      expect(d.unitWeightG, 1000);
    });

    test('қадоқлар ўқилади; нотўғри/такрорий/default ID ва 5 дан ортиғи ташланади', () {
      final p = _product(packs: [
        _pack('p1', '1 кг', [[1, 15000]], w: 1000),
        _pack('p1', 'такрор', [[1, 1]]),
        _pack('default', 'ёлғон', [[1, 1]]),
        _pack('x9', 'нотўғри ID', [[1, 1]]),
        _pack('p2', '', [[1, 1]]), // номсиз
        _pack('p3', 'нархсиз', []),
        _pack('p4', '5 кг', [[1, 70000], [10, 65000]], w: 5000),
        _pack('p5', '10 кг', [[1, 135000]]),
        _pack('p6', '25 кг', [[1, 320000]]),
        _pack('p7', '50 кг', [[1, 620000]]),
        _pack('p8', 'ортиқча', [[1, 1]]),
      ]);
      expect(p.packs.map((x) => x.id), ['p1', 'p4', 'p5', 'p6', 'p7']);
      expect(p.packById('p4').priceForQty(12), 65000);
      expect(p.packById('p4').priceForQty(3), 70000);
      expect(p.packById('йўқ').id, 'p1', reason: 'номаълум ID — биринчиси');
    });

    test('энг арзон қадоқ — бошланғич нарх бўйича', () {
      final p = _product(packs: [
        _pack('p1', '25 кг', [[1, 320000]]),
        _pack('p2', '1 кг', [[1, 15000]]),
      ]);
      expect(p.cheapestPack.id, 'p2');
    });
  });

  group('write', () {
    test('create: packs ёзилади, маҳсулот нархи/вазни энг арзон қадоқдан', () {
      final p = _product(packs: [
        _pack('p1', '25 кг', [[1, 320000]], w: 25000),
        _pack('p2', '1 кг', [[1, 15000], [10, 14000]], w: 1000, photo: 'https://x/1.jpg'),
      ]);
      final m = p.toFirestoreCreate();
      expect((m['packs'] as List), hasLength(2));
      expect(m['priceTiers'], [
        {'minQty': 1, 'price': 15000},
        {'minQty': 10, 'price': 14000},
      ]);
      expect(m['unitWeightG'], 1000);
      expect(((m['packs'] as List)[1] as Map)['photoUrl'], 'https://x/1.jpg');
    });

    test('create: қадоқсиз маҳсулотда packs майдони умуман йўқ', () {
      expect(_product().toFirestoreCreate().containsKey('packs'), isFalse);
    });

    test('update: қадоқлар олиб ташланса — packs ўчирилади', () {
      final m = _product().toFirestoreOwnerUpdate();
      expect(m['packs'], isA<FieldValue>());
    });
  });

  group('минимал буюртма (эга, 2026-11-13)', () {
    test('effectiveMoq: сотувчи сони катта бўлса — у; кичик/нотўғри/йўқ — поғона', () {
      const t1 = [PriceTier(minQty: 1, price: 100)];
      const t10 = [PriceTier(minQty: 10, price: 100)];
      expect(effectiveMoq(t1, 25), 25);
      expect(effectiveMoq(t10, 5), 10, reason: 'поғона катта');
      expect(effectiveMoq(t1, null), 1);
      expect(effectiveMoq(const [], null), 1);
      for (final bad in [0, -3, kWholesaleMaxOrderQty + 1]) {
        expect(effectiveMoq(t1, bad), 1, reason: 'нотўғри: $bad');
      }
      expect(effectiveMoq(t1, kWholesaleMaxOrderQty), kWholesaleMaxOrderQty, reason: 'чегара');
    });

    test('validMinOrderQty: бутун 1..1 000 000; каср/сатр/0 — null', () {
      expect(validMinOrderQty(25), 25);
      expect(validMinOrderQty(25.0), 25);
      expect(validMinOrderQty(2.5), isNull);
      expect(validMinOrderQty('25'), isNull);
      expect(validMinOrderQty(0), isNull);
      expect(validMinOrderQty(null), isNull);
    });

    test('қадоқ: ўқилади, moq га таъсир қилади, ёзилади; нотўғри қиймат ташланади', () {
      final p = _product(packs: [
        {..._pack('p1', '1 кг', [[1, 15000]]), 'minOrderQty': 25},
        {..._pack('p2', '25 кг', [[1, 320000]]), 'minOrderQty': 0},
      ]);
      expect(p.packById('p1').minOrderQty, 25);
      expect(p.packById('p1').moq, 25);
      expect(p.packById('p2').minOrderQty, isNull);
      expect(p.packById('p2').moq, 1);
      final packs = p.toFirestoreCreate()['packs'] as List;
      expect((packs[0] as Map)['minOrderQty'], 25);
      expect((packs[1] as Map).containsKey('minOrderQty'), isFalse);
    });

    test('қадоқсиз маҳсулот: маҳсулот даражасида — ўқилади, default қадоққа ўтади, ёзилади', () {
      final p = WholesaleProduct.fromMap('x', {
        'sellerId': '998901111111',
        'title': 'Ун',
        'description': 'Олий нав',
        'priceTiers': [
          {'minQty': 1, 'price': 9000},
        ],
        'minOrderQty': 40,
      });
      expect(p.minOrderQty, 40);
      expect(p.moq, 40);
      expect(p.effectivePacks.single.moq, 40);
      expect(p.toFirestoreCreate()['minOrderQty'], 40);
      expect(p.toFirestoreOwnerUpdate()['minOrderQty'], 40);
    });

    test('таҳрир: сон олиб ташланса ёки маҳсулот қадоқли бўлса — маҳсулот даражасидагиси ўчирилади', () {
      expect(_product().toFirestoreOwnerUpdate()['minOrderQty'], isA<FieldValue>());
      expect(_product().toFirestoreCreate().containsKey('minOrderQty'), isFalse);
      final packed = WholesaleProduct.fromMap('x', {
        'sellerId': '998901111111',
        'title': 'Гуруч',
        'description': 'Лазер',
        'priceTiers': [
          {'minQty': 1, 'price': 15000},
        ],
        'minOrderQty': 40,
        'packs': [_pack('p1', '1 кг', [[1, 15000]])],
      });
      expect(packed.moq, 1, reason: 'қадоқли маҳсулотда маҳсулот даражасидаги сон ишламайди');
      expect(packed.toFirestoreOwnerUpdate()['minOrderQty'], isA<FieldValue>());
      expect(packed.toFirestoreCreate().containsKey('minOrderQty'), isFalse);
    });
  });

  group('форма: минимал буюртма майдони', () {
    test('бўш — хато эмас; 25 — сақланади; 0 ва 1 000 001 — хато', () {
      final d = WholesalePackDraft(id: 'p1');
      addTearDown(d.dispose);
      expect(d.collectMinQty(), (qty: null, error: null));
      d.minQty.text = ' 25 ';
      expect(d.collectMinQty(), (qty: 25, error: null));
      d.minQty.text = '0';
      expect(d.collectMinQty().error, 'wholesale_err_min_qty_invalid');
      d.minQty.text = '1000001';
      expect(d.collectMinQty().error, 'wholesale_err_min_qty_invalid');
    });

    test('таҳрир: мавжуд қадоқнинг сони майдонга тушади', () {
      final d = WholesalePackDraft.fromPack(const WholesalePack(
        id: 'p1',
        label: '1 кг',
        priceTiers: [PriceTier(minQty: 1, price: 100)],
        minOrderQty: 30,
      ));
      addTearDown(d.dispose);
      expect(d.minQty.text, '30');
    });
  });

  group('stock', () {
    test('ўқиш: манфий ва сон бўлмаганлар ташланади; null = киритилмаган', () {
      final s = WholesaleStock.fromMap({
        'packs': {'p1': 12, 'p2': 0, 'p3': -4, 'p4': 'x'},
      });
      expect(s.of('p1'), 12);
      expect(s.isOut('p2'), isTrue);
      expect(s.of('p3'), isNull);
      expect(s.of('p4'), isNull);
      expect(s.of('p9'), isNull);
      expect(WholesaleStock.fromMap(null).byPack, isEmpty);
    });
  });

  test('nextId: банд бўлмаган биринчи', () {
    expect(WholesalePack.nextId(['p1', 'p3']), 'p2');
    expect(WholesalePack.nextId(const []), 'p1');
  });
}
