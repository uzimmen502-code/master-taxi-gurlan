import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/admin_web/screens/supermarket_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_supermarket_service.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_offer.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../supermarket/sm_fixture.dart';

Map<String, String> _n3(String s) => {'uz_Cyrl': s, 'uz_Latn': '$s-lat', 'ru': '$s-ru'};

Map<String, dynamic> _txRaw() => {
      'version': 3,
      'categories': [
        {
          'id': 'vegetables',
          'order': 1,
          'icon': 'vegetables',
          'names': _n3('Сабзавотлар'),
          'groups': [
            {'id': 'onion', 'order': 1, 'names': _n3('Пиёз'), 'unit': 'kg', 'step': 0.5, 'weighed': true, 'synonyms': []},
          ],
        },
      ],
    };

class _FakeAdmin extends AdminSupermarketService {
  final saved = <({String id, SmOfferDraft draft, int? purchase, String? supplier})>[];
  ({SmSettings s, int v, String reason})? savedSettings;
  ({List<dynamic> cats, int v})? savedTx;
  final settled = <(String, List<({String productId, num actualQty})>)>[];
  final removed = <(String, String, String)>[];

  @override
  Future<Map<String, dynamic>?> loadTaxonomyRaw() async => _txRaw();
  @override
  Future<void> saveTaxonomy(List<dynamic> categories, int expectedVersion) async =>
      savedTx = (cats: categories, v: expectedVersion);
  @override
  Future<List<SmOffer>> loadOffers(SmTaxonomy tx) async => [offer('o1', price: 5000)];
  @override
  String newProductId() => 'newProd123';
  @override
  Future<Map<String, dynamic>?> loadCost(String productId) async => {'purchasePrice': 4000, 'supplier': 'Деҳқон'};
  @override
  Future<void> saveOffer({
    required String productId,
    required SmOfferDraft draft,
    int? purchasePrice,
    String? supplier,
  }) async =>
      saved.add((id: productId, draft: draft, purchase: purchasePrice, supplier: supplier));
  @override
  Future<SmSettings> loadSettings() async => const SmSettings(
        stage: 'internal',
        testerIds: ['998901234567'],
        districtIds: ['gurlan'],
        slots: [SmSlotDraft(id: 's1000_1200', startMin: 600, endMin: 720)],
        cutoffMin: 60,
        weighHoldPercent: 10,
        version: 4,
      );
  @override
  Future<void> saveSettings(SmSettings s, {required int expectedVersion, required String reason}) async =>
      savedSettings = (s: s, v: expectedVersion, reason: reason);
  @override
  Future<void> settleWeights(String orderId, List<({String productId, num actualQty})> lines) async =>
      settled.add((orderId, lines));
  @override
  Future<void> removeLine(String orderId, String productId, String reason) async =>
      removed.add((orderId, productId, reason));
}

Finder _k(String k) => find.byKey(ValueKey(k));

Future<void> _big(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(1200, 2600));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

SmOfferDraft _d({
  int price = 5000,
  num step = 0.5,
  String group = 'onion',
  num? stock = 10,
  String unit = 'kg',
  String variety = 'red',
  Map<String, String>? vNames,
  Map<String, String> quality = const {},
}) =>
    SmOfferDraft(
      groupId: group,
      varietyId: variety,
      varietyNames: vNames ?? _n3('Қизил'),
      qualityNames: quality,
      packLabel: '',
      unit: unit,
      qtyStep: step,
      weighed: true,
      stock: stock,
      status: 'active',
      price: price,
    );

