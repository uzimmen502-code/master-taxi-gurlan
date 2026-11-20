// «AVA Супермаркет» скриншотлари (эга 2026-11-20) — ҲАҚИҚИЙ виджетлар, сохта маълумот, ёруғ тема.
// Фақат `AVA_SCREENS=1` билан (оддий прогонда ўтказиб юборилади); ҳар тестни алоҳида ишга туширинг:
//   $env:AVA_SCREENS='1'; flutter test test/features/supermarket/sm_screens_shots_test.dart --plain-name "sm_home"
// Натижа: build/screens/sm_*.png (375×812 dp, pixelRatio 2; админ — 1280×800).
// Расмлар: таклиф расмлари тармоқдан — бу ерда ўрин (иконка) кўринади.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/admin_web/screens/supermarket_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_supermarket_service.dart';
import 'package:ava_gurlan/features/home/widgets/home_markets_block.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_access.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_cart.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_offer.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_cart_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_category_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_checkout_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_group_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/supermarket_home_screen.dart';
import 'package:ava_gurlan/features/supermarket/supermarket_controller.dart';
import 'package:ava_gurlan/features/supermarket/widgets/sm_order_cancel_bar.dart';
import 'package:ava_gurlan/features/supermarket/widgets/sm_order_progress_view.dart';
import 'package:ava_gurlan/l10n/app_localizations.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sm_fixture.dart' show FakeSupermarketApi;

final _enabled = Platform.environment['AVA_SCREENS'] == '1';

Map<String, String> _n(String c, String l, String r) => {'uz_Cyrl': c, 'uz_Latn': l, 'ru': r};

final _tx = SmTaxonomy.fromMap({
  'version': 1,
  'categories': [
    for (final (i, id, icon, c, groups) in [
      (1, 'vegetables', 'vegetable', 'Сабзавотлар', [('onion', 'Пиёз', 'kg', 0.5, true), ('potato', 'Картошка', 'kg', 1, true), ('carrot', 'Сабзи', 'kg', 0.5, true), ('tomato', 'Помидор', 'kg', 0.5, true)]),
      (2, 'fruits', 'fruit', 'Мевалар', [('apple', 'Олма', 'kg', 0.5, true), ('banana', 'Банан', 'kg', 0.5, true)]),
      (3, 'meat', 'meat', 'Гўшт ва парранда', [('beef', 'Мол гўшти', 'kg', 0.5, true)]),
      (4, 'dairy', 'dairy', 'Сут маҳсулотлари', [('milk', 'Сут', 'pack', 1, false), ('kefir', 'Кефир', 'pack', 1, false)]),
      (5, 'eggs', 'egg', 'Тухум', [('egg', 'Тухум', 'pack', 1, false)]),
      (6, 'grain', 'grain', 'Ун, гуруч, дон', [('rice', 'Гуруч', 'kg', 1, false)]),
      (7, 'oil', 'oil', 'Ёғ', [('oil', 'Пахта ёғи', 'l', 1, false)]),
      (8, 'drinks', 'drink', 'Ичимликлар', [('water', 'Сув', 'pack', 1, false)]),
      (9, 'household', 'household', 'Рўзғор буюмлари', [('soap', 'Совун', 'piece', 1, false)]),
    ])
      {
        'id': id,
        'order': i,
        'icon': icon,
        'names': _n(c, c, c),
        'groups': [
          for (final (j, (gid, name, unit, step, weighed)) in groups.indexed)
            {'id': gid, 'order': j, 'names': _n(name, name, name), 'unit': unit, 'step': step, 'weighed': weighed, 'synonyms': <String>[]},
        ],
      },
  ],
});

SmOffer _o(String id, String group, String name, int price,
        {String variety = 'v', String vName = '', String quality = '', String pack = '', String unit = 'kg',
        num step = 0.5, bool weighed = true, String status = 'active', num stock = 50, num? packQty, String packUnit = ''}) =>
    SmOffer.fromMap(id, {
      'name': name,
      'smGroupId': group,
      'smVariety': {'id': variety, 'names': vName.isEmpty ? <String, String>{} : _n(vName, vName, vName)},
      if (quality.isNotEmpty) 'smQuality': _n(quality, quality, quality),
      'packLabel': pack,
      'unit': unit,
      'qtyStep': step,
      'weighed': weighed,
      'smStatus': status,
      'stock': stock,
      'price': price,
      if (packQty != null) 'packQty': packQty,
      if (packUnit.isNotEmpty) 'packUnit': packUnit,
    });

