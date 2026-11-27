// Эга 2026-11-28: бош саҳифа реклама каруселлари — 0 / 1 / N реклама, ўнгдан чапга айланиш,
// тегинилганда тўхташ, жойлашув бўйича бошланғич слайд, манба фильтри (пуллик Home тарифи).
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/home/widgets/home_ad_carousel.dart';
import 'package:ava_gurlan/features/home/widgets/home_info_ticker.dart' show kHomeBannerArtAsset;
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HomeAdSlide _s(String id) => HomeAdSlide(id: id, title: 'T$id', subtitle: 'S$id');

TvClip _clip(String id, {String category = 'ad', String tier = 'home', String processing = 'ready'}) => TvClip(
      id: id,
      videoUrl: '',
      posterUrl: '',
      title: id,
      price: 0,
      districtId: '',
      districtLabel: '',
      ownerPhone: '',
      ownerName: '',
      category: category,
      adTier: tier,
      processingStatus: processing,
    );

Finder _slide(String id) => find.byKey(ValueKey('home_ad_slide_$id'));

/// Экранда тўлиқ кўринаётган слайд (PageView бир вақтда биттасини кўрсатади).
String? _visible(WidgetTester t) {
  for (final id in ['a', 'b', 'c']) {
    final f = _slide(id);
    if (f.evaluate().isEmpty) continue;
    if (t.getTopLeft(f).dx.abs() < 1) return id;
  }
  return null;
}

