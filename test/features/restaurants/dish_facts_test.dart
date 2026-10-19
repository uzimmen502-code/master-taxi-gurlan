// Таом маълумотлари (D-REST-16/17/24): соф мантиқ — чегаралар `firestore.rules`
// (`restaurantMenuItemOk`) билан бир хил бўлиши шарт; шу тест ва
// `functions/test/restaurant_rules.test.js` бир хил чегара нуқталарини қулфлайди.

import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/dish_facts.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:flutter_test/flutter_test.dart';

DishFacts _nutrition(int kcal, int protein, int fat, int carbs) =>
    DishFacts(kcal: kcal, protein: protein, fat: fat, carbs: carbs);

void main() {
  group('DishFacts.validate — порция ва грамм', () {
    test('бўш факт тўғри (ҳаммаси ихтиёрий) ва isEmpty', () {
      expect(DishFacts.empty.validate(), isEmpty);
      expect(DishFacts.empty.isEmpty, isTrue);
      expect(const DishFacts(servings: 2).isEmpty, isFalse);
    });

    test('порция 1…50 (чегаралар), 0 ва 51 хато', () {
      expect(const DishFacts(servings: 1).validate(), isEmpty);
      expect(const DishFacts(servings: 50).validate(), isEmpty);
      expect(const DishFacts(servings: 0).validate(), [DishFactsError.servings]);
      expect(const DishFacts(servings: 51).validate(), [DishFactsError.servings]);
      expect(const DishFacts(servings: -1).validate(), [DishFactsError.servings]);
    });

    test('грамм 10…5000 (чегаралар), 9 ва 5001 хато', () {
      expect(const DishFacts(weightG: 10).validate(), isEmpty);
      expect(const DishFacts(weightG: 5000).validate(), isEmpty);
      expect(const DishFacts(weightG: 9).validate(), [DishFactsError.weight]);
      expect(const DishFacts(weightG: 5001).validate(), [DishFactsError.weight]);
    });
  });

  group('DishFacts — КБЖУ', () {
    test('тўртталаси бирга: тўғри; бир неча қисм — nutrition_incomplete', () {
      expect(_nutrition(600, 30, 25, 60).validate(), isEmpty, reason: 'calc 585, фарқ 15');
      expect(const DishFacts(kcal: 300).validate(), [DishFactsError.nutritionIncomplete]);
      expect(const DishFacts(kcal: 300, protein: 10, fat: 10).validate(), [DishFactsError.nutritionIncomplete]);
      expect(const DishFacts(protein: 10, fat: 10, carbs: 10).validate(), [DishFactsError.nutritionIncomplete]);
    });

    test('калория мослиги — 15 % (calc 400: 340…460), икки томонлама чегара', () {
      expect(_nutrition(460, 0, 0, 100).validate(), isEmpty);
      expect(_nutrition(340, 0, 0, 100).validate(), isEmpty);
      expect(_nutrition(461, 0, 0, 100).validate(), [DishFactsError.nutritionMismatch]);
      expect(_nutrition(339, 0, 0, 100).validate(), [DishFactsError.nutritionMismatch]);
    });

    test('калория мослиги — мутлақ 20 ккал (calc 40: 20…60), сув (ҳаммаси 0)', () {
      expect(_nutrition(60, 0, 0, 10).validate(), isEmpty);
      expect(_nutrition(20, 0, 0, 10).validate(), isEmpty);
      expect(_nutrition(61, 0, 0, 10).validate(), [DishFactsError.nutritionMismatch]);
      expect(_nutrition(0, 0, 0, 0).validate(), isEmpty);
      expect(_nutrition(20, 0, 0, 0).validate(), isEmpty);
      expect(_nutrition(21, 0, 0, 0).validate(), [DishFactsError.nutritionMismatch]);
    });

    test('диапазон алоҳида: мослик бажарилган, фақат чегара ошган → nutrition_range', () {
      expect(_nutrition(5000, 500, 111, 500).validate(), isEmpty, reason: 'calc 4999');
      expect(_nutrition(5001, 500, 111, 500).validate(), [DishFactsError.nutritionRange]);
      expect(_nutrition(2200, 501, 0, 0).validate(), [DishFactsError.nutritionRange], reason: 'calc 2004 — мос');
      expect(_nutrition(-1, 0, 0, 0).validate(), [DishFactsError.nutritionRange]);
    });

    test('kcalConsistent: қисман берилса текширилмайди (true)', () {
      expect(DishFacts.kcalConsistent(kcal: 100), isTrue);
      expect(DishFacts.kcalConsistent(kcal: 100, protein: 1, fat: 1), isTrue);
      expect(DishFacts.kcalConsistent(kcal: 460, protein: 0, fat: 0, carbs: 100), isTrue);
      expect(DishFacts.kcalConsistent(kcal: 461, protein: 0, fat: 0, carbs: 100), isFalse);
    });
  });

  group('DishFacts — кухна ва теглар', () {
    test('кухна: иккаласи бирга ва гуруҳ тўғри; биттаси ёки нотўғри гуруҳ — хато', () {
      expect(const DishFacts(cuisineGroup: 'national', cuisineId: 'national_ozbek').validate(), isEmpty);
      expect(const DishFacts(cuisineGroup: 'world', cuisineId: 'world_turk').validate(), isEmpty);
      expect(const DishFacts(cuisineId: 'national_ozbek').validate(), [DishFactsError.cuisine]);
      expect(const DishFacts(cuisineGroup: 'national').validate(), [DishFactsError.cuisine]);
      expect(const DishFacts(cuisineGroup: 'asia', cuisineId: 'x').validate(), [DishFactsError.cuisine]);
      expect(const DishFacts(cuisineGroup: 'national', cuisineId: '').validate(), [DishFactsError.cuisine]);
      expect(DishFacts(cuisineGroup: 'national', cuisineId: 'a' * 81).validate(), [DishFactsError.cuisine]);
      expect(DishFacts(cuisineGroup: 'national', cuisineId: 'a' * 80).validate(), isEmpty);
    });

    test('теглар: рухсат этилганлар ≤ 4, такрорсиз; бошқа тег ёки 5 та — хато', () {
      expect(const DishFacts(tags: [DishTag.kids, DishTag.light]).validate(), isEmpty);
      for (final tag in DishTag.all) {
        expect(DishFacts(tags: [tag]).validate(), isEmpty, reason: tag);
      }
      expect(const DishFacts(tags: [DishTag.kids, DishTag.light, DishTag.dastarxon, DishTag.ramadan]).validate(), isEmpty, reason: '4 та — рухсат');
      expect(const DishFacts(tags: DishTag.all).validate(), [DishFactsError.tags], reason: 'ҳаммаси бирданига (10 та) — ≤ 4 чегарасидан ошади');
      expect(const DishFacts(tags: ['spicy']).validate(), [DishFactsError.tags]);
      expect(const DishFacts(tags: ['kids', 'kids']).validate(), [DishFactsError.tags], reason: 'такрор');
      expect(const DishFacts(tags: ['kids', 'breakfast', 'night', 'light', 'x']).validate(), [DishFactsError.tags]);
    });

    test('бир нечта хато бирга қайтади', () {
      const bad = DishFacts(servings: 0, weightG: 9, kcal: 1, tags: ['x']);
      expect(bad.validate(), [
        DishFactsError.servings,
        DishFactsError.weight,
        DishFactsError.nutritionIncomplete,
        DishFactsError.tags,
      ]);
    });
  });

  group('DishFacts.toMap / fromMap', () {
    const full = DishFacts(
      servings: 4,
      weightG: 450,
      kcal: 600,
      protein: 30,
      fat: 25,
      carbs: 60,
      cuisineGroup: 'national',
      cuisineId: 'national_ozbek',
      tags: ['kids', 'light'],
    );

    test('тўлиқ тўплам: toMap → fromMap бир хил; barcha fieldKeys қоплайди', () {
      final m = full.toMap();
      expect(m.keys.toSet(), DishFacts.fieldKeys.toSet());
      final back = DishFacts.fromMap(Map<String, dynamic>.of(m));
      expect(back.toMap(), m);
      expect(back.validate(), isEmpty);
    });

    test('toMap фақат киритилганларни ёзади; бўш — {}', () {
      expect(DishFacts.empty.toMap(), isEmpty);
      expect(const DishFacts(servings: 2).toMap(), {'servings': 2});
      // КБЖУ бутун бўлмаса ҳеч қайси қисми ёзилмайди
      expect(const DishFacts(kcal: 300, protein: 10).toMap(), isEmpty);
    });

    test('fromMap бузилган/эски ҳужжатда синмайди: нотўғри тип ва чегара — «йўқ»', () {
      final d = DishFacts.fromMap({
        'servings': '4',
        'weightG': 9,
        'kcal': 600,
        'protein': 30.5,
        'fat': 25,
        'carbs': 60,
        'cuisineGroup': 'asia',
        'cuisineId': 'x',
        'tags': ['kids', 7, 'spicy', 'kids'],
      });
      expect(d.servings, isNull);
      expect(d.weightG, isNull);
      expect(d.hasNutrition, isFalse, reason: 'protein бутун эмас → КБЖУ бутунлай ташланади');
      expect(d.kcal, isNull);
      expect(d.hasCuisine, isFalse);
      expect(d.tags, ['kids'], reason: 'нотўғри ва такрор тег ташланади');
    });

    test('fromMap: web double (100.0) бутун сифатида қабул қилинади', () {
      expect(DishFacts.fromMap({'servings': 3.0, 'weightG': 450.0}).servings, 3);
      expect(DishFacts.fromMap({'servings': 3.5}).servings, isNull);
    });

    test('patch: null — тегилмайди; берилса киритилмаганлар «ўчириш» белгиси билан', () {
      const gone = Object();
      expect(DishFacts.patch(null, gone), isEmpty, reason: 'фактларни билмайдиган чақирувчи маълумотни ўчирмайди');
      final p = DishFacts.patch(const DishFacts(servings: 2, tags: ['kids']), gone);
      expect(p.keys.toSet(), DishFacts.fieldKeys.toSet());
      expect(p['servings'], 2);
      expect(p['tags'], ['kids']);
      expect(p['weightG'], same(gone));
      expect(p['kcal'], same(gone));
      expect(p['cuisineId'], same(gone));
      // Бўш факт = ҳаммаси ўчирилади (сотувчи барчасини тозалади)
      expect(DishFacts.patch(DishFacts.empty, gone).values.every((v) => identical(v, gone)), isTrue);
    });

    test('эски таом (фактсиз ҳужжат) → бўш', () {
      expect(DishFacts.fromMap({'name': 'Osh', 'price': 40000}).isEmpty, isTrue);
    });
  });

  group('MenuItem.pricePerPerson', () {
    MenuItem item(int price, int? servings) =>
        MenuItem(id: 'x', name: 'X', price: price, facts: DishFacts(servings: servings));

    test('юқорига яхлитланади (бутун сўм, 8-қоида): 35 000 / 4 = 8 750; 10 000 / 3 = 3 334', () {
      expect(item(35000, 4).pricePerPerson, 8750);
      expect(item(10000, 3).pricePerPerson, 3334);
      expect(item(10000, 1).pricePerPerson, 10000);
      expect(item(1, 50).pricePerPerson, 1);
    });

    test('порция сони йўқ ёки нарх нотўғри — null', () {
      expect(item(35000, null).pricePerPerson, isNull);
      expect(item(0, 4).pricePerPerson, isNull);
    });

    test('MenuItem.fromMap фактларни ўқийди', () {
      final m = MenuItem.fromMap('osh', {
        'name': 'Osh',
        'price': 40000,
        'servings': 4,
        'cuisineGroup': 'national',
        'cuisineId': 'national_ozbek',
      });
      expect(m.facts.servings, 4);
      expect(m.pricePerPerson, 10000);
      expect(m.facts.cuisineId, 'national_ozbek');
    });
  });

  group('Cuisine', () {
    test('тайёр кухна: names[lang]; сотувчи номи: кирилл ↔ лотин, рус учун кирилл', () {
      const preset = Cuisine(
        id: 'national_ozbek',
        name: 'Ўзбек',
        group: 'national',
        names: {'uz_Cyrl': 'Ўзбек', 'uz_Latn': "O'zbek", 'ru': 'Узбекская'},
      );
      expect(preset.displayName('uz_Latn'), "O'zbek");
      expect(preset.displayName('ru'), 'Узбекская');
      expect(preset.displayName('uz_Cyrl'), 'Ўзбек');

      const custom = Cuisine(id: 'national_x', name: 'Qashqadaryo milliy taomlari', group: 'national');
      expect(custom.displayName('uz_Latn'), 'Qashqadaryo milliy taomlari');
      expect(custom.displayName('uz_Cyrl'), 'Қашқадарё миллий таомлари');
      expect(custom.displayName('ru'), 'Қашқадарё миллий таомлари', reason: 'автоматик таржима йўқ — кирилл шакли');

      const cyr = Cuisine(id: 'national_y', name: 'Самарқанд миллий таомлари', group: 'national');
      expect(cyr.displayName('uz_Latn'), 'Samarqand milliy taomlari');
      expect(cyr.displayName('uz_Cyrl'), 'Самарқанд миллий таомлари');
    });

    test('fromMap: бузилган майдонлар синмайди; hidden', () {
      final c = Cuisine.fromMap('a', {'name': 5, 'group': null, 'names': {'ru': 'Х', 'uz_Latn': 3}, 'hidden': true});
      expect(c.name, '');
      expect(c.group, '');
      expect(c.names, {'ru': 'Х'});
      expect(c.hidden, isTrue);
      expect(Cuisine.fromMap('b', const {}).hidden, isFalse);
    });

    test('selectable: яширилган, гуруҳсиз ва номсиз чиқмайди; тил бўйича алифбо тартиби', () {
      final all = [
        const Cuisine(id: '1', name: 'Хоразм', group: 'national'),
        const Cuisine(id: '2', name: 'Бухоро', group: 'national'),
        const Cuisine(id: '3', name: 'Яширин', group: 'national', hidden: true),
        const Cuisine(id: '4', name: 'Гуруҳсиз', group: ''),
        const Cuisine(id: '5', name: '  ', group: 'world'),
        const Cuisine(id: '6', name: 'Турк', group: 'world'),
      ];
      final out = Cuisine.selectable(all, 'uz_Cyrl');
      expect(out.map((c) => c.id), ['2', '6', '1'], reason: 'Б < Т < Х');
    });

    test('selectable: ўзбек ҳарфлари асосий ҳарфидан кейин (ў — у дан кейин, Юникод тартиби эмас)', () {
      final out = Cuisine.selectable(const [
        Cuisine(id: 'f', name: 'Фарғона', group: 'national'),
        Cuisine(id: 'o', name: 'Ўзбек', group: 'national'),
        Cuisine(id: 'u', name: 'Узбекча', group: 'national'),
        Cuisine(id: 'q', name: 'Қашқадарё', group: 'national'),
        Cuisine(id: 'k', name: 'Конибодом', group: 'national'),
        Cuisine(id: 'l', name: 'Лазги', group: 'national'),
      ], 'uz_Cyrl');
      expect(out.map((c) => c.id), ['k', 'q', 'l', 'u', 'o', 'f']);
    });
  });
}
