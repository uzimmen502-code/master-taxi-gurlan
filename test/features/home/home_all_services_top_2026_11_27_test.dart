// Эга 2026-11-27: «Барча хизматлар ›» қатори қидирув тагида, «Бозорлар»дан олдин (пастдагиси олиб
// ташланди). Босилса — «Барча хизматлар» экрани: ҳар хизмат ЭСКИ расми билан (ServiceCircleTile,
// home_services_catalog), модул дарвозаси бўйича, ихчам гридда.
import 'dart:io';

import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/core/utils/payment_provider_launcher.dart';
import 'package:ava_gurlan/features/home/home_services_catalog.dart';
import 'package:ava_gurlan/features/home/widgets/all_services_screen.dart';
import 'package:ava_gurlan/features/home/widgets/home_lite_cards.dart';
import 'package:ava_gurlan/features/home/widgets/home_services_olx_row.dart';
import 'package:ava_gurlan/features/home/widgets/service_circle_tile.dart';
import 'package:ava_gurlan/features/home/widgets/service_spotlight_item.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HomeServiceActions _noopActions() => HomeServiceActions(
      push: (_) async {},
      openModule: (_) async {},
      openYukModule: (_, __) async {},
      openPayment: (PaymentProviderApp _) async {},
      openDating: () async {},
      showComingSoon: () {},
    );

Future<List<ServiceSpotlightItem>> _catalog(WidgetTester t) async {
  late List<ServiceSpotlightItem> items;
  await t.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      items = buildHomeServices(context, a: _noopActions());
      return const SizedBox.shrink();
    }),
  ));
  return items;
}

/// Эга 2026-11-27 (2-тур): аввал расмсиз бўлган 8 хизмат — энди эга расмлари билан.
const _kOwnerPhotos = <String, String>{
  'jobs_services': 'assets/images/home/card_services_market_v1.webp',
  'tv_market': 'assets/images/services/service_tv_market_v1.webp',
  'dating': 'assets/images/home/card_dating_v1.webp',
  'chatgpt': 'assets/images/services/service_chatgpt_v1.webp',
  'logistics': 'assets/images/home/card_post_v1.webp',
  'realty': 'assets/images/markets/market_realty_v2.webp',
  'wholesale_market': 'assets/images/markets/market_wholesale_v2.webp',
  'china_market': 'assets/images/markets/market_china_v2.webp',
};

