import 'package:ava_gurlan/features/restaurants/domain/menu_category_suggestions.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/menu_category_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _name(String k) => 'N:$k';

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

    test('аллақачон бор бўлим (ҳарф катталиги/бўшлиқсиз) қайта таклиф қилинмайди', () {
      final out = MenuCategorySuggestions.missingNames(
        keys: const ['hot', 'sweets', 'drinks'],
        name: _name,
        existing: const [MenuCategory(id: 'x', name: ' n:hot ')],
      );
      expect(out, ['N:sweets', 'N:drinks']);
    });

    test('ҳаммаси бор → бўш; ҳеч нарса йўқ → ҳаммаси', () {
      expect(
        MenuCategorySuggestions.missingNames(keys: const ['hot'], name: _name, existing: const [MenuCategory(id: 'x', name: 'N:hot')]),
        isEmpty,
      );
      expect(MenuCategorySuggestions.missingNames(keys: const ['hot', 'sweets'], name: _name, existing: const []), ['N:hot', 'N:sweets']);
    });

    test('матн калити', () {
      expect(MenuCategorySuggestions.textKey('hot'), 'restaurants_cat_hot');
    });
  });

  group('promptMenuCategoryName — чиплар', () {
    Future<String?> open(WidgetTester t, {MenuCategory? existing, List<MenuCategory> cats = const [], bool homeCook = true}) async {
      String? result = 'unset';
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => result = await promptMenuCategoryName(ctx, existing: existing, categories: cats, homeCook: homeCook),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('янги категория: уй ошпази учун 4 та чип; босилса майдонга ёзилади ва таҳрирланади', (t) async {
      await open(t);
      final chips = find.byType(ActionChip);
      expect(chips, findsNWidgets(4));

      await t.tap(chips.first);
      await t.pump();
      final field = t.widget<TextField>(find.byKey(const ValueKey('category-name-field')));
      expect(field.controller!.text, isNotEmpty);
      expect(field.controller!.text, MenuCategorySuggestions.textKey('hot'), reason: 'тест муҳитида матн калити қайтади');
    });

    testWidgets('кафе учун 7 та чип', (t) async {
      await open(t, homeCook: false);
      expect(find.byType(ActionChip), findsNWidgets(7));
    });

    testWidgets('мавжуд бўлим таклифдан чиқарилади', (t) async {
      await open(t, cats: [MenuCategory(id: 'x', name: MenuCategorySuggestions.textKey('hot'))]);
      expect(find.byType(ActionChip), findsNWidgets(3));
    });

    testWidgets('қайта номлашда чип ва тушунтириш қатори йўқ', (t) async {
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
