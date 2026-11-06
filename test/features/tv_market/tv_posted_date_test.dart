import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_market_feed_screen.dart';
import 'package:ava_gurlan/features/tv_market/utils/tv_posted_date.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_clip_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String? _label(DateTime? at, DateTime now) =>
    tvPostedDateLabel(at, now: now, todayWord: 'Бугун');

void main() {
  group('tvPostedDateLabel', () {
    // 2026-11-05 12:00 Тошкент = 07:00Z.
    final now = DateTime.utc(2026, 11, 5, 7);

    test('шу кун (Тошкент) → «Бугун, ҲҲ:ДД» Тошкент вақтида', () {
      // 09:35Z = 14:35 Тошкент.
      expect(_label(DateTime.utc(2026, 11, 5, 9, 35), now), 'Бугун, 14:35');
    });

    test('аввалги кун → «КК.ОО.ЙЙЙЙ»', () {
      expect(_label(DateTime.utc(2026, 11, 3, 8, 0), now), '03.11.2026');
    });

    test('UTC бўйича кеча, Тошкент бўйича бугун (19:30Z = 00:30) → «Бугун»', () {
      expect(_label(DateTime.utc(2026, 11, 4, 19, 30), now), 'Бугун, 00:30');
    });

    test('UTC бўйича бугун, Тошкент бўйича эрта эмас: 18:59Z кеча = 23:59', () {
      expect(_label(DateTime.utc(2026, 11, 4, 18, 59), now), '04.11.2026');
    });

    test('қурилма вақт зонасига боғлиқ эмас (local DateTime ҳам UTC орқали)', () {
      final at = DateTime.utc(2026, 11, 5, 9, 35).toLocal();
      expect(_label(at, now.toLocal()), 'Бугун, 14:35');
    });

    test('эски клип (чегарадан олдин) → сана йўқ', () {
      final before = kTvPostedDateSince.subtract(const Duration(seconds: 1));
      expect(_label(before, now), isNull);
    });

    test('чегара пайтининг ўзи → сана бор', () {
      expect(_label(kTvPostedDateSince, kTvPostedDateSince), isNotNull);
    });

    test('createdAt йўқ (serverTimestamp ҳали келмаган) → сана йўқ', () {
      expect(_label(null, now), isNull);
    });
  });

  group('TvClipOverlay сана белгиси', () {
    TvClip clip(DateTime? createdAt) => TvClip(
          id: 'c1',
          videoUrl: 'https://example.test/a.mp4',
          posterUrl: '',
          title: 'Сотилади',
          price: 0,
          districtId: 'd1',
          districtLabel: 'Гурлан',
          ownerPhone: '+998900000000',
          ownerName: 'Аваз',
          category: 'product',
          createdAt: createdAt,
        );

    Future<void> pump(WidgetTester tester, TvClip c) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            TvClipOverlay(
              clip: c,
              onContact: () {},
              onLike: () {},
              onComment: () {},
              onShare: () {},
              onSave: () {},
            ),
          ]),
        ),
      ));
    }

    testWidgets('янги клип: сана тепа чап бурчакда, оқ хирароқ', (tester) async {
      // Чегарадан кейинги СОБИТ вақт; кутилган матн ҳақиқий «ҳозир»дан ҳисобланади
      // (аввал «03.11.2026» қотирилган эди — шу куни тест «Бугун, …» кўриб йиқиларди).
      final posted = kTvPostedDateSince.add(const Duration(minutes: 1));
      await pump(tester, clip(posted));
      final f = find.byKey(const ValueKey('tv-posted-date'));
      expect(f, findsOneWidget);
      expect(tester.widget<Text>(f).data,
          tvPostedDateLabel(posted, now: DateTime.now(), todayWord: 'tv_posted_today'));
      final pos = tester.getTopLeft(f);
      expect(pos.dx, 12);
      expect(pos.dy, lessThan(200), reason: 'сана тепада бўлиши керак');
      final color = tester.widget<Text>(f).style!.color!;
      expect(color.a, inExclusiveRange(0.5, 1.0));
    });

    // Регрессия (эга скриншоти 2026-11-06): ҳақиқий лента тузилмасида
    // (`extendBodyBehindAppBar` + AppBar + 48 px таблар) сана табдан ≈104 px
    // пастда эди — AppBar баландлиги иккинчи марта қўшилган.
    testWidgets('ҳақиқий лентада: сана таблар остидан 3 px; таб ёзуви яшил чизиқдан 1 px', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final posted = kTvPostedDateSince.add(const Duration(minutes: 1));
      await tester.pumpWidget(MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: TabBar(
                  dividerHeight: 0,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(fontSize: 11.5, height: 1.15),
                  tabs: [
                    tvFeedTabLabel('AVAGram'),
                    tvFeedTabLabel('Янгиликлар', showBadge: true, badgeLabel: 'янги'),
                    tvFeedTabLabel('Реклама ва эълонлар'),
                  ],
                ),
              ),
            ),
            body: Stack(children: [
              TvClipOverlay(
                clip: clip(posted),
                onContact: () {},
                onLike: () {},
                onComment: () {},
                onShare: () {},
                onSave: () {},
              ),
            ]),
          ),
        ),
      ));
      final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
      final dateTop = tester.getTopLeft(find.byKey(const ValueKey('tv-posted-date'))).dy;
      expect(dateTop - appBarBottom, kTvPostedDateGap);

      final tabBar = tester.getRect(find.byType(TabBar));
      final indicatorTop = tabBar.bottom - 2.5;
      for (final t in ['AVAGram', 'Янгиликлар']) {
        final textBottom = tester.getRect(find.text(t)).bottom;
        expect(indicatorTop - textBottom, closeTo(kTvTabLabelGap, 0.01), reason: t);
      }
      // 2 қаторли ёрлиқ ҳам пастга текисланади (тепадан кесилмайди).
      final longRect = tester.getRect(find.text('Реклама ва эълонлар'));
      expect(indicatorTop - longRect.bottom, closeTo(kTvTabLabelGap, 0.01));
      expect(longRect.top, greaterThanOrEqualTo(tabBar.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('эски клип: сана йўқ', (tester) async {
      await pump(tester, clip(DateTime.utc(2026, 10, 31, 8)));
      expect(find.byKey(const ValueKey('tv-posted-date')), findsNothing);
    });

    testWidgets('createdAt йўқ: сана йўқ', (tester) async {
      await pump(tester, clip(null));
      expect(find.byKey(const ValueKey('tv-posted-date')), findsNothing);
    });
  });
}