final _offers = <SmOffer>[
  _o('on1', 'onion', 'Қизил пиёз, Гурлан', 5000, variety: 'red', vName: 'Қизил пиёз', quality: '1-сорт'),
  _o('on2', 'onion', 'Қизил пиёз, тўрда 2 кг', 9000,
      variety: 'red', vName: 'Қизил пиёз', pack: 'тўр 2 кг', unit: 'pack', step: 1, weighed: false, packQty: 2, packUnit: 'kg'),
  _o('on3', 'onion', 'Қизил пиёз, сараланган', 7000, variety: 'red', vName: 'Қизил пиёз', quality: 'Олий'),
  _o('on4', 'onion', 'Қизил пиёз, янги ҳосил', 4000, variety: 'red', vName: 'Қизил пиёз', status: 'out_of_stock'),
  _o('on5', 'onion', 'Оқ пиёз', 6000, variety: 'white', vName: 'Оқ пиёз'),
  _o('on6', 'onion', 'Сариқ пиёз', 5500, variety: 'yellow', vName: 'Сариқ пиёз'),
  _o('po1', 'potato', 'Картошка, маҳаллий', 6000, variety: 'local', vName: 'Маҳаллий', step: 1),
  _o('ca1', 'carrot', 'Сабзи, сариқ', 4500, variety: 'yellow', vName: 'Сариқ сабзи'),
  _o('to1', 'tomato', 'Помидор, иссиқхона', 14000, variety: 'green', vName: 'Иссиқхона'),
  _o('ap1', 'apple', 'Олма, Семеренко', 12000, variety: 'sem', vName: 'Семеренко'),
  _o('ba1', 'banana', 'Банан', 22000),
  _o('be1', 'beef', 'Мол гўшти, лаҳм', 98000, variety: 'lean', vName: 'Лаҳм'),
  _o('mi1', 'milk', 'Сут 3,2%, 0,9 л', 12000,
      unit: 'pack', step: 1, weighed: false, pack: '0,9 л', packQty: 0.9, packUnit: 'l'),
  _o('ke1', 'kefir', 'Кефир 2,5%, 1 л', 13000, unit: 'pack', step: 1, weighed: false, packQty: 1, packUnit: 'l'),
  _o('eg1', 'egg', 'Тухум, 10 дона', 18000, unit: 'pack', step: 1, weighed: false, packQty: 10, packUnit: 'piece'),
  _o('ri1', 'rice', 'Гуруч, Лазер', 24000, step: 1, weighed: false),
  _o('oi1', 'oil', 'Пахта ёғи', 26000, unit: 'l', step: 1, weighed: false),
  _o('wa1', 'water', 'Сув, 1,5 л', 4000, unit: 'pack', step: 1, weighed: false, packQty: 1.5, packUnit: 'l'),
  _o('so1', 'soap', 'Хўжалик совуни', 6000, unit: 'piece', step: 1, weighed: false),
];

const _access = SmAccess(
  allowed: true,
  feePercent: 11,
  weighHoldPercent: 10,
  slots: [
    SmSlot(id: 's10', names: {}, startMin: 600, endMin: 720, day: 'today'),
    SmSlot(id: 's15', names: {}, startMin: 900, endMin: 1020, day: 'today'),
    SmSlot(id: 's18', names: {}, startMin: 1080, endMin: 1200, day: 'today'),
    SmSlot(id: 't10', names: {}, startMin: 600, endMin: 720, day: 'tomorrow'),
  ],
);

final _cart = SmCart.empty.add('on1', 2000).add('mi1', 2000).add('eg1', 1000).add('po1', 3000);

SupermarketController _controller() {
  final c = SupermarketController(api: FakeSupermarketApi(access: _access));
  c.setCatalogForTest(_tx, _offers, access: _access, cart: _cart);
  c.deliveryArea = const GeoArea(regionId: 'xorazm', districtId: 'gurlan', regionLabel: 'Хоразм', districtLabel: 'Гурлан');
  return c;
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(Future.value(ByteData.view(File('assets/fonts/Inter-$w.ttf').readAsBytesSync().buffer)));
  }
  await inter.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:\develop\flutter';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await l.load();
  }
}

