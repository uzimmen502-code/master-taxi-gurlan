// «Миқдорга чегирма» формаси (D-REST-25): редактор ва таом формасига уланиши — сақлашга НИМА кетади,
// хато бўлса сақлаш тўхтайди, таҳрирда мавжуд поғоналар индамай ўчиб кетмайди.

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/dish_facts.dart';
import 'package:ava_gurlan/features/restaurants/domain/qty_tiers.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/menu_item_form_screen.dart';
import 'package:ava_gurlan/features/restaurants/merchant/qty_tiers_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

final _l10n = JsonL10nDelegate();
String _tr(String key) => _l10n.tr(key);

QtyTier _t(int q, int p) => QtyTier(minQty: q, price: p);

class _Repo implements RestaurantsRepository {
  final saved = <({String? id, int price, List<QtyTier>? tiers})>[];

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
    saved.add((id: id, price: price, tiers: qtyTiers));
    return id ?? 'new1';
  }

  @override
  Future<List<Cuisine>> listCuisines({bool force = false}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('QtyTiersEditor', () {
    late TextEditingController price;
    QtyTiersDraft? last;

    Future<void> pumpEditor(
      WidgetTester t, {
      List<QtyTier> initial = const [],
      String base = '40000',
      bool showErrors = false,
      double width = 390,
      double textScale = 1.0,
    }) async {
      t.view.physicalSize = Size(width * 3, 2000 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      price = TextEditingController(text: base);
      addTearDown(price.dispose);
      last = null;
      await t.pumpWidget(l10nApp(
        delegate: _l10n,
        textScale: textScale,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QtyTiersEditor(
              key: UniqueKey(),
              initial: initial,
              priceController: price,
              showErrors: showErrors,
              onChanged: (d) => last = d,
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    Finder minField(int i) => find.byKey(ValueKey('qty-tier-min-$i'));
    Finder priceField(int i) => find.byKey(ValueKey('qty-tier-price-$i'));

    testWidgets('бошида йиғилган; очилса ҳинт (чегирмани ресторан беради) ва «Поғона қўшиш»; мавжуд поғоналар билан очиқ', (t) async {
      await pumpEditor(t);
      expect(find.text(_tr('restaurants_m_tiers_title')), findsOneWidget);
      expect(find.text(_tr('restaurants_m_tiers_hint')), findsNothing);
      await t.tap(find.byKey(const ValueKey('qty-tiers-header')));
      await t.pumpAndSettle();
      expect(find.text(_tr('restaurants_m_tiers_hint')), findsOneWidget);
      expect(find.byKey(const ValueKey('qty-tiers-add')), findsOneWidget);
      expect(find.byKey(const ValueKey('qty-tier-min-0')), findsNothing, reason: 'қатор ўзи пайдо бўлмайди');

      await pumpEditor(t, initial: [_t(10, 38000)]);
      expect(find.text(_tr('restaurants_m_tiers_hint')), findsOneWidget, reason: 'поғона бор — очиқ');
      expect((t.widget(minField(0)) as TextField).controller!.text, '10');
      expect((t.widget(priceField(0)) as TextField).controller!.text, '38000');
      expect((t.widget(find.byKey(const ValueKey('qty-tiers-count'))) as Text).data, '1');
    });

    testWidgets('қатор қўшиш/ўчириш; 3 тадан кейин «қўшиш» йўқ; ҳар ўзгаришда тўлиқ қаторлар чиқади', (t) async {
      await pumpEditor(t);
      await t.tap(find.byKey(const ValueKey('qty-tiers-header')));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byKey(const ValueKey('qty-tiers-add')));
        await t.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('qty-tiers-add')), findsNothing, reason: 'энг кўпи 3 та');
      await t.enterText(minField(0), '10');
      await t.enterText(priceField(0), '38000');
      await t.enterText(minField(1), '30');
      await t.enterText(priceField(1), '35000');
      await t.pump();
      expect(last!.tiers, [_t(10, 38000), _t(30, 35000)]);
      expect(last!.hasIncompleteRow, isFalse, reason: 'учинчи қатор бутунлай бўш — эътиборсиз');
      expect(last!.errorsFor(40000), isEmpty);

      await t.tap(find.byKey(const ValueKey('qty-tier-remove-0')));
      await t.pumpAndSettle();
      expect(last!.tiers, [_t(30, 35000)]);
      expect(find.byKey(const ValueKey('qty-tiers-add')), findsOneWidget);
    });

    testWidgets('ярим тўлдирилган қатор — «incomplete»; нарх асосийдан кам эмас — хато матни; тўғри — мисол кўрсатилади', (t) async {
      await pumpEditor(t);
      await t.tap(find.byKey(const ValueKey('qty-tiers-header')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('qty-tiers-add')));
      await t.pumpAndSettle();
      await t.enterText(minField(0), '10');
      await t.pump();
      expect(last!.hasIncompleteRow, isTrue);
      expect(last!.errorsFor(40000), [QtyTiersError.incomplete]);
      expect(find.text(_tr('restaurants_m_tiers_err_incomplete')), findsOneWidget);

      await t.enterText(priceField(0), '40000');
      await t.pump();
      expect(find.text(_tr('restaurants_m_tiers_err_price')), findsOneWidget);
      expect(find.byKey(const ValueKey('qty-tiers-preview')), findsNothing);

      await t.enterText(priceField(0), '32000');
      await t.pump();
      expect(find.byKey(const ValueKey('qty-tiers-error')), findsNothing);
      // 10 та × 32 000 = 320 000, чегирма 80 000 (асосий 40 000)
      final preview = (t.widget(find.byKey(const ValueKey('qty-tiers-preview'))) as Text).data!;
      expect(preview, contains('10'));
      expect(preview, contains('320 000'));
      expect(preview, contains('80 000'));
    });

    testWidgets('асосий нарх тушиб кетса (30 000 < поғона нархи) — хато ҳолати нарх майдони ўзгарганда янгиланади', (t) async {
      await pumpEditor(t, initial: [_t(10, 38000)]);
      await t.enterText(priceField(0), '37000'); // ўзгартириб тегамиз — хато кўрсатиш режими
      await t.pump();
      expect(find.byKey(const ValueKey('qty-tiers-error')), findsNothing);
      price.text = '30000';
      await t.pump();
      expect(find.text(_tr('restaurants_m_tiers_err_price')), findsOneWidget);
      expect(last!.errorsFor(30000), [QtyTiersError.price]);
    });

    testWidgets('showErrors: карточка ўзи очилади ва хато кўринади', (t) async {
      await pumpEditor(t, initial: const []);
      expect(find.byKey(const ValueKey('qty-tiers-error')), findsNothing);
      // ҳолат бўйича: рўйхат бўш — хато йўқ; ярим тўлган қатор билан showErrors
      await pumpEditor(t, initial: [_t(10, 50000)], showErrors: true);
      expect(find.text(_tr('restaurants_m_tiers_err_price')), findsOneWidget);
    });

    testWidgets('тор экран 320 ва шрифт ×2: 3 қатор ва хато матни билан синмайди', (t) async {
      await pumpEditor(t, initial: [_t(10, 50000), _t(30, 60000), _t(40, 70000)], width: 320, textScale: 2.0, showErrors: true);
      expect(t.takeException(), isNull);
    });
  });

  group('MenuItemFormScreen + миқдорга чегирма', () {
    Future<void> openForm(WidgetTester t, _Repo repo, {MenuItem? existing, double width = 390}) async {
      t.view.physicalSize = Size(width * 3, 3000 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        delegate: _l10n,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) => MenuItemFormScreen(restaurantId: 'r1', categories: const [], repository: repo, existing: existing),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    Finder field(String key) => find.widgetWithText(TextField, _tr(key));
    Finder save() => find.widgetWithText(FilledButton, _tr('restaurants_m_save'));

    Future<void> tapSave(WidgetTester t) async {
      await t.ensureVisible(save());
      await t.tap(save());
      await t.pumpAndSettle();
    }

    Future<void> openTiers(WidgetTester t) async {
      await t.ensureVisible(find.byKey(const ValueKey('qty-tiers-header')));
      await t.tap(find.byKey(const ValueKey('qty-tiers-header')));
      await t.pumpAndSettle();
    }

    testWidgets('чегирмасиз янги таом: qtyTiers = БЎШ рўйхат (майдон ўчирилади, тегилмай қолмайди)', (t) async {
      final repo = _Repo();
      await openForm(t, repo);
      await t.enterText(field('restaurants_m_item_name'), 'Osh');
      await t.enterText(field('restaurants_m_item_price'), '35000');
      await tapSave(t);
      expect(repo.saved.single.tiers, isEmpty);
      expect(repo.saved.single.tiers, isNotNull);
    });

    testWidgets('тўғри поғоналар сақланади (10 → 32 000, 30 → 30 000)', (t) async {
      final repo = _Repo();
      await openForm(t, repo);
      await t.enterText(field('restaurants_m_item_name'), 'Plov');
      await t.enterText(field('restaurants_m_item_price'), '35000');
      await openTiers(t);
      for (var i = 0; i < 2; i++) {
        await t.ensureVisible(find.byKey(const ValueKey('qty-tiers-add')));
        await t.tap(find.byKey(const ValueKey('qty-tiers-add')));
        await t.pumpAndSettle();
      }
      await t.enterText(find.byKey(const ValueKey('qty-tier-min-0')), '10');
      await t.enterText(find.byKey(const ValueKey('qty-tier-price-0')), '32000');
      await t.enterText(find.byKey(const ValueKey('qty-tier-min-1')), '30');
      await t.enterText(find.byKey(const ValueKey('qty-tier-price-1')), '30000');
      await t.pumpAndSettle();
      await tapSave(t);
      expect(repo.saved.single.tiers, [_t(10, 32000), _t(30, 30000)]);
      expect(find.text('open'), findsOneWidget, reason: 'форма ёпилди');
    });

    testWidgets('хато (поғона нархи асосийга тенг) — сақлаш ТЎХТАЙДИ, хабар чиқади, карточка очиқ ва хато кўринади', (t) async {
      final repo = _Repo();
      await openForm(t, repo);
      await t.enterText(field('restaurants_m_item_name'), 'Plov');
      await t.enterText(field('restaurants_m_item_price'), '35000');
      await openTiers(t);
      await t.ensureVisible(find.byKey(const ValueKey('qty-tiers-add')));
      await t.tap(find.byKey(const ValueKey('qty-tiers-add')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('qty-tier-min-0')), '10');
      await t.enterText(find.byKey(const ValueKey('qty-tier-price-0')), '35000');
      await t.pumpAndSettle();
      await tapSave(t);
      expect(repo.saved, isEmpty, reason: 'хатоли чегирма билан таом сақланмайди');
      expect(find.text(_tr('restaurants_m_tiers_err_fix')), findsOneWidget);
      expect(find.byKey(const ValueKey('qty-tiers-error')), findsOneWidget);
    });

    testWidgets('ярим тўлдирилган қатор ҳам сақлашни тўхтатади', (t) async {
      final repo = _Repo();
      await openForm(t, repo);
      await t.enterText(field('restaurants_m_item_name'), 'Plov');
      await t.enterText(field('restaurants_m_item_price'), '35000');
      await openTiers(t);
      await t.ensureVisible(find.byKey(const ValueKey('qty-tiers-add')));
      await t.tap(find.byKey(const ValueKey('qty-tiers-add')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('qty-tier-min-0')), '10');
      await t.pumpAndSettle();
      await tapSave(t);
      expect(repo.saved, isEmpty);
    });

    testWidgets('таҳрир: мавжуд поғоналар индамай ЎЧМАЙДИ (ўзгартирмасдан сақлаш — ўшалар); барчасини ўчириш — бўш рўйхат', (t) async {
      final existing = MenuItem(id: 'osh', name: 'Osh', price: 35000, qtyTiers: [_t(10, 32000), _t(30, 30000)]);
      final repo = _Repo();
      await openForm(t, repo, existing: existing);
      await tapSave(t);
      expect(repo.saved.single.tiers, [_t(10, 32000), _t(30, 30000)]);
      expect(repo.saved.single.id, 'osh');

      final repo2 = _Repo();
      await openForm(t, repo2, existing: existing);
      await t.ensureVisible(find.byKey(const ValueKey('qty-tier-remove-1')));
      await t.tap(find.byKey(const ValueKey('qty-tier-remove-1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('qty-tier-remove-0')));
      await t.pumpAndSettle();
      await tapSave(t);
      expect(repo2.saved.single.tiers, isEmpty);
    });

    testWidgets('таҳрирда асосий нарх поғона нархидан паст қилинса — сақлаш тўхтайди (бузилган ҳужжат ҳосил бўлмайди)', (t) async {
      final existing = MenuItem(id: 'osh', name: 'Osh', price: 35000, qtyTiers: [_t(10, 32000)]);
      final repo = _Repo();
      await openForm(t, repo, existing: existing);
      await t.enterText(field('restaurants_m_item_price'), '30000');
      await t.pumpAndSettle();
      await tapSave(t);
      expect(repo.saved, isEmpty);
      expect(find.text(_tr('restaurants_m_tiers_err_fix')), findsOneWidget);
    });

    testWidgets('тор экран 320: форма чегирма карточкаси билан синмайди', (t) async {
      await openForm(t, _Repo(), existing: MenuItem(id: 'o', name: 'Osh', price: 35000, qtyTiers: [_t(10, 32000), _t(30, 30000)]), width: 320);
      expect(t.takeException(), isNull);
    });
  });
}
