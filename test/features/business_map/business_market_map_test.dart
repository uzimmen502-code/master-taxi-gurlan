// «Менинг бизнесим» фаолият тури → 6 бозор мослиги (2026-11-16).
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_market_map.dart';
import 'package:ava_gurlan/features/business_map/domain/business_subtypes.dart';
import 'package:ava_gurlan/features/business_map/domain/business_type_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../markets/taxonomy_fixture.dart';

void main() {
  BusinessMarketMatch? m(BusinessCategory c, [String? s]) => marketForBusiness(c, s);

  test('6 бозорнинг ҳар бирига йўл бор', () {
    expect(m(BusinessCategory.animals, 'Чорва сотиш'), (marketId: 'livestock', categoryId: null));
    expect(m(BusinessCategory.auto, 'Автосалон'), (marketId: 'auto', categoryId: 'cars'));
    expect(m(BusinessCategory.retail, 'Гўшт дўкони (қассоб)'), (marketId: 'meat', categoryId: null));
    expect(m(BusinessCategory.agriculture, 'Полизчилик'), (marketId: 'farm', categoryId: 'melons'));
    expect(m(BusinessCategory.retail, 'Телефон'), (marketId: 'electronics', categoryId: 'phones'));
    expect(m(BusinessCategory.retail, 'Маиший техника'), (marketId: 'appliances', categoryId: null));
  });

  test('бўлимлар: мото/техника/эҳтиёт қисм, балиқ/парранда, кондиционер, ноутбук, аксессуар', () {
    expect(m(BusinessCategory.auto, 'Мотоцикл савдоси')?.categoryId, 'moto');
    expect(m(BusinessCategory.auto, 'Махсус техника савдоси')?.categoryId, 'tech');
    expect(m(BusinessCategory.auto, 'Шина савдоси')?.categoryId, 'parts');
    expect(m(BusinessCategory.retail, 'Автомобиль эҳтиёт қисмлари'), (marketId: 'auto', categoryId: 'parts'));
    expect(m(BusinessCategory.agriculture, 'Балиқчилик'), (marketId: 'meat', categoryId: 'fish'));
    expect(m(BusinessCategory.retail, 'Товуқ гўшти дўкони')?.categoryId, 'poultry');
    expect(m(BusinessCategory.retail, 'Кондиционер ва иситгичлар'), (marketId: 'appliances', categoryId: 'air_conditioners'));
    expect(m(BusinessCategory.retail, 'Компьютер ва ноутбуклар'), (marketId: 'electronics', categoryId: 'laptops'));
    expect(m(BusinessCategory.retail, 'Телефон аксессуарлари'), (marketId: 'electronics', categoryId: 'accessories'));
    expect(m(BusinessCategory.retail, 'Электроника'), (marketId: 'electronics', categoryId: null));
    expect(m(BusinessCategory.agriculture, 'Қорамол')?.marketId, 'livestock');
  });

  test('исталган тил/ёзувда сақланган тур танилади', () {
    expect(m(BusinessCategory.retail, 'Телефоны')?.marketId, 'electronics');
    expect(m(BusinessCategory.retail, "Baliq do'koni")?.categoryId, 'fish');
    expect(m(BusinessCategory.auto, '  автосалон ')?.categoryId, 'cars');
  });

  test('бўш/ўз матни → тур бўйича (animals, agriculture, auto); тайёр хизмат тури → йўқ', () {
    expect(m(BusinessCategory.animals), (marketId: 'livestock', categoryId: null));
    expect(m(BusinessCategory.agriculture, 'Менинг фермам'), (marketId: 'farm', categoryId: null));
    expect(m(BusinessCategory.auto, ''), (marketId: 'auto', categoryId: null));
    expect(m(BusinessCategory.animals, 'Ветеринария'), isNull);
    expect(m(BusinessCategory.auto, 'Автосервис'), isNull);
    expect(m(BusinessCategory.agriculture, 'Ер ҳайдаш'), isNull);
  });

  test('номаълум → бозор йўқ (Аралаш)', () {
    expect(m(BusinessCategory.retail), isNull);
    expect(m(BusinessCategory.retail, 'Кийим-кечак'), isNull);
    expect(m(BusinessCategory.food, 'Ресторан'), isNull);
    expect(m(BusinessCategory.other, 'Нимадир'), isNull);
    expect(m(BusinessCategory.it, null), isNull);
  });

  test('мосликдаги ҳар бир бозор/бўлим таксономия v3 да бор (fixture = market_taxonomy_v3.json бўлимлари)', () {
    final tax = kTaxonomyV3;
    final all = {for (final x in tax.ordered) x.id};
    expect(all, {'livestock', 'auto', 'meat', 'farm', 'electronics', 'appliances'});
    final seen = <String>{};
    for (final c in BusinessCategory.values) {
      for (final (uz, _) in BusinessSubtypes.data[c]!) {
        final r = m(c, uz);
        if (r == null) continue;
        seen.add(r.marketId);
        final mk = tax.market(r.marketId);
        expect(mk, isNotNull, reason: '$uz → ${r.marketId}');
        if (r.categoryId != null) {
          expect(mk!.category(r.categoryId!), isNotNull, reason: '$uz → ${r.marketId}/${r.categoryId}');
        }
      }
    }
    expect(seen, all);
  });

  test('янги авто савдо турлари — маҳсулот профили', () {
    for (final s in ['Автосалон', 'Мотоцикл савдоси', 'Махсус техника савдоси']) {
      expect(BusinessTypeProfile.of(BusinessCategory.auto, subtype: s).defaultKind, OfferKind.product, reason: s);
    }
  });
}
