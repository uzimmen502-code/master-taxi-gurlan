import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
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
