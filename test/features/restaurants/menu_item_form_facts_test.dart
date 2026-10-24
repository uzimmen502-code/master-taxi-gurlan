// Таом формаси + фактлар (D-REST-16/17/24): сақлашда репозиторийга НИМА кетади.
// Асосий хавф — таҳрирда мавжуд фактларнинг индамай ўчиб кетиши ёки хато фактлар
// сақланиб қолиши. Репозиторий қалбаки (Firestore йўқ); ёзув семантикаси
// (`DishFacts.patch`) `dish_facts_test.dart`да, rules — `restaurant_rules.test.js`да.

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/dish_facts.dart';
import 'package:ava_gurlan/features/restaurants/domain/qty_tiers.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/menu_item_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

final _l10n = JsonL10nDelegate();
String _tr(String key) => _l10n.tr(key);

class _Saved {
  _Saved(this.id, this.name, this.price, this.facts, this.categoryId, [this.qtyTiers]);
  final String? id;
  final String name;
  final int price;
  final DishFacts? facts;
  final String categoryId;

  /// `null` — репозиторийга чегирма берилмаган (тегилмайди); бўш — «ўчирилади».
  final List<QtyTier>? qtyTiers;
}

class _FakeRepo implements RestaurantsRepository {
  final saved = <_Saved>[];

  /// upsertCategory чақирувлари: (ном, тартиб рақами).
  final createdCategories = <(String, int)>[];

  @override
  Future<String> upsertMenuItem(
    String restaurantId, {
    String? id,
    required String name,
    required int price,
    String description = '',
    String photoUrl = '',
    String categoryId = '',
    int sort = 0,
    bool available = true,
    DateTime? stopUntil,
    DishFacts? facts,
    List<QtyTier>? qtyTiers,
  }) async {
    saved.add(_Saved(id, name, price, facts, categoryId, qtyTiers));
    return id ?? 'new1';
  }

  @override
  Future<String> upsertCategory(String restaurantId, {String? id, required String name, required int sort}) async {
    createdCategories.add((name, sort));
    return 'cat_${createdCategories.length}';
  }

