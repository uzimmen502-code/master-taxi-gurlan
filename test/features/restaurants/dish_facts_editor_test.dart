// Таом формасидаги «Мижоз учун қўшимча маълумот» блоки (D-REST-16/17/24):
// ҳақиқий uz_Latn матнлари билан (калит қолиб кетса — хом калит чиқади ва тест йиқилади),
// тор экран (320) ва катта шрифт (×2) да ҳам синмаслиги.

import 'package:ava_gurlan/core/theme/ava_tokens.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/dish_facts.dart';
import 'package:ava_gurlan/features/restaurants/merchant/dish_facts_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

const _ozbek = Cuisine(id: 'national_ozbek', name: 'Ўзбек', group: 'national', names: {'uz_Latn': "O'zbek", 'uz_Cyrl': 'Ўзбек', 'ru': 'Узбекская'});
const _xorazm = Cuisine(id: 'national_xorazm', name: 'Хоразм', group: 'national', names: {'uz_Latn': 'Xorazm', 'uz_Cyrl': 'Хоразм', 'ru': 'Хорезмская'});
const _turk = Cuisine(id: 'world_turk', name: 'Турк', group: 'world', names: {'uz_Latn': 'Turk', 'uz_Cyrl': 'Турк', 'ru': 'Турецкая'});

class _Harness {
  _Harness({
    this.initial = DishFacts.empty,
    String price = '35000',
    this.addResult,
    this.addError,
  }) : priceController = TextEditingController(text: price);

  final DishFacts initial;
  final TextEditingController priceController;
  final List<Cuisine> cuisines = const [_ozbek, _xorazm, _turk];
  final Cuisine Function(String name, String group)? addResult;
  final Object? addError;

  final showErrors = ValueNotifier<bool>(false);
  DishFacts? last;
  int cuisineLoads = 0;
  final added = <(String, String)>[];