class _Host extends StatelessWidget {
  const _Host({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// [stops]: 'top' | 'bottom' | число (dp сурилиш). [before] — скриншотдан олдин амал (тап ва ҳ.к.).
Future<void> _shoot(
  WidgetTester t,
  String name,
  Widget screen, {
  Size size = const Size(375, 812),
  List<Object> stops = const ['top'],
  Future<void> Function(WidgetTester t)? before,
  List<String> images = const [],
}) async {
  final key = GlobalKey();
  await t.binding.setSurfaceSize(size);
  await t.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'),
      supportedLocales: const [
        Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'),
        Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn'),
        Locale('ru'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 24)),
        child: child!,
      ),
      home: _Host(child: screen),
    ),
  ));
  for (var i = 0; i < 20 && find.byType(_Host).evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
  await t.runAsync(() async {
    final ctx = t.element(find.byType(_Host));
    for (final p in images) {
      await precacheImage(AssetImage(p), ctx);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await t.pump(const Duration(milliseconds: 500));
  if (before != null) await before(t);
  await t.pump(const Duration(milliseconds: 500));
  // Расмлар (cacheWidth билан) асинхрон декод бўлади — тайёр бўлишини кутиш.
  for (var i = 0; i < 3; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 100));
  }
  Directory('build/screens').createSync(recursive: true);
  for (final stop in stops) {
    final scrollables = find.byType(Scrollable);
    if (stop != 'top' && scrollables.evaluate().isNotEmpty) {
      // Энг катта (асосий) рўйхат — биринчи вертикал Scrollable.
      final st = t.stateList<ScrollableState>(scrollables).firstWhere(
            (s) => s.position.axis == Axis.vertical,
            orElse: () => t.state<ScrollableState>(scrollables.first),
          );
      final pos = st.position;
      final target = stop == 'bottom' ? pos.maxScrollExtent : (stop as num).toDouble();
      pos.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
      await t.pump(const Duration(milliseconds: 300));
    }
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final suffix = stops.length == 1 ? '' : '_$stop';
    await t.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/screens/$name$suffix.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  expect(t.takeException(), isNull);
  await t.pumpWidget(const SizedBox());
  await t.binding.setSurfaceSize(null);
}

class _FakeAdmin extends AdminSupermarketService {
  @override
  Future<Map<String, dynamic>?> loadTaxonomyRaw() async => {
        'version': 1,
        'categories': [
          {
            'id': 'vegetables',
            'order': 1,
            'icon': 'vegetable',
            'names': _n('Сабзавотлар', 'Sabzavotlar', 'Овощи'),
            'groups': [
              {'id': 'onion', 'order': 1, 'names': _n('Пиёз', 'Piyoz', 'Лук'), 'unit': 'kg', 'step': 0.5, 'weighed': true, 'synonyms': []},
            ],
          },
          {
            'id': 'dairy',
            'order': 2,
            'icon': 'dairy',
            'names': _n('Сут маҳсулотлари', 'Sut mahsulotlari', 'Молочные'),
            'groups': [
              {'id': 'milk', 'order': 1, 'names': _n('Сут', 'Sut', 'Молоко'), 'unit': 'pack', 'step': 1, 'weighed': false, 'synonyms': []},
            ],
          },
        ],
      };
  @override
  Future<List<SmOffer>> loadOffers(SmTaxonomy tx) async => [
        for (final o in _offers.where((o) => o.groupId == 'onion' || o.groupId == 'milk'))
          SmOffer(
            id: o.id, name: o.name, groupId: o.groupId, price: o.price, varietyNames: o.varietyNames, unit: o.unit,
            status: o.status, priceUpdatedAt: DateTime(2026, 11, 20, 9, 30), priceUpdatedBy: 'admin998901234567',
          ),
      ];
  @override
  Future<Map<String, dynamic>?> loadCost(String productId) async => {'purchasePrice': 3800, 'supplier': 'Гурлан деҳқон хўжалиги'};
}

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    SharedPreferences.setMockInitialValues({'user_phone': '+998901234567'});
    await _loadFonts();
  });

  testWidgets('sm_home_markets', (t) async {
    await _shoot(
      t,
      'sm_home_markets',
      Scaffold(
        backgroundColor: AvaLight.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: HomeMarketsBlock(
              onOpen: (_) {},
              isVisible: (_) => true,
              loadSupermarketAccess: () async => true,
              loadTaxonomy: () async => MarketTaxonomy.fromMap(const {'version': 1, 'markets': {}}),
            ),
          ),
        ),
      ),
      images: [for (final e in kHomeMarketEntries) if (e.imagePath != null) e.imagePath!],
    );
  }, skip: !_enabled);

  testWidgets('sm_home', (t) async {
    await _shoot(t, 'sm_home', SupermarketHomeScreen(controller: _controller()), stops: const ['top', 'bottom']);
  }, skip: !_enabled);

  testWidgets('sm_category', (t) async {
    await _shoot(t, 'sm_category', SmCategoryScreen(controller: _controller(), category: _tx.category('vegetables')!));
  }, skip: !_enabled);

  testWidgets('sm_group', (t) async {
    await _shoot(t, 'sm_group', SmGroupScreen(controller: _controller(), group: _tx.group('onion')!),
        stops: const ['top', 600, 'bottom']);
  }, skip: !_enabled);

  testWidgets('sm_group_milk', (t) async {
    await _shoot(t, 'sm_group_milk', SmGroupScreen(controller: _controller(), group: _tx.group('milk')!));
  }, skip: !_enabled);

  testWidgets('sm_cart', (t) async {
    await _shoot(t, 'sm_cart', SmCartScreen(controller: _controller()), stops: const ['top', 'bottom']);
  }, skip: !_enabled);

  Future<void> fill(WidgetTester t) async {
    await t.enterText(find.byKey(const ValueKey('sm_addr_mahalla')), 'Наврўз МФЙ');
    await t.enterText(find.byKey(const ValueKey('sm_addr_street')), 'Мустақиллик кўчаси');
    await t.enterText(find.byKey(const ValueKey('sm_addr_house')), '12');
    await t.ensureVisible(find.byKey(const ValueKey('sm_slot_s15')));
    await t.tap(find.byKey(const ValueKey('sm_slot_s15')));
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('sm_checkout_ok', (t) async {
    await _shoot(t, 'sm_checkout_ok', SmCheckoutScreen(controller: _controller(), balance: Stream.value(250000)),
        before: fill, stops: const ['top', 'bottom']);
  }, skip: !_enabled);

  testWidgets('sm_checkout_short', (t) async {
    await _shoot(t, 'sm_checkout_short', SmCheckoutScreen(controller: _controller(), balance: Stream.value(30000)),
        before: fill, stops: const ['bottom']);
  }, skip: !_enabled);

  testWidgets('sm_order_status', (t) async {
    OrderModel o(String s) => OrderModel(id: 'ord1', type: 'platform', subtype: 'supermarket', total: 98000, status: s, items: const []);
    Widget page(String status) => Scaffold(
          appBar: AppBar(title: const Text('AVA Супермаркет')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SmOrderProgressView(status: status),
              const SizedBox(height: 8),
              SmOrderCancelBar(order: o(status), cancel: (_) async {}),
            ],
          ),
        );
    await _shoot(t, 'sm_order_status_new', page('new'));
    await _shoot(t, 'sm_order_status_preparing', page('accepted'));
    await _shoot(t, 'sm_order_status_courier', page('in_delivery'));
  }, skip: !_enabled);

  testWidgets('sm_admin_offers', (t) async {
    await _shoot(t, 'sm_admin_offers', Scaffold(body: SmOffersAdminTab(service: _FakeAdmin())), size: const Size(1280, 800));
  }, skip: !_enabled);

  testWidgets('sm_admin_offer_editor', (t) async {
    await _shoot(t, 'sm_admin_offer_editor', Scaffold(body: SmOffersAdminTab(service: _FakeAdmin())),
        size: const Size(1280, 1000), before: (t) async {
      await t.tap(find.byKey(const ValueKey('sm_admin_offer_mi1')));
      await t.pump(const Duration(milliseconds: 600));
    });
  }, skip: !_enabled);

  testWidgets('sm_admin_settle', (t) async {
    final order = {
      'id': 'K7Qm2x',
      'type': 'platform',
      'subtype': 'supermarket',
      'status': 'accepted',
      'itemsTotal': 52000,
      'weighHold': 2600,
      'deliveryFee': 5720,
      'total': 60320,
      'items': [
        {'productId': 'on1', 'name': 'Қизил пиёз, Гурлан', 'qty': 2, 'smUnit': 'kg', 'weighed': true},
        {'productId': 'po1', 'name': 'Картошка, маҳаллий', 'qty': 3, 'smUnit': 'kg', 'weighed': true},
        {'productId': 'mi1', 'name': 'Сут 3,2%, 0,9 л', 'qty': 2, 'smUnit': 'pack'},
      ],
    };
    await _shoot(t, 'sm_admin_settle',
        Scaffold(body: SmOrdersAdminTab(service: _FakeAdmin(), orders: Stream.value([order]))),
        size: const Size(1280, 800), before: (t) async {
      await t.pump();
      await t.tap(find.byKey(const ValueKey('sm_admin_settle_K7Qm2x')));
      await t.pump(const Duration(milliseconds: 600));
      await t.enterText(find.byKey(const ValueKey('sm_admin_actual_on1')), '1.85');
    });
  }, skip: !_enabled);
}