  @override
  Future<List<Cuisine>> listCuisines({bool force = false}) async => const [
        Cuisine(id: 'national_ozbek', name: 'Ўзбек', group: 'national', names: {'uz_Latn': "O'zbek"}),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<void> _open(
  WidgetTester t,
  _FakeRepo repo, {
  MenuItem? existing,
  List<MenuCategory> categories = const [],
  bool homeCook = false,
}) async {
  t.view.physicalSize = const Size(390 * 3, 2400 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    l10nApp(
      delegate: _l10n,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => MenuItemFormScreen(
                restaurantId: 'r1',
                categories: categories,
                homeCook: homeCook,
                repository: repo,
                existing: existing,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

Finder _field(String key) => find.widgetWithText(TextField, _tr(key));
Finder _save() => find.widgetWithText(FilledButton, _tr('restaurants_m_save'));

Future<void> _fillBasics(WidgetTester t, {String name = 'Osh', String price = '35000'}) async {
  await t.enterText(_field('restaurants_m_item_name'), name);
  await t.enterText(_field('restaurants_m_item_price'), price);
  await t.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester t) async {
  // Форма узайгач «Сақлаш» ListView'да ҳали қурилмаган бўлиши мумкин (ленивый) — аввал пастга суриб топамиз.
  await t.dragUntilVisible(_save(), find.byType(ListView).first, const Offset(0, -400));
  await t.pumpAndSettle();
  await t.tap(_save());
  await t.pumpAndSettle();
}

void main() {
  testWidgets('янги таом, фактсиз: facts БЎШ (null эмас) — «ҳаммаси тозаланган» ҳолат ёзилади, форма ёпилади', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    await _fillBasics(t);
    await _tapSave(t);
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.name, 'Osh');
    expect(repo.saved.single.price, 35000);
    expect(repo.saved.single.facts, isNotNull, reason: 'форма фактларни билади — null (тегма) эмас');
    expect(repo.saved.single.facts!.isEmpty, isTrue);
    expect(find.text('open'), findsOneWidget, reason: 'сақлангач форма ёпилди');
  });

  testWidgets('янги таом + порция/кухна/тег киритилса — репозиторийга айнан шу фактлар кетади', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    await _fillBasics(t);

    await t.tap(find.text(_tr('restaurants_m_dish_portion')));
    await t.pumpAndSettle();
    await t.enterText(_field('restaurants_m_dish_servings'), '4');
    await t.tap(find.text(_tr('restaurants_m_dish_tags')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilterChip, _tr('restaurants_m_dish_tag_kids')));
    await t.ensureVisible(find.text(_tr('restaurants_m_dish_cuisine')));
    await t.pumpAndSettle();
    await t.tap(find.text(_tr('restaurants_m_dish_cuisine')));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text(_tr('restaurants_m_dish_group_national'))));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, "O'zbek"));
    await t.pumpAndSettle();
    await _tapSave(t);

    final f = repo.saved.single.facts!;
    expect(f.servings, 4);
    expect(f.tags, ['kids']);
    expect(f.cuisineGroup, 'national');
    expect(f.cuisineId, 'national_ozbek');
    expect(f.validate(), isEmpty);
  });

  testWidgets('теглар: Дастурхон ва 5 та мавсум теги формада бор; 5 тадан ортиқ танланса сақланмайди (≤ 4)', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    await _fillBasics(t);
    await t.tap(find.text(_tr('restaurants_m_dish_tags')));
    await t.pumpAndSettle();
    for (final tag in [DishTag.dastarxon, ...DishTag.seasons]) {
      expect(find.widgetWithText(FilterChip, _tr('restaurants_m_dish_tag_$tag')), findsOneWidget, reason: tag);
    }
    for (final tag in [DishTag.kids, DishTag.light, DishTag.dastarxon, DishTag.ramadan, DishTag.navruz]) {
      await t.tap(find.widgetWithText(FilterChip, _tr('restaurants_m_dish_tag_$tag')));
      await t.pump();
    }
    await _tapSave(t);
    expect(repo.saved, isEmpty, reason: '5 та тег — сақланмайди');
    expect(find.text(_tr('restaurants_m_dish_err_tags')), findsWidgets);
  });
  testWidgets('ХАТОЛИ факт (калория мос эмас) сақланмайди: репозиторий чақирилмайди, хабар ва хатоли карточка очилади', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    await _fillBasics(t);
    await t.tap(find.text(_tr('restaurants_m_dish_nutrition')));
    await t.pumpAndSettle();
    await t.enterText(_field('restaurants_m_dish_kcal'), '900');
    await t.enterText(_field('restaurants_m_dish_protein'), '30');
    await t.enterText(_field('restaurants_m_dish_fat'), '25');
    await t.enterText(_field('restaurants_m_dish_carbs'), '60');
    await t.pumpAndSettle();
    await _tapSave(t);

    expect(repo.saved, isEmpty, reason: 'хато факт ёзилмайди');
    expect(find.text(_tr('restaurants_m_dish_err_fix')), findsOneWidget);
    expect(find.textContaining('585'), findsWidgets, reason: 'карточкада тахминий 585 ккал кўрсатилган');
    expect(find.text('open'), findsNothing, reason: 'форма ёпилмади');

    // Тузатилса — сақланади
    await t.enterText(_field('restaurants_m_dish_kcal'), '600');
    await t.pumpAndSettle();
    await _tapSave(t);
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.facts!.kcal, 600);
  });

  testWidgets('тугалланмаган КБЖУ (фақат калория) ҳам сақланмайди — «ярим» маълумот ҳужжатга тушмайди', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    await _fillBasics(t);
    await t.tap(find.text(_tr('restaurants_m_dish_nutrition')));
    await t.pumpAndSettle();
    await t.enterText(_field('restaurants_m_dish_kcal'), '300');
    await t.pumpAndSettle();
    await _tapSave(t);
    expect(repo.saved, isEmpty);
    expect(find.text(_tr('restaurants_m_dish_err_nutrition_incomplete')), findsOneWidget);
  });

  testWidgets('таҳрир: тегмасдан сақланса — мавжуд фактлар САҚЛАНАДИ (индамай ўчмайди)', (t) async {
    const facts = DishFacts(servings: 4, weightG: 450, tags: ['kids']);
    final repo = _FakeRepo();
    await _open(t, repo, existing: const MenuItem(id: 'osh', name: 'Osh', price: 35000, facts: facts));
    await _tapSave(t);
    final saved = repo.saved.single;
    expect(saved.id, 'osh');
    expect(saved.facts!.servings, 4);
    expect(saved.facts!.weightG, 450);
    expect(saved.facts!.tags, ['kids']);
  });

  testWidgets('таҳрир: сотувчи порция сонини тозаласа — facts.servings null (репозиторий ҳужжатдан ўчиради)', (t) async {
    const facts = DishFacts(servings: 4, weightG: 450);
    final repo = _FakeRepo();
    await _open(t, repo, existing: const MenuItem(id: 'osh', name: 'Osh', price: 35000, facts: facts));
    await t.enterText(_field('restaurants_m_dish_servings'), '');
    await t.pumpAndSettle();
    await _tapSave(t);
    final saved = repo.saved.single.facts!;
    expect(saved.servings, isNull);
    expect(saved.weightG, 450, reason: 'бошқа майдонлар сақланади');
    // Репозиторий патчи: null → «ўчириш», қолгани қиймат (қаранг: DishFacts.patch тести)
    const gone = Object();
    expect(DishFacts.patch(saved, gone)['servings'], same(gone));
    expect(DishFacts.patch(saved, gone)['weightG'], 450);
  });

  // ── Қадоқлаш йўқ (D-REST-28) ва категория таклифи (D-REST-29) ──────────

  testWidgets('қадоқлаш майдони ЙЎҚ (D-REST-28): формада қадоқлаш ёзуви ва майдони кўринмайди', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    final labels = t
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => '${f.decoration?.labelText}')
        .toList();
    expect(labels.where((l) => l.toLowerCase().contains('qadoq') || l.contains('packaging')), isEmpty, reason: '$labels');
    expect(find.textContaining('Qadoq'), findsNothing);
  });

  testWidgets('янги сотувчи: тизим кафе учун 7 та бўлим таклиф қилади, ҲЕЧ БИРИ ўзи танланмайди («Boshqalar»)', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    for (final key in ['first', 'second', 'salads', 'shashlik', 'fastfood', 'drinks', 'sweets']) {
      expect(find.byKey(ValueKey('category-suggest-$key')), findsOneWidget, reason: key);
    }
    expect(find.byKey(const ValueKey('category-suggest-hot')), findsNothing, reason: 'уй ошпази рўйхати эмас');
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('category-none'))).selected, isTrue);
    expect(find.text(_tr('restaurants_m_item_category_suggest_hint')), findsOneWidget);
    expect(repo.createdCategories, isEmpty, reason: 'кўриш ҳужжат яратмайди');
  });

  testWidgets('уй ошпази: қисқа таклиф (4 та)', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo, homeCook: true);
    final suggested = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith('category-suggest-'));
    expect(suggested, findsNWidgets(4));
  });

  testWidgets('таклифни танлаш + сақлаш: бўлим САҚЛАШДА эганинг тилида яратилади ва таом шунга боғланади', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    await _fillBasics(t);
    await t.tap(find.byKey(const ValueKey('category-suggest-first')));
    await t.pumpAndSettle();
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('category-suggest-first'))).selected, isTrue);
    expect(repo.createdCategories, isEmpty, reason: 'танлаш ўзи ҳужжат яратмайди');
    await _tapSave(t);
    expect(repo.createdCategories, [('Birinchi taomlar', 0)]);
    expect(repo.saved.single.categoryId, 'cat_1');
  });

  testWidgets('таклиф танланиб, кейин «Boshqalar»га қайтилса — бўлим ЯРАТИЛМАЙДИ, таом категориясиз', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    await _fillBasics(t);
    await t.tap(find.byKey(const ValueKey('category-suggest-drinks')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('category-none')));
    await t.pumpAndSettle();
    await _tapSave(t);
    expect(repo.createdCategories, isEmpty);
    expect(repo.saved.single.categoryId, '');
  });

  testWidgets('мавжуд бўлим танланади (янги яратилмайди); аллақачон бор бўлим таклифдан чиқади (бошқа ёзувда ҳам)', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo, categories: const [
      MenuCategory(id: 'c1', name: 'Таомлар', sort: 0),
      MenuCategory(id: 'c2', name: 'Birinchi taomlar', sort: 1),
    ]);
    expect(find.byKey(const ValueKey('category-suggest-first')), findsNothing, reason: '«Биринчи таомлар» (лотинда) бор — такрор таклиф йўқ');
    expect(find.byKey(const ValueKey('category-suggest-second')), findsOneWidget);
    await _fillBasics(t);
    await t.tap(find.byKey(const ValueKey('category-c1')));
    await t.pumpAndSettle();
    await _tapSave(t);
    expect(repo.createdCategories, isEmpty);
    expect(repo.saved.single.categoryId, 'c1');
  });

  testWidgets('таҳрир: таомнинг категорияси танланган кўринади; таклиф қилинмаган нарса ўзгармайди', (t) async {
    final repo = _FakeRepo();
    await _open(
      t,
      repo,
      categories: const [MenuCategory(id: 'c1', name: 'Таомлар')],
      existing: const MenuItem(id: 'osh', name: 'Osh', price: 35000, categoryId: 'c1'),
    );
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('category-c1'))).selected, isTrue);
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('category-none'))).selected, isFalse);
    await _tapSave(t);
    expect(repo.saved.single.categoryId, 'c1');
    expect(repo.createdCategories, isEmpty);
  });

  testWidgets('«Ўз категориям»: диалог → янги бўлим яратилади ва танланади → таом шунга боғланади', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    await _fillBasics(t);
    await t.ensureVisible(find.byKey(const ValueKey('category-create-own')));
    await t.tap(find.byKey(const ValueKey('category-create-own')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('category-name-field')), 'Palov');
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, _tr('restaurants_m_save'))));
    await t.pumpAndSettle();
    expect(repo.createdCategories, [('Palov', 0)]);
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('category-cat_1'))).selected, isTrue);
    await _tapSave(t);
    expect(repo.createdCategories, hasLength(1), reason: 'такрор яратилмади');
    expect(repo.saved.single.categoryId, 'cat_1');
  });

  testWidgets('асосий талаблар (ном/нарх) бўш бўлса — фактлардан қатъи назар ёзилмайди', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    await _tapSave(t);
    expect(repo.saved, isEmpty);
    expect(find.text(_tr('restaurants_m_err_item')), findsOneWidget);
  });

  testWidgets('бўш ном/нарх: ҳар майдон остида ўз хатоси, тўлдирилса шу майдонники кетади (#3)', (t) async {
    final repo = _FakeRepo();
    await _open(t, repo);
    expect(find.text(_tr('restaurants_m_err_item_name')), findsNothing, reason: 'юборишдан олдин хато йўқ');
    await _tapSave(t);
    final name = _field('restaurants_m_item_name');
    final price = _field('restaurants_m_item_price');
    expect(find.descendant(of: name, matching: find.text(_tr('restaurants_m_err_item_name'))), findsOneWidget);
    expect(find.descendant(of: price, matching: find.text(_tr('restaurants_m_err_item_price'))), findsOneWidget);
    await t.enterText(name, 'Osh');
    await t.pump();
    expect(find.text(_tr('restaurants_m_err_item_name')), findsNothing);
    expect(find.text(_tr('restaurants_m_err_item_price')), findsOneWidget);
  });
}