void main() {
  group('соф функциялар', () {
    test('вақт қаторлари: тартиб, такрор йўқ, хато қаторлар; сервер учун 3 тилда ном', () {
      final r = parseSlotLines('15:00-17:00\n10:00 - 12:00\n\n10:00-12:00\n12:00-11:00\nабв\n9:60-10:00');
      expect(r.slots.map((s) => s.id), ['s1000_1200', 's1500_1700']);
      expect(r.slots.first.startMin, 600);
      expect(r.errors, ['12:00-11:00', 'абв', '9:60-10:00']);
      expect(slotLines(r.slots), '10:00-12:00\n15:00-17:00');
      expect(r.slots.first.toMap(), {
        'id': 's1000_1200',
        'names': {'uz_Cyrl': '10:00–12:00', 'uz_Latn': '10:00–12:00', 'ru': '10:00–12:00'},
        'startMin': 600,
        'endMin': 720,
      });
    });

    test('settings: фақат сервер калитлари; версия; текширув (0..720, 0..50, туман ID)', () {
      final s = SmSettings.fromMap({
        'stage': 'pilot',
        'testerIds': ['998901234567'],
        'districtIds': ['gurlan'],
        'slots': [
          {'id': 's1', 'startMin': 600, 'endMin': 720, 'names': _n3('Эрталаб')},
          {'bad': 1},
        ],
        'cutoffMin': 60,
        'weighHoldPercent': 10,
        'version': 7,
        'updatedAt': 'x',
      });
      expect(s.version, 7);
      expect(s.toMap().keys.toSet(), {'stage', 'testerIds', 'districtIds', 'slots', 'cutoffMin', 'weighHoldPercent'});
      expect((s.toMap()['slots'] as List).single['names'], _n3('Эрталаб'));
      expect(s.problems(), isEmpty);
      expect(const SmSettings(cutoffMin: 721).problems(), isNotEmpty);
      expect(const SmSettings(cutoffMin: 720).problems(), isEmpty, reason: 'чегара');
      expect(const SmSettings(weighHoldPercent: 51).problems(), isNotEmpty);
      expect(const SmSettings(districtIds: ['Gurlan!']).problems(), isNotEmpty);
      expect(SmSettings.fromMap({'stage': 'x'}).stage, 'off');
      expect(SmSettings.fromMap(null).version, 0);
    });

    test('таклиф: текширув сервер кўзгуси (мусбат/манфий/чегара)', () {
      final tx = SmTaxonomy.fromMap(_txRaw());
      expect(_d().validate(tx), isEmpty);
      expect(_d(price: 1).validate(tx), isEmpty, reason: 'чегара: 1 сўм');
      expect(_d(stock: 0).validate(tx), isEmpty, reason: 'чегара: қолдиқ 0');
      expect(_d(price: 0).validate(tx), contains('Нарх бутун сон, 0 дан катта'));
      expect(_d(step: 0).validate(tx), isNotEmpty);
      expect(_d(group: 'nope').validate(tx), contains('Гуруҳ таксономияда йўқ'));
      expect(_d(stock: -1).validate(tx), isNotEmpty);
      expect(_d(stock: null).validate(tx), contains('Қолдиқни киритинг (0 — тугаган)'));
      expect(_d(unit: 'ton').validate(tx), contains('Бирлик нотўғри'));
      expect(_d(variety: 'Red').validate(tx), isNotEmpty, reason: 'ID_RE');
      expect(_d(vNames: const {'uz_Cyrl': 'Қизил'}).validate(tx), contains('Нав номи 3 тилда бўлиши шарт'));
      expect(_d(quality: const {'uz_Cyrl': '1-сорт'}).validate(tx), contains('Сифат — ё 3 тилда, ё бўш'));
    });

    test('таклиф payload — сервер OFFER_KEYS; харид нархи offer ичида эмас', () {
      final o = _d(price: 5500).toOffer();
      expect(o.keys.toSet(), {'smGroupId', 'smVariety', 'packLabel', 'unit', 'qtyStep', 'weighed', 'stock', 'smStatus', 'price'});
      expect(o['smVariety'], {'id': 'red', 'names': _n3('Қизил')});
      expect(_d(quality: _n3('1-сорт')).toOffer()['smQuality'], _n3('1-сорт'));
    });

    test('сервер хатоси → Кирилл матн', () {
      expect(
        smAdminErrorText('x', 'invalid-argument', {
          'code': 'OFFER_INVALID',
          'messages': {'uz_Cyrl': 'Таклиф маълумоти нотўғри.'},
          'errors': ['PRICE_INVALID offer.price'],
        }),
        'Таклиф маълумоти нотўғри. (OFFER_INVALID): PRICE_INVALID offer.price',
      );
      expect(smAdminErrorText('fn', 'internal', null), 'Сервер рад этди (fn): internal');
    });

    test('таксономия JSON текшируви (сервер кўзгуси)', () {
      expect(smTaxonomyJsonProblem(jsonEncode({'categories': _txRaw()['categories']})), isNull);
      expect(smTaxonomyJsonProblem(jsonEncode(_txRaw())), contains('фақат `categories`'), reason: 'version калити');
      expect(smTaxonomyJsonProblem('{'), 'JSON нотўғри');
      expect(smTaxonomyJsonProblem('[]'), isNotNull);
      expect(smTaxonomyJsonProblem('{"categories":[]}'), isNotNull);
      Map<String, dynamic> base() => jsonDecode(jsonEncode({'categories': _txRaw()['categories']})) as Map<String, dynamic>;
      final badUnit = base();
      ((badUnit['categories'] as List).first['groups'] as List).first['unit'] = 'ton';
      expect(smTaxonomyJsonProblem(jsonEncode(badUnit)), contains('бирлик'));
      final dup = base();
      final groups = (dup['categories'] as List).first['groups'] as List;
      groups.add(jsonDecode(jsonEncode(groups.first)));
      expect(smTaxonomyJsonProblem(jsonEncode(dup)), contains('такрорланган'));
      final oneLang = base();
      (oneLang['categories'] as List).first['names'] = {'uz_Cyrl': 'X'};
      expect(smTaxonomyJsonProblem(jsonEncode(oneLang)), contains('3 тилда'));
      final noSyn = base();
      ((noSyn['categories'] as List).first['groups'] as List).first.remove('synonyms');
      expect(smTaxonomyJsonProblem(jsonEncode(noSyn)), contains('synonyms'));
    });

    test('ҳақиқий миқдор ва буюртма қаторлари (сервер шакли)', () {
      expect(smParseActualQty({'a': '1,25', 'b': '2'})!.map((e) => e.actualQty), [1.25, 2]);
      expect(smParseActualQty({'a': '0'}), isNull);
      expect(smParseActualQty({'a': 'x'}), isNull);
      final lines = smOrderLines({
        'items': [
          {'productId': 'a', 'name': 'Пиёз', 'qty': 1.5, 'unit': 'кг', 'smUnit': 'kg', 'weighed': true},
          {'productId': 'b', 'name': 'Сут', 'qty': 2, 'unit': 'пачка', 'smUnit': 'pack'},
          {'productId': 'c', 'name': 'Олма', 'qty': 1, 'smUnit': 'kg', 'weighed': true, 'actualQty': 0.95},
          {'productId': 'd', 'name': 'Нок', 'qty': 1, 'smUnit': 'kg', 'weighed': true, 'removed': {'reason': 'йўқ'}},
        ],
      });
      expect(lines.map((l) => '${l.productId}:${l.unit}:${l.weighed}:${l.removed}'),
          ['a:kg:true:false', 'b:pack:false:false', 'c:kg:true:false', 'd:kg:true:true']);
      expect(smLinesToWeigh(lines).map((l) => l.productId), ['a'], reason: 'тортилган ва олинган қаторлар йўқ');
      expect(smOrderLines({}), isEmpty);
    });

    test('нарх ўзгариши матни', () {
      final o = SmOffer(id: 'x', name: 'x', groupId: 'g', price: 1, priceUpdatedAt: DateTime(2026, 11, 20, 9, 5), priceUpdatedBy: 'abcdefghijk');
      expect(smPriceChangeText(o), 'нарх ўзгарди: 20.11.2026 09:05, abcdefgh…');
      expect(smPriceChangeText(const SmOffer(id: 'x', name: 'x', groupId: 'g', price: 1)), '');
    });
  });

  group('формалар', () {
    testWidgets('таклиф таҳрири: нарх + харид нархи серверга; хато — Кирилл матн', (t) async {
      await _big(t);
      final s = _FakeAdmin();
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmOffersAdminTab(service: s))));
      await t.pumpAndSettle();
      await t.tap(_k('sm_admin_offer_o1'));
      await t.pumpAndSettle();
      expect(find.text('4000'), findsOneWidget, reason: 'private/cost юкланди');
      await t.enterText(_k('sm_admin_price'), '0');
      await t.tap(_k('sm_admin_save_offer'));
      await t.pumpAndSettle();
      expect(find.text('Нарх бутун сон, 0 дан катта'), findsOneWidget);
      expect(s.saved, isEmpty);
      await t.enterText(_k('sm_admin_price'), '5500');
      await t.enterText(_k('sm_admin_purchase'), '4200');
      await t.tap(_k('sm_admin_save_offer'));
      await t.pumpAndSettle();
      expect(s.saved.single.id, 'o1');
      expect(s.saved.single.draft.price, 5500);
      expect(s.saved.single.purchase, 4200);
      expect(s.saved.single.supplier, 'Деҳқон');
    });

    testWidgets('янги таклиф: ID клиентда, 3 тилли нав шарт', (t) async {
      await _big(t);
      final s = _FakeAdmin();
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmOffersAdminTab(service: s))));
      await t.pumpAndSettle();
      await t.tap(_k('sm_admin_new_offer'));
      await t.pumpAndSettle();
      expect(find.text('Янги таклиф'), findsWidgets);
      await t.tap(_k('sm_admin_group'));
      await t.pumpAndSettle();
      await t.tap(find.text('Пиёз').last);
      await t.pumpAndSettle();
      await t.enterText(_k('sm_admin_variety_id'), 'red');
      await t.enterText(_k('sm_admin_variety_cyr'), 'Қизил');
      await t.enterText(_k('sm_admin_price'), '6000');
      await t.enterText(_k('sm_admin_stock'), '50');
      await t.tap(_k('sm_admin_save_offer'));
      await t.pumpAndSettle();
      expect(find.text('Нав номи 3 тилда бўлиши шарт'), findsOneWidget);
      await t.enterText(_k('sm_admin_variety_lat'), 'Qizil');
      await t.enterText(_k('sm_admin_variety_ru'), 'Красный');
      await t.tap(_k('sm_admin_save_offer'));
      await t.pumpAndSettle();
      expect(s.saved.single.id, 'newProd123');
      expect(s.saved.single.draft.toOffer()['stock'], 50);
      expect(s.saved.single.draft.unit, 'kg', reason: 'гуруҳдан');
      expect(s.saved.single.purchase, isNull);
    });

    testWidgets('созламалар: версия ва сабаб билан; нотўғри — сақланмайди', (t) async {
      await _big(t);
      final s = _FakeAdmin();
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmSettingsAdminTab(service: s))));
      await t.pumpAndSettle();
      expect(find.text('10:00-12:00'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      await t.enterText(_k('sm_admin_slots'), '10:00-12:00\n18-20');
      await t.tap(_k('sm_admin_settings_save'));
      await t.pumpAndSettle();
      expect(s.savedSettings, isNull);
      expect(find.textContaining('Нотўғри вақт'), findsOneWidget);
      expect(find.textContaining('Сабаб ёзинг'), findsOneWidget);
      await t.enterText(_k('sm_admin_slots'), '10:00-12:00\n15:00-17:00');
      await t.enterText(_k('sm_admin_cutoff'), '721');
      await t.enterText(_k('sm_admin_reason'), 'Гурлан пилот');
      await t.tap(_k('sm_admin_settings_save'));
      await t.pumpAndSettle();
      expect(s.savedSettings, isNull, reason: 'cutoff > 720');
      await t.enterText(_k('sm_admin_cutoff'), '90');
      await t.tap(_k('sm_admin_stage_public'));
      await t.tap(_k('sm_admin_settings_save'));
      await t.pumpAndSettle();
      final saved = s.savedSettings!;
      expect(saved.v, 4);
      expect(saved.reason, 'Гурлан пилот');
      expect(saved.s.stage, 'public');
      expect(saved.s.slots.map((x) => x.id), ['s1000_1200', 's1500_1700']);
      expect(saved.s.districtIds, ['gurlan']);
      expect(saved.s.cutoffMin, 90);
      expect(saved.s.weighHoldPercent, 10);
    });

    testWidgets('таксономия: хулоса; фақат categories + expectedVersion; нотўғри JSON сақланмайди', (t) async {
      await _big(t);
      final s = _FakeAdmin();
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmTaxonomyAdminTab(service: s))));
      await t.pumpAndSettle();
      expect(find.text('Версия 3 · 1 категория · 1 гуруҳ'), findsOneWidget);
      await t.tap(_k('sm_admin_tx_save'));
      await t.pumpAndSettle();
      expect(s.savedTx!.v, 3);
      expect(s.savedTx!.cats.length, 1);
      s.savedTx = null;
      await t.enterText(_k('sm_admin_tx_json'), '{oops');
      await t.tap(_k('sm_admin_tx_save'));
      await t.pumpAndSettle();
      expect(find.text('JSON нотўғри'), findsOneWidget);
      expect(s.savedTx, isNull);
    });

    testWidgets('буюртмалар: тортиш (фақат тортилмаган) ва қаторни олиш; ҳолат ёпиқ — тугма йўқ', (t) async {
      await _big(t);
      final s = _FakeAdmin();
      Map<String, dynamic> order(String id, String status) => {
            'id': id,
            'type': 'platform',
            'subtype': 'supermarket',
            'status': status,
            'itemsTotal': 10000,
            'total': 12100,
            'items': [
              {'productId': 'a', 'name': 'Пиёз', 'qty': 2, 'smUnit': 'kg', 'weighed': true},
              {'productId': 'b', 'name': 'Сут', 'qty': 1, 'smUnit': 'pack'},
            ],
          };
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SmOrdersAdminTab(service: s, orders: Stream.value([order('ord1', 'accepted'), order('ord2', 'delivered')])),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.textContaining('Маҳсулот: '), findsWidgets);
      expect(_k('sm_admin_settle_ord2'), findsNothing);
      expect(_k('sm_admin_remove_ord2_b'), findsNothing);
      await t.tap(_k('sm_admin_settle_ord1'));
      await t.pumpAndSettle();
      await t.enterText(_k('sm_admin_actual_a'), '1,85');
      await t.tap(_k('sm_admin_settle_confirm'));
      await t.pumpAndSettle();
      expect(s.settled.single.$1, 'ord1');
      expect(s.settled.single.$2.single.actualQty, 1.85);
      await t.tap(_k('sm_admin_remove_ord1_b'));
      await t.pumpAndSettle();
      await t.enterText(_k('sm_admin_remove_reason'), 'тугаб қолди');
      await t.tap(_k('sm_admin_remove_confirm'));
      await t.pumpAndSettle();
      expect(s.removed.single, ('ord1', 'b', 'тугаб қолди'));
    });
  });

  test('админ панелда «AVA Супермаркет» бўлими (users рухсати)', () {
    final src = File('lib/features/admin_web/screens/admin_shell.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(src.contains("label: 'AVA Супермаркет'"), isTrue);
    expect(src.contains("if (section.label == 'AVA Супермаркет') {\n      return const SupermarketAdminScreen();"), isTrue);
  });
}
