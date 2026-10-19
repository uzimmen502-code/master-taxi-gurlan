import 'package:ava_gurlan/features/restaurants/domain/menu_category_suggestions.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/menu_category_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MenuCategorySuggestions', () {
    test('уй ошпази қисқа, кафе кенгроқ; бошланғич 3 тадан', () {
      expect(MenuCategorySuggestions.keysFor(homeCook: true).length, 4);
      expect(MenuCategorySuggestions.keysFor(homeCook: false).length, 7);
      expect(MenuCategorySuggestions.starterKeysFor(homeCook: true).length, 3);
      expect(MenuCategorySuggestions.starterKeysFor(homeCook: false).length, 3);
    });

    test('бошланғичлар таклиф рўйхатининг ичида', () {
      for (final homeCook in [true, false]) {
        final all = MenuCategorySuggestions.keysFor(homeCook: homeCook);
        expect(MenuCategorySuggestions.starterKeysFor(homeCook: homeCook).every(all.contains), isTrue);
      }
    });

    test('калитлар такрорланмайди', () {
      for (final l in [MenuCategorySuggestions.homeCook, MenuCategorySuggestions.cafe]) {
        expect(l.toSet().length, l.length);
      }
    });

    test('таклиф қилинадиган ҳар бир калит жадвалда бор', () {
      for (final k in [...MenuCategorySuggestions.homeCook, ...MenuCategorySuggestions.cafe]) {
        for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
          expect(MenuCategoryNamesProbe.has(k, lang), isTrue, reason: '$k/$lang');
        }
      }
    });

    test('аллақачон бор бўлим (ҳарф катталиги, бўшлиқ, БОШҚА ТИЛ ва ёзувда ҳам) қайта таклиф қилинмайди', () {
      for (final existing in [' иссиқ таомлар ', 'Issiq taomlar', 'Горячие блюда']) {
        final out = MenuCategorySuggestions.missingNames(
          keys: const ['hot', 'sweets', 'drinks'],
          lang: 'uz_Cyrl',
          existing: [MenuCategory(id: 'x', name: existing)],
        );
        expect(out, ['Ширинликлар', 'Ичимликлар'], reason: existing);
      }
    });

    test('матн эга тилида: лотин ва рус', () {
      expect(MenuCategorySuggestions.missingNames(keys: const ['hot'], lang: 'uz_Latn', existing: const []), ['Issiq taomlar']);
      expect(MenuCategorySuggestions.missingNames(keys: const ['hot'], lang: 'ru', existing: const []), ['Горячие блюда']);
    });

    test('ҳаммаси бор → бўш', () {
      expect(
        MenuCategorySuggestions.missingNames(
          keys: const ['hot'],
          lang: 'uz_Cyrl',
          existing: const [MenuCategory(id: 'x', name: 'Иссиқ таомлар')],
        ),
        isEmpty,
      );
    });
  });

  group('promptMenuCategoryName — чиплар', () {
    Future<void> open(WidgetTester t, {MenuCategory? existing, List<MenuCategory> cats = const [], bool homeCook = true}) async {
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => promptMenuCategoryName(ctx, existing: existing, categories: cats, homeCook: homeCook),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('янги категория: уй ошпази учун 4 та чип; босилса майдонга ёзилади', (t) async {
      await open(t);
      final chips = find.byType(ActionChip);
      expect(chips, findsNWidgets(4));

      await t.tap(chips.first);
      await t.pump();
      final field = t.widget<TextField>(find.byKey(const ValueKey('category-name-field')));
      expect(field.controller!.text, 'Иссиқ таомлар');
    });

    testWidgets('кафе учун 7 та чип', (t) async {
      await open(t, homeCook: false);
      expect(find.byType(ActionChip), findsNWidgets(7));
    });

    testWidgets('мавжуд бўлим (бошқа ёзувда ҳам) таклифдан чиқарилади', (t) async {
      await open(t, cats: const [MenuCategory(id: 'x', name: 'Issiq taomlar')]);
      expect(find.byType(ActionChip), findsNWidgets(3));
    });

    testWidgets('қайта номлашда чип йўқ', (t) async {
      await open(t, existing: const MenuCategory(id: 'x', name: 'Таомлар'));
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('«Сақлаш» тозаланган номни қайтаради; бўш ном → null', (t) async {
      String? result = 'unset';
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(onPressed: () async => result = await promptMenuCategoryName(ctx), child: const Text('open')),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('category-name-field')), '  Салатлар ');
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(result, 'Салатлар');

      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(result, isNull);
    });
  });
}

/// Тест ёрдамчиси: жадвалда калит ва тил борлигини текширади.
abstract final class MenuCategoryNamesProbe {
  static bool has(String key, String lang) => MenuCategorySuggestionsProbe.name(key, lang).isNotEmpty;
}

abstract final class MenuCategorySuggestionsProbe {
  static String name(String key, String lang) =>
      MenuCategorySuggestions.missingNames(keys: [key], lang: lang, existing: const []).firstOrNull ?? '';
}