void main() {
  tearDown(ServiceConfigHolder.resetForTest);

  test('жойи: қидирув тагида, «Бозорлар»дан олдин; бош саҳифада битта', () {
    final src = File('lib/features/home/home_screen.dart').readAsStringSync();
    final search = RegExp(r'HomeGlobalSearchBar\(\s*key:').firstMatch(src)!.start;
    final header = src.indexOf('HomeAllServicesHeader(');
    final block = src.indexOf('HomeMarketsBlock(onOpen: _openHomeMarket');
    expect(search, greaterThan(0));
    expect(header, greaterThan(search));
    expect(block, greaterThan(header));
    expect(RegExp(r'HomeAllServicesHeader\(').allMatches(src).length, 1);
    // Ораликда бошқа виджет йўқ (фақат оралиқ).
    final between = src.substring(header, block);
    expect(between.contains('HomeMarketSection('), isFalse);
    expect(src.contains('onTap: _openAllServices'), isTrue);
    // Экран — тўлиқ каталог (эски расмлар шу ерда).
    expect(
      RegExp(r'AllServicesScreen\(\s*items: buildHomeServices\(context, a: _serviceActions\)')
          .hasMatch(src),
      isTrue,
    );
  });

  testWidgets('навигация: қатор босилса — «Барча хизматлар» экрани, эски доира плиткалар', (t) async {
    ServiceConfigHolder.setForTest(
      defaults: ServiceModuleConfig({'bread': ModuleStatus.enabled}),
      enforce: true,
    );
    final items = [
      ServiceSpotlightItem(
        moduleId: 'bread',
        label: 'Нон',
        imagePath: 'assets/images/services/service_bread.png',
        onTap: () {},
      ),
    ];
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: HomeAllServicesHeader(
            items: items,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => AllServicesScreen(items: items)),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.byKey(const ValueKey('home_all_services_header')));
    await t.pumpAndSettle();
    expect(find.byType(AllServicesScreen), findsOneWidget);
    expect(find.byType(ServiceCircleTile), findsOneWidget);
    expect(find.text('home_services_all_title'), findsOneWidget); // AppBar
    final img = t.widget<Image>(find.descendant(
      of: find.byType(ServiceCircleTile),
      matching: find.byType(Image),
    ));
    expect((img.image as AssetImage).assetName, 'assets/images/services/service_bread.png');
  });

  testWidgets('дарвоза: яширин модул «Барча хизматлар»да йўқ; ҳаммаси яширин — қатор ҳам йўқ', (t) async {
    ServiceConfigHolder.setForTest(
      defaults: ServiceModuleConfig({
        'bread': ModuleStatus.enabled,
        'milk': ModuleStatus.hidden,
      }),
      enforce: true,
    );
    ServiceSpotlightItem it(String id) => ServiceSpotlightItem(
          moduleId: id,
          label: id,
          imagePath: 'assets/images/services/service_$id.png',
          onTap: () {},
        );
    await t.pumpWidget(MaterialApp(home: AllServicesScreen(items: [it('bread'), it('milk')])));
    expect(find.byType(ServiceCircleTile), findsOneWidget);
    expect(find.text('bread'), findsOneWidget);
    expect(find.text('milk'), findsNothing);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: HomeAllServicesHeader(items: [it('milk')])),
    ));
    expect(find.byKey(const ValueKey('home_all_services_header')), findsNothing);
  });

  testWidgets('ихчам грид: телефонда (375) 3 устун, катак 82 px', (t) async {
    await t.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => t.binding.setSurfaceSize(null));
    ServiceConfigHolder.setForTest(
      defaults: ServiceModuleConfig({'bread': ModuleStatus.enabled}),
      enforce: true,
    );
    final items = List.generate(
      6,
      (i) => ServiceSpotlightItem(moduleId: 'bread', label: 'b$i', icon: Icons.circle, onTap: () {}),
    );
    await t.pumpWidget(MaterialApp(home: AllServicesScreen(items: items)));
    final tiles = find.byType(ServiceCircleTile);
    expect(tiles, findsNWidgets(6));
    final y0 = t.getTopLeft(tiles.at(0)).dy;
    expect(t.getTopLeft(tiles.at(2)).dy, y0);
    expect(t.getTopLeft(tiles.at(3)).dy, greaterThan(y0));
    expect(t.getSize(tiles.at(0)).height, ServiceCircleTile.tileHeight);
  });

  testWidgets('расмлар: каталогдаги ҳар PNG/SVG мавжуд, жадвал билан бир хил; расмсизлар рўйхати', (t) async {
    final items = await _catalog(t);
    expect(items, isNotEmpty);
    final iconOnly = <String>{};
    for (final e in items) {
      final asset = e.imagePath ?? e.svgPath;
      if (asset == null) {
        iconOnly.add(e.moduleId);
        expect(e.icon, isNotNull, reason: '${e.moduleId}: расм ҳам, иконка ҳам йўқ');
        continue;
      }
      expect(asset.startsWith('assets/images/'), isTrue, reason: asset);
      expect(File(asset).existsSync(), isTrue, reason: 'файл йўқ: $asset');
      expect(File(asset).lengthSync(), greaterThan(0), reason: asset);
      // Эски кўриниш: ServiceCircleTile жадвали билан бир хил расм.
      expect(e.imagePath ?? '', serviceImageFor(e.moduleId) ?? '', reason: e.moduleId);
      expect(e.svgPath ?? '', serviceSvgFor(e.moduleId) ?? '', reason: e.moduleId);
    }
    // Расмсиз (фақат иконка) хизмат қолмади.
    expect(iconOnly, isEmpty);
    final byId = {for (final e in items) e.moduleId: e};
    _kOwnerPhotos.forEach((id, path) {
      expect(byId[id]!.imagePath, path, reason: id);
      expect(isServicePhoto(path), isTrue, reason: id);
      expect(File(path).lengthSync(), lessThan(120 * 1024), reason: path);
    });
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dir in ['services', 'home', 'markets']) {
      expect(pubspec.contains('- assets/images/$dir/'), isTrue, reason: dir);
    }
  });

  // Эга расмлари 2026-11-27: Мой алмаштириш (oil_change) ва Менинг яқинларим (circles).
  testWidgets('эга фотолари: oil_change/circles — янги webp, доирани тўлиқ қоплайди; бошқалар — эски', (t) async {
    final items = await _catalog(t);
    final byId = {for (final e in items) e.moduleId: e};
    expect(byId['oil_change']!.imagePath, 'assets/images/services/service_oil_change_v2.webp');
    expect(byId['circles']!.imagePath, 'assets/images/services/service_relatives_v2.webp');
    expect(kHomeRelativesCardImage, 'assets/images/services/service_relatives_v2.webp');
    for (final p in [byId['oil_change']!.imagePath!, kHomeRelativesCardImage]) {
      expect(File(p).existsSync(), isTrue, reason: p);
      expect(File(p).lengthSync(), lessThan(60 * 1024), reason: p);
      expect(isServicePhoto(p), isTrue);
    }
    expect(isServicePhoto(byId['bread']!.imagePath), isFalse);
    expect(isServicePhoto(null), isFalse);

    ServiceConfigHolder.setForTest(
      defaults: ServiceModuleConfig({
        'oil_change': ModuleStatus.enabled,
        'bread': ModuleStatus.enabled,
      }),
      enforce: true,
    );
    await t.pumpWidget(MaterialApp(
      home: AllServicesScreen(items: [byId['oil_change']!, byId['bread']!]),
    ));
    expect(find.byKey(const ValueKey('service_photo_oil_change')), findsOneWidget);
    expect(find.byKey(const ValueKey('service_photo_bread')), findsNothing);
    expect(find.byType(ClipOval), findsOneWidget);
  });

  test('«Яқинларингиз туғилган кунини қўшинг» карточкаси — эга расми, cover', () {
    final src = File('lib/features/home/home_screen.dart').readAsStringSync();
    final i = src.indexOf("id: 'relatives_bday'");
    expect(i, greaterThan(0));
    final card = src.substring(i, src.indexOf('onTap: _openRelativesAdd', i));
    expect(card.contains('imagePath: kHomeRelativesCardImage'), isTrue);
    expect(card.contains('fit: HomeLiteImageFit.cover'), isTrue);
  });
}
