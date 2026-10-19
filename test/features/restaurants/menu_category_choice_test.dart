import 'package:ava_gurlan/features/restaurants/domain/menu_category_choice.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _cats = [
  MenuCategory(id: 'c1', name: 'Таомлар', sort: 0),
  MenuCategory(id: 'c2', name: 'Ичимликлар', sort: 1),
];

void main() {
  group('MenuCategoryChoice.initial — янги таом', () {
    test('REGRESSION: категория бор, фильтр йўқ → «Бошқалар» (биринчи категория ЭМАС)', () {
      expect(MenuCategoryChoice.initial(isEdit: false, categories: _cats), MenuCategoryChoice.none);
    });

    test('менюда бўлим фильтри танланган → шу бўлим', () {
      expect(MenuCategoryChoice.initial(isEdit: false, filterCategoryId: 'c2', categories: _cats), 'c2');
    });

    test('фильтр ўлик/номаълум id → «Бошқалар»', () {
      expect(MenuCategoryChoice.initial(isEdit: false, filterCategoryId: 'gone', categories: _cats), MenuCategoryChoice.none);
    });

    test('категориялар умуман йўқ (янги ошпаз) → «Бошқалар»', () {
      expect(MenuCategoryChoice.initial(isEdit: false, categories: const []), MenuCategoryChoice.none);
    });
  });

  group('MenuCategoryChoice.initial — таҳрир', () {
    test('таомнинг ўз категорияси сақланади', () {
      expect(MenuCategoryChoice.initial(isEdit: true, existingCategoryId: 'c2', categories: _cats), 'c2');
    });

    test('REGRESSION: категорияси ўчирилган таом жимгина биринчи бўлимга ўтмайди → «Бошқалар»', () {
      expect(MenuCategoryChoice.initial(isEdit: true, existingCategoryId: 'deleted', categories: _cats), MenuCategoryChoice.none);
    });

    test('категориясиз таом категориясиз қолади (фильтр таҳрирга тегмайди)', () {
      expect(
        MenuCategoryChoice.initial(isEdit: true, existingCategoryId: '', filterCategoryId: 'c1', categories: _cats),
        MenuCategoryChoice.none,
      );
    });
  });

  group('MenuCategoryChoice.known', () {
    test('мавжуд id ўзгармайди, номаълум id сақланмайди', () {
      expect(MenuCategoryChoice.known('c1', _cats), 'c1');
      expect(MenuCategoryChoice.known('zzz', _cats), '');
      expect(MenuCategoryChoice.known('', _cats), '');
    });
  });

  group('MenuCategoryChoice — тизим таклифи (D-REST-29)', () {
    test('suggest ↔ suggestedKey: айлантириб қайтади; оддий id ва бўш — null', () {
      expect(MenuCategoryChoice.suggestedKey(MenuCategoryChoice.suggest('drinks')), 'drinks');
      expect(MenuCategoryChoice.suggestedKey('c1'), isNull);
      expect(MenuCategoryChoice.suggestedKey(''), isNull);
    });

    test('номаълум тайёр ном калити тўғри ЭМАС (қўлда ясалган қиймат категорияга айланмайди)', () {
      expect(MenuCategoryChoice.suggestedKey('__suggest__:nope'), isNull);
      expect(MenuCategoryChoice.suggestedKey('__suggest__:'), isNull);
      expect(MenuCategoryChoice.known('__suggest__:nope', _cats), '');
    });

    test('known: тўғри таклиф танлови сақланади (яратилмаган бўлса ҳам)', () {
      final id = MenuCategoryChoice.suggest('hot');
      expect(MenuCategoryChoice.known(id, _cats), id);
      expect(MenuCategoryChoice.known(id, const []), id);
    });
  });

  group('MenuCategoryChoice.findByName — такрорий категория яратилмасин', () {
    test('катта-кичик ҳарф ва ортиқча бўшлиқ эътиборга олинмайди', () {
      expect(MenuCategoryChoice.findByName(_cats, '  таомлар ')?.id, 'c1');
      expect(MenuCategoryChoice.findByName(_cats, 'ИЧИМЛИКЛАР')?.id, 'c2');
      expect(MenuCategoryChoice.findByName(const [MenuCategory(id: 'x', name: 'Ширин  таомлар')], 'ширин таомлар')?.id, 'x');
    });

    test('бошқа ном ёки бўш ном → null', () {
      expect(MenuCategoryChoice.findByName(_cats, 'Салатлар'), isNull);
      expect(MenuCategoryChoice.findByName(_cats, '   '), isNull);
    });
  });

  group('MenuCategoryChoice.chunks — batch чегараси', () {
    test('400 дан бўлакланади', () {
      final parts = MenuCategoryChoice.chunks(List.generate(950, (i) => i));
      expect(parts.map((p) => p.length), [400, 400, 150]);
      expect(parts.expand((p) => p).length, 950);
    });

    test('бўш → бўлак йўқ; аниқ чегара', () {
      expect(MenuCategoryChoice.chunks(<int>[]), isEmpty);
      expect(MenuCategoryChoice.chunks(List.generate(400, (i) => i)).length, 1);
      expect(MenuCategoryChoice.chunks(List.generate(401, (i) => i)).length, 2);
    });
  });
}