  Future<void> pump(WidgetTester t, {double width = 390, double textScale = 1.0}) async {
    t.view.physicalSize = Size(width * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      l10nApp(
        textScale: textScale,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder<bool>(
              valueListenable: showErrors,
              builder: (context, show, _) => DishFactsEditor(
                initial: initial,
                priceController: priceController,
                showErrors: show,
                onChanged: (f) => last = f,
                loadCuisines: () async {
                  cuisineLoads += 1;
                  return cuisines;
                },
                addCuisine: (name, group) async {
                  added.add((name, group));
                  if (addError != null) throw addError!;
                  return addResult!(name, group);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }
}

Finder _text(String s) => find.text(s);
Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  testWidgets('бошланғич ҳолат: 4 та ёпиқ карточка, 0 / 4, ичидаги майдонлар кўринмайди (прогрессив очиш)', (t) async {
    final h = _Harness();
    await h.pump(t);
    expect(_text('0 / 4'), findsOneWidget);
    for (final title in ['Porsiya', 'Tarkibi (KBJU)', 'Oshxona', 'Belgilar']) {
      expect(_text(title), findsOneWidget, reason: title);
    }
    expect(_text('Mijoz uchun qo\'shimcha ma\'lumot'), findsOneWidget);
    expect(_field('Necha kishilik porsiya'), findsNothing);
    expect(_field('Kaloriya (kkal)'), findsNothing);
    expect(h.cuisineLoads, 0, reason: 'кухналар карточка очилмагунча юкланмайди (ўқишлар тежалади)');
    expect(h.last, isNull, reason: 'ҳеч нарса ўзгармади — onChanged чақирилмайди');
  });

  testWidgets('порция: чип ва майдон; бир кишилик нарх нарх ўзгарганда янгиланади; грамм', (t) async {
    final h = _Harness(price: '35000');
    await h.pump(t);
    await t.tap(_text('Porsiya'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(ChoiceChip, '4'));
    await t.pumpAndSettle();
    expect(h.last!.servings, 4);
    expect(_text('Bir kishilik narx: 8 750 so\'m'), findsOneWidget);
    expect((t.widget(_field('Necha kishilik porsiya')) as TextField).controller!.text, '4');

    h.priceController.text = '10000';
    await t.pumpAndSettle();
    expect(_text('Bir kishilik narx: 2 500 so\'m'), findsOneWidget, reason: 'нарх таом майдонидан жонли');

    await t.enterText(_field('Necha kishilik porsiya'), '3');
    await t.pumpAndSettle();
    expect(_text('Bir kishilik narx: 3 334 so\'m'), findsOneWidget, reason: 'юқорига яхлитланади');

    await t.enterText(_field('Porsiya og\'irligi (gramm)'), '450');
    await t.pumpAndSettle();
    expect(h.last!.weightG, 450);
    expect(_text('3 kishilik · 450 g'), findsOneWidget, reason: 'ёпиқ карточка қисқача мазмуни');
    expect(_text('1 / 4'), findsOneWidget);
  });

  testWidgets('порция сони чегарадан ташқари (51) — жонли хато; тўғриланса йўқолади', (t) async {
    final h = _Harness();
    await h.pump(t);
    await t.tap(_text('Porsiya'));
    await t.pumpAndSettle();
    await t.enterText(_field('Necha kishilik porsiya'), '51');
    await t.pumpAndSettle();
    expect(_text('Porsiya soni 1 dan 50 gacha bo\'lishi kerak'), findsOneWidget);
    expect(h.last!.validate(), [DishFactsError.servings]);
    await t.enterText(_field('Necha kishilik porsiya'), '50');
    await t.pumpAndSettle();
    expect(_text('Porsiya soni 1 dan 50 gacha bo\'lishi kerak'), findsNothing);
  });

  testWidgets('КБЖУ: тўғри → «мос» ёзуви ва диаграмма ёзуви; калория мос эмас → хато (тахминий 585 билан); тузатилса йўқолади', (t) async {
    final h = _Harness();
    await h.pump(t);
    await t.tap(_text('Tarkibi (KBJU)'));
    await t.pumpAndSettle();

    await t.enterText(_field('Kaloriya (kkal)'), '600');
    await t.enterText(_field('Oqsil (g)'), '30');
    await t.enterText(_field('Yog\' (g)'), '25');
    await t.enterText(_field('Uglevod (g)'), '60');
    await t.pumpAndSettle();
    expect(h.last!.hasNutrition, isTrue);
    expect(_text('Makroelementlar bo\'yicha ≈ 585 kkal — mos'), findsOneWidget);
    // Диаграмма легендаси — РАҚАМ билан (ранг ягона белги эмас)
    expect(_text('Oqsil 30 g'), findsOneWidget);
    expect(_text('Yog\' 25 g'), findsOneWidget);
    expect(_text('Uglevod 60 g'), findsOneWidget);
    expect(_text('600 kkal'), findsOneWidget, reason: 'ёпиқ карточка мазмуни (очиқда ҳам сарлавҳа остида)');

    await t.enterText(_field('Kaloriya (kkal)'), '800');
    await t.pumpAndSettle();
    expect(find.textContaining('taxminan 585 kkal chiqadi'), findsOneWidget);
    expect(_text('Makroelementlar bo\'yicha ≈ 585 kkal — mos'), findsNothing);
    expect(h.last!.validate(), [DishFactsError.nutritionMismatch]);

    await t.enterText(_field('Kaloriya (kkal)'), '600');
    await t.pumpAndSettle();
    expect(find.textContaining('taxminan 585 kkal chiqadi'), findsNothing);
  });

  testWidgets('КБЖУ диаграммаси ЧИЗИЛАДИ (қурилмада сегментлар 0 баландликда кўринмай қолган эди): баландлик 10, эни калорияга ҳисса (О120 : Ё225 : У240)', (t) async {
    final h = _Harness(initial: const DishFacts(kcal: 600, protein: 30, fat: 25, carbs: 60));
    await h.pump(t);
    Size seg(Color color) => t.getSize(find.byWidgetPredicate((w) => w is ColoredBox && w.color == color));
    final p = seg(AvaMacroColors.light.protein);
    final f = seg(AvaMacroColors.light.fat);
    final c = seg(AvaMacroColors.light.carbs);
    for (final s in [p, f, c]) {
      expect(s.height, 10, reason: 'сегмент кўринадиган баландликда');
      expect(s.width, greaterThan(0));
    }
    expect(c.width, greaterThan(f.width));
    expect(f.width, greaterThan(p.width));
    // Ҳисса: 120:225:240 (2 та 2px бўшлиқ чиқарилгач) — 2 % аниқликда
    final total = p.width + f.width + c.width;
    expect(p.width / total, closeTo(120 / 585, 0.02));
    expect(f.width / total, closeTo(225 / 585, 0.02));
    expect(c.width / total, closeTo(240 / 585, 0.02));
  });

  testWidgets('хатоли карточка «тўлдирилган» эмас: яшил белги ва ҳисоб йўқ, қизил хато белгиси бор (калория мос эмас)', (t) async {
    final h = _Harness(initial: const DishFacts(kcal: 900, protein: 30, fat: 25, carbs: 60));
    await h.pump(t);
    expect(_text('0 / 4'), findsOneWidget, reason: 'хатоли КБЖУ ҳисобга кирмайди');
    expect(find.byIcon(Icons.check_rounded), findsNothing, reason: 'яшил белги йўқ');
    expect(find.byIcon(Icons.error_outline_rounded), findsWidgets);
  });

  testWidgets('танланган чип рангдан ТАШҚАРИ ҳам ажралади (қалин контур), порция чипида белги (✓) йўқ — ён-ёнига сиғади', (t) async {
    final h = _Harness();
    await h.pump(t);
    await t.tap(_text('Porsiya'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, '4'));
    await t.pumpAndSettle();
    ChoiceChip chip(String n) => t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, n));
    expect(chip('4').selected, isTrue);
    expect(chip('4').side!.width, 1.5);
    expect(chip('3').side!.width, 1.0);
    expect(chip('4').showCheckmark, isFalse);
    // 390 px да 6 та чип БИР қаторда (ўнгдан-чапга бир хил y)
    final ys = [for (final n in ['1', '2', '3', '4', '5', '6']) t.getTopLeft(find.widgetWithText(ChoiceChip, n)).dy];
    expect(ys.toSet(), hasLength(1), reason: 'чиплар қаторга сиғди: $ys');
  });

  testWidgets('КБЖУ тугалланмаган: ёзиш пайтида хато эмас; «сақлаш» уринишидан кейин (showErrors) кўринади ва карточка очилади', (t) async {
    final h = _Harness();
    await h.pump(t);
    await t.tap(_text('Tarkibi (KBJU)'));
    await t.pumpAndSettle();
    await t.enterText(_field('Kaloriya (kkal)'), '300');
    await t.pumpAndSettle();
    expect(find.textContaining('to\'rttasi ham kiritilishi kerak'), findsNothing, reason: 'ёзаётганда безовта қилмайди');
    expect(h.last!.validate(), [DishFactsError.nutritionIncomplete]);

    // Карточкани ёпамиз, кейин сақлаш уриниши
    await t.tap(_text('Tarkibi (KBJU)'));
    await t.pumpAndSettle();
    h.showErrors.value = true;
    await t.pumpAndSettle();
    expect(find.textContaining('to\'rttasi ham kiritilishi kerak'), findsOneWidget, reason: 'хатоли карточка автомат очилди');
  });

  testWidgets('кухна: аввал гуруҳ; гуруҳ бўйича чиплар; танлаш; гуруҳ алмашса кухна тозаланади; қайта босилса бекор', (t) async {
    final h = _Harness();
    await h.pump(t);
    await t.tap(_text('Oshxona'));
    await t.pumpAndSettle();
    expect(h.cuisineLoads, 1);
    expect(_text('Avval «Milliy» yoki «Dunyo»ni tanlang'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Xorazm'), findsNothing);

    // SegmentedButton'нинг сегменти — ёзув бўйича босамиз
    await t.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('Milliy')));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Xorazm'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'O\'zbek'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Turk'), findsNothing, reason: 'бошқа гуруҳники кўринмайди');

    await t.tap(find.widgetWithText(ChoiceChip, 'Xorazm'));
    await t.pumpAndSettle();
    expect(h.last!.cuisineGroup, 'national');
    expect(h.last!.cuisineId, 'national_xorazm');
    expect(_text('1 / 4'), findsOneWidget);

    await t.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('Dunyo')));
    await t.pumpAndSettle();
    expect(h.last!.cuisineId, isNull, reason: 'гуруҳ алмашди — эски гуруҳ кухнаси тозаланди');
    expect(h.last!.cuisineGroup, 'world');
    expect(h.last!.validate(), [DishFactsError.cuisine], reason: 'гуруҳ бор, кухна йўқ — тўлиқсиз (сақлашда кўрсатилади)');
    expect(find.widgetWithText(ChoiceChip, 'Turk'), findsOneWidget);
    expect(h.cuisineLoads, 1, reason: 'рўйхат қайта юкланмади');

    await t.tap(find.widgetWithText(ChoiceChip, 'Turk'));
    await t.pumpAndSettle();
    expect(h.last!.validate(), isEmpty);
    await t.tap(find.widgetWithText(ChoiceChip, 'Turk'));
    await t.pumpAndSettle();
    expect(h.last!.cuisineId, isNull, reason: 'қайта босилса танлов бекор');
  });

  testWidgets('ўз номини қўшиш: диалог → сервер (ном, гуруҳ) → янги чип танланади; 2 ҳарфдан қисқа ном тугмаси ўчиқ', (t) async {
    final h = _Harness(
      addResult: (name, group) => Cuisine(id: 'national_qashqadaryo-milliy-taomlari', name: name, group: group),
    );
    await h.pump(t);
    await t.tap(_text('Oshxona'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('Milliy')));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(ActionChip, 'O\'z nomimni qo\'shish'));
    await t.pumpAndSettle();
    expect(_text('Yangi nom'), findsOneWidget);
    FilledButton okButton() => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Qo\'shish'));
    expect(okButton().onPressed, isNull, reason: 'бўш ном');
    await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Q');
    await t.pumpAndSettle();
    expect(okButton().onPressed, isNull, reason: '1 ҳарф');
    await t.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      '  Qashqadaryo   milliy taomlari ',
    );
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Qo\'shish'));
    await t.pumpAndSettle();

    expect(h.added, [('Qashqadaryo milliy taomlari', 'national')], reason: 'бўшлиқлар тозаланган');
    expect(h.last!.cuisineId, 'national_qashqadaryo-milliy-taomlari');
    expect(h.last!.cuisineGroup, 'national');
    expect(find.widgetWithText(ChoiceChip, 'Qashqadaryo milliy taomlari'), findsOneWidget, reason: 'янги чип рўйхатга тушди');
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Qashqadaryo milliy taomlari')).selected, isTrue);
  });

  testWidgets('ўз номини қўшиш хато берса (кунлик лимит) — тушунарли хабар, танлов ўзгармайди', (t) async {
    final h = _Harness(
      addError: const RestaurantsException('resource-exhausted', 'CUISINE_RATE_LIMIT', 'x'),
    );
    await h.pump(t);
    await t.tap(_text('Oshxona'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('Dunyo')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ActionChip, 'O\'z nomimni qo\'shish'));
    await t.pumpAndSettle();
    await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Gruzin');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Qo\'shish'));
    await t.pumpAndSettle();
    expect(h.added, [('Gruzin', 'world')]);
    expect(find.textContaining('Bugun juda ko\'p yangi nom'), findsOneWidget);
    expect(h.last?.cuisineId, isNull);
  });

  testWidgets('кухналар юкланмаса — хато ва «Qayta urinish»; босилса қайта юкланади (гуруҳ танлаш ҳам автомат қайта уринади)', (t) async {
    var calls = 0;
    final h = _Harness();
    t.view.physicalSize = const Size(390 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DishFactsEditor(
              initial: DishFacts.empty,
              priceController: h.priceController,
              onChanged: (f) => h.last = f,
              loadCuisines: () async {
                calls += 1;
                // 1: карточка очилганда, 2: гуруҳ танланганда (автомат қайта уриниш) — иккаласи ҳам йиқилади
                if (calls <= 2) throw StateError('offline');
                return [_xorazm];
              },
              addCuisine: (n, g) async => throw UnimplementedError(),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(_text('Oshxona'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('Milliy')));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(_text('Ro\'yxatni yuklab bo\'lmadi'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Qayta urinish'));
    await t.pumpAndSettle();
    expect(calls, 3);
    expect(find.widgetWithText(ChoiceChip, 'Xorazm'), findsOneWidget);
  });

  testWidgets('белгилар: бир нечтасини танлаш; тартиб DishTag.all бўйича (барқарор); қайта босилса олиб ташланади', (t) async {
    final h = _Harness();
    await h.pump(t);
    await t.tap(_text('Belgilar'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilterChip, 'Yengil va sog\'lom'));
    await t.tap(find.widgetWithText(FilterChip, 'Bolalar uchun'));
    await t.pumpAndSettle();
    expect(h.last!.tags, ['kids', 'light'], reason: 'босилиш тартибидан мустақил');
    expect(_text('Bolalar uchun · Yengil va sog\'lom'), findsOneWidget);
    await t.tap(find.widgetWithText(FilterChip, 'Bolalar uchun'));
    await t.pumpAndSettle();
    expect(h.last!.tags, ['light']);
  });

  testWidgets('таҳрир: мавжуд фактлар майдонларга тўлдирилади, карточкалар очиқ, 4 / 4; ўзгартирмасдан ҳам тўғри', (t) async {
    const full = DishFacts(
      servings: 4,
      weightG: 450,
      kcal: 600,
      protein: 30,
      fat: 25,
      carbs: 60,
      cuisineGroup: 'national',
      cuisineId: 'national_ozbek',
      tags: ['kids'],
    );
    final h = _Harness(initial: full);
    await h.pump(t);
    expect(_text('4 / 4'), findsOneWidget);
    expect((t.widget(_field('Necha kishilik porsiya')) as TextField).controller!.text, '4');
    expect((t.widget(_field('Kaloriya (kkal)')) as TextField).controller!.text, '600');
    expect(_text('Bir kishilik narx: 8 750 so\'m'), findsOneWidget);
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'O\'zbek')).selected, isTrue, reason: 'танланган кухна');
    expect(t.widget<FilterChip>(find.widgetWithText(FilterChip, 'Bolalar uchun')).selected, isTrue);
    expect(h.last, isNull, reason: 'фойдаланувчи тегмагунча onChanged чақирилмайди');
  });

  testWidgets('танланган кухна рўйхатда йўқ (яширилган) — «Tanlangan» чипи ва тозалаш имконияти', (t) async {
    final h = _Harness(
      initial: const DishFacts(cuisineGroup: 'national', cuisineId: 'national_yashirin'),
    );
    await h.pump(t);
    expect(find.widgetWithText(InputChip, 'Tanlangan'), findsOneWidget);
    // Ўчириш белгиси платформа иконкаси — виджетнинг ўз `onDeleted` қайтариши билан босамиз.
    t.widget<InputChip>(find.widgetWithText(InputChip, 'Tanlangan')).onDeleted!();
    await t.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Tanlangan'), findsNothing);
    expect(h.last!.cuisineId, isNull);
    expect(h.last!.cuisineGroup, 'national');
  });

  for (final w in [320.0, 360.0]) {
    testWidgets('тор экран ${w.toInt()} px, шрифт ×2, ҳамма карточка очиқ ва тўлдирилган — overflow ва истисно йўқ', (t) async {
      const full = DishFacts(
        servings: 4,
        weightG: 450,
        kcal: 600,
        protein: 30,
        fat: 25,
        carbs: 60,
        cuisineGroup: 'national',
        cuisineId: 'national_ozbek',
        tags: ['kids', 'breakfast', 'night', 'light'],
      );
      final h = _Harness(initial: full);
      await h.pump(t, width: w, textScale: 2.0);
      expect(t.takeException(), isNull);
      // КБЖУ хатоси ҳам тор экранда синмайди
      await t.enterText(_field('Kaloriya (kkal)'), '900');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.textContaining('taxminan 585 kkal chiqadi'), findsOneWidget);
    });
  }

  testWidgets('dispose: виджет олиб ташланса истисно йўқ (контроллерлар тозаланади)', (t) async {
    final h = _Harness(initial: const DishFacts(servings: 2));
    await h.pump(t);
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