void main() {
  late List<int> opened;
  late int advertise;

  setUp(() {
    opened = [];
    advertise = 0;
  });

  Future<void> pump(WidgetTester t, List<HomeAdSlide> slides, {HomeAdPlacement p = HomeAdPlacement.markets}) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.zero,
          child: HomeAdCarousel(
            placement: p,
            slides: slides,
            onOpen: opened.add,
            onAdvertise: () => advertise++,
            interval: const Duration(seconds: 4),
            resumeDelay: const Duration(seconds: 8),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  Future<void> unmount(WidgetTester t) => t.pumpWidget(const SizedBox());

  testWidgets('0 реклама — «Бу ерда сизнинг рекламангиз…» + «Реклама бериш», босилса onAdvertise', (t) async {
    await pump(t, const []);
    expect(find.byKey(const ValueKey('home_ad_placeholder')), findsOneWidget);
    expect(find.text('home_ad_slot_title'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('home_ad_placeholder_cta')));
    expect(advertise, 1);
    expect(find.byKey(const ValueKey('home_ad_carousel_pages')), findsNothing);
    await unmount(t);
  });

  testWidgets('«Реклама бериш» ўрни (эга 2026-11-28): юқори баннер мегафони чапда, кўзгули, ~25% эн; матн ва тугма ўнгда; 320 px × 1.5 — тошиш йўқ', (t) async {
    await pump(t, const []);
    final art = find.byKey(const ValueKey('home_ad_placeholder_art'));
    expect(art, findsOneWidget);
    expect(t.widget<Transform>(art).transform.storage[0], -1.0, reason: 'горизонтал кўзгу (flipX)');
    final img = t.widget<Image>(find.descendant(of: art, matching: find.byType(Image)));
    expect((img.image as AssetImage).assetName, kHomeBannerArtAsset);
    final card = t.getRect(find.byKey(const ValueKey('home_ad_placeholder')));
    final artRect = t.getRect(art);
    final text = t.getRect(find.text('home_ad_slot_title'));
    final cta = t.getRect(find.byKey(const ValueKey('home_ad_placeholder_cta')));
    expect(artRect.left - card.left, lessThan(16), reason: 'чапда');
    expect(artRect.right, lessThanOrEqualTo(text.left));
    expect(artRect.right, lessThanOrEqualTo(cta.left));
    expect(artRect.width, closeTo(card.width * kHomeAdPlaceholderArtFraction - 8, 1));
    await unmount(t);
    // Тор экран + катта шрифт.
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.5)),
      child: MaterialApp(
        home: Scaffold(
          body: HomeAdCarousel(placement: HomeAdPlacement.markets, slides: const [], onOpen: (_) {}, onAdvertise: () {}),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull, reason: 'RenderFlex тошиши йўқ');
    expect(find.byKey(const ValueKey('home_ad_placeholder_cta')), findsOneWidget);
    await unmount(t);
  });

  testWidgets('1 реклама — статик (PageView йўқ, айланмайди); босилса onOpen(0)', (t) async {
    await pump(t, [_s('a')]);
    expect(find.byKey(const ValueKey('home_ad_carousel_pages')), findsNothing);
    expect(_slide('a'), findsOneWidget);
    await t.pump(const Duration(seconds: 13));
    expect(_slide('a'), findsOneWidget);
    await t.tap(_slide('a'));
    expect(opened, [0]);
    await unmount(t);
  });

  testWidgets('N реклама — ўнгдан чапга, айлана (a → b → c → a); босилган слайд индекси', (t) async {
    await pump(t, [_s('a'), _s('b'), _s('c')]);
    expect(_visible(t), 'a');
    await t.pump(const Duration(seconds: 4));
    // Ўтиш пайтида кейинги слайд ЎНГДАН киради (dx > 0), жорийси чапга кетади.
    await t.pump(const Duration(milliseconds: 150));
    expect(t.getTopLeft(_slide('b')).dx, greaterThan(0));
    expect(t.getTopLeft(_slide('a')).dx, lessThan(0));
    await t.pumpAndSettle();
    expect(_visible(t), 'b');
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(_visible(t), 'c');
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(_visible(t), 'a', reason: 'охиридан кейин яна биринчиси (чексиз айлана)');
    await t.tap(_slide('a'));
    expect(opened, [0]);
    await unmount(t);
  });

  testWidgets('тегиб турилганда тўхтайди; қўйиб юборилгач resumeDelay дан кейин давом этади', (t) async {
    await pump(t, [_s('a'), _s('b'), _s('c')]);
    final g = await t.startGesture(t.getCenter(_slide('a')));
    await t.pump(const Duration(seconds: 9));
    await t.pumpAndSettle();
    expect(_visible(t), 'a', reason: 'бармоқ тегиб турибди');
    await g.up();
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(_visible(t), 'a', reason: 'resumeDelay (8 с) ҳали ўтмади');
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(_visible(t), isNot('a'));
    await unmount(t);
  });

  testWidgets('жойлашув: markets → 1-слайд, services → 2-слайд, transport → 3-слайд', (t) async {
    final slides = [_s('a'), _s('b'), _s('c')];
    await pump(t, slides, p: HomeAdPlacement.services);
    expect(_visible(t), 'b');
    await unmount(t);
    await pump(t, slides, p: HomeAdPlacement.transport);
    expect(_visible(t), 'c');
    expect(find.byKey(const ValueKey('home_ad_carousel_transport')), findsOneWidget);
    await unmount(t);
  });

  test('homeAdCarouselStart: mod N, 0 → 0', () {
    expect(homeAdCarouselStart(HomeAdPlacement.markets, 3), 0);
    expect(homeAdCarouselStart(HomeAdPlacement.services, 3), 1);
    expect(homeAdCarouselStart(HomeAdPlacement.transport, 3), 2);
    expect(homeAdCarouselStart(HomeAdPlacement.transport, 2), 0);
    expect(homeAdCarouselStart(HomeAdPlacement.services, 0), 0);
  });

  test('манба: фақат пуллик Home тарифидаги (home/premium/pro_max) ижро этиладиган реклама', () {
    final out = homeCarouselAds([
      _clip('home'),
      _clip('prem', tier: 'premium'),
      _clip('max', tier: 'pro_max'),
      _clip('basic', tier: 'basic'),
      _clip('vis', tier: 'visibility'),
      _clip('organic', category: 'product', tier: ''),
      _clip('broken', processing: 'error'),
    ]);
    expect(out.map((c) => c.id), ['home', 'prem', 'max']);
  });

  test('HomeAdCarouselFeed: юклайди ва фильтрлайди; хато — аввалги рўйхат қолади', () async {
    var fail = false;
    final feed = HomeAdCarouselFeed(load: () async {
      if (fail) throw StateError('offline');
      return [_clip('a'), _clip('b', tier: 'basic')];
    });
    await feed.refresh();
    expect(feed.ads.value.map((c) => c.id), ['a']);
    fail = true;
    await feed.refresh();
    expect(feed.ads.value.map((c) => c.id), ['a']);
    feed.dispose();
  });

  test('lang: 3 тилда', () {
    for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final m = jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;
      expect((m['home_ad_slot_title'] as String?)?.isNotEmpty, isTrue, reason: l);
      expect((m['home_ad_slot_cta'] as String?)?.isNotEmpty, isTrue, reason: l);
    }
    final cyr = jsonDecode(File('assets/lang/uz_Cyrl.json').readAsStringSync()) as Map<String, dynamic>;
    expect(cyr['home_ad_slot_title'], 'Бу ерда сизнинг рекламангиз бўлиши мумкин');
    expect(cyr['home_ad_slot_cta'], 'Реклама бериш');
  });
}
