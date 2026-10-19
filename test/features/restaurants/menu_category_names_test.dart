import 'package:ava_gurlan/core/utils/uz_script.dart';
import 'package:ava_gurlan/features/restaurants/domain/menu_category_choice.dart';
import 'package:ava_gurlan/features/restaurants/domain/menu_category_names.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('тайёр номлар жадвали', () {
    test('ҳар калитда учала тил бор ва бўш эмас', () {
      MenuCategoryNames.presets.forEach((k, names) {
        expect(names.keys.toSet(), {'uz_Cyrl', 'uz_Latn', 'ru'}, reason: k);
        expect(names.values.every((v) => v.trim().isNotEmpty), isTrue, reason: k);
      });
    });

    test('ўзбек лотини кириллдан ўгириш билан БИР ХИЛ (имло хатоси йўқ)', () {
      MenuCategoryNames.presets.forEach((k, n) {
        expect(UzScript.toLatin(n['uz_Cyrl']!), n['uz_Latn'], reason: k);
        expect(UzScript.toCyrillic(n['uz_Latn']!), n['uz_Cyrl'], reason: k);
      });
    });

    test('номлар ўзаро такрорланмайди (бир матн иккита калитга тушмасин)', () {
      final seen = <String, String>{};
      MenuCategoryNames.presets.forEach((k, names) {
        for (final v in names.values) {
          final id = MenuCategoryNames.identity(v);
          expect(seen[id] == null || seen[id] == k, isTrue, reason: '$v ($k) ≠ ${seen[id]}');
          seen[id] = k;
        }
      });
    });
  });

  group('MenuCategoryNames.display — мижоз ўз тилида кўради', () {
    test('REGRESSION: кирилда сақланган тайёр ном — рус мижозга русча, лотин мижозга лотинча', () {
      expect(MenuCategoryNames.display('Ичимликлар', 'ru'), 'Напитки');
      expect(MenuCategoryNames.display('Ичимликлар', 'uz_Latn'), 'Ichimliklar');
      expect(MenuCategoryNames.display('Ичимликлар', 'uz_Cyrl'), 'Ичимликлар');
    });

    test('лотинда ёки русчада сақланган тайёр ном ҳам ҳар тилда мос чиқади', () {
      expect(MenuCategoryNames.display('Issiq taomlar', 'uz_Cyrl'), 'Иссиқ таомлар');
      expect(MenuCategoryNames.display('Issiq taomlar', 'ru'), 'Горячие блюда');
      expect(MenuCategoryNames.display('Горячие блюда', 'uz_Latn'), 'Issiq taomlar');
      expect(MenuCategoryNames.display('  ШАШЛЫК ', 'uz_Cyrl'), 'Шашлик');
    });

    test('эганинг ўз номи: ўзбек кирилл ↔ лотин, рус учун кирилл', () {
      expect(MenuCategoryNames.display('Чойхона таомлари', 'uz_Latn'), 'Choyxona taomlari');
      expect(MenuCategoryNames.display("Choyxona taomlari", 'uz_Cyrl'), 'Чойхона таомлари');
      expect(MenuCategoryNames.display("Choyxona taomlari", 'ru'), 'Чойхона таомлари');
      expect(MenuCategoryNames.display('Чойхона таомлари', 'ru'), 'Чойхона таомлари');
    });

    test('бренд ва рақам бузилмайди', () {
      expect(MenuCategoryNames.display('Coca-Cola 0.5', 'uz_Cyrl'), 'Coca-Cola 0.5');
      expect(MenuCategoryNames.display('KFC', 'ru'), 'KFC');
    });

    test('бўш матн йиқилмайди', () {
      expect(MenuCategoryNames.display('', 'ru'), '');
      expect(MenuCategoryNames.display('   ', 'uz_Latn'), '   ');
    });

    test('MenuCategory.displayName сақланган номга тегмайди', () {
      const c = MenuCategory(id: 'x', name: 'Ичимликлар');
      expect(c.displayName('ru'), 'Напитки');
      expect(c.name, 'Ичимликлар');
    });
  });

  group('такрорий категория — тил ва ёзувдан қатъи назар', () {
    const cats = [MenuCategory(id: 'c1', name: 'Ичимликлар'), MenuCategory(id: 'c2', name: 'Чойхона таомлари')];

    test('тайёр ном бошқа тилда: «Напитки» = «Ichimliklar» = «Ичимликлар»', () {
      expect(MenuCategoryChoice.findByName(cats, 'Напитки')?.id, 'c1');
      expect(MenuCategoryChoice.findByName(cats, 'ichimliklar')?.id, 'c1');
    });

    test('эганинг ўз номи: кирилл ↔ лотин', () {
      expect(MenuCategoryChoice.findByName(cats, 'Choyxona taomlari')?.id, 'c2');
      expect(MenuCategoryChoice.findByName(cats, ' чойхона   таомлари ')?.id, 'c2');
    });

    test('бошқа ном → null', () {
      expect(MenuCategoryChoice.findByName(cats, 'Салатлар'), isNull);
    });
  });
}
