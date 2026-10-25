import 'package:ava_gurlan/features/home/widgets/home_realty_section.dart';
import 'package:ava_gurlan/features/realty/realty_tabs.dart';
import 'package:ava_gurlan/features/realty/screens/realty_detail_screen.dart';
import 'package:ava_gurlan/features/realty/widgets/realty_card.dart';
import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:ava_gurlan/repositories/realty_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Кўчмас мулк: пуллик РЕКЛАМА/СРОЧНО даражаси харидорга МАВЖУД ёрлиқ
/// (`RealtyTierBadge`, «РЕКЛАМА»/«СРОЧНО») билан кўрсатилади — фақат муддати
/// амалда бўлса; янги «Реклама» белгиси қўшилмайди (эга, 2026-10-25).
///
/// Локализация делегати атайлаб уланмаган — `context.tr` калитнинг ўзини
/// қайтаради (`realty_tier_promo` ва ҳ.к.).
class _FakeRepo implements RealtyRepository {
  @override
  Future<RealtyDetail?> fetchDetail(String listingId) async => null;

  @override
  Stream<int> watchUnlocksLeft() => Stream.value(0);

  @override
  Future<String> fetchAgentPhone() async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _pill = ValueKey('realty_tier_badge');
const _homeLabel = ValueKey('home_realty_tier_label');

RealtyListing _listing({
  RealtyTier tier = RealtyTier.plain,
  DateTime? tierUntil,
}) =>
    RealtyListing(
      id: 'L1',
      ownerKey: 'k',
      ownerName: 'Эга',
      deal: RealtyDeal.sale,
      tier: tier,
      title: 'Уч хонали уй',
      text: 'Таъмирланган',
      priceText: '50 000 \$',
      areaLat: 41.85,
      areaLng: 60.39,
      status: 'active',
      tierUntil: tierUntil,
    );

void main() {
  final now = DateTime(2026, 10, 25, 12);
  final future = DateTime.now().add(const Duration(days: 5));
  final past = DateTime.now().subtract(const Duration(days: 1));

  group('RealtyListing.isPromotedAt / displayTier', () {
    test('РЕКЛАМА/СРОЧНО муддати келажакда — амалда', () {
      expect(
        _listing(tier: RealtyTier.promo, tierUntil: now.add(const Duration(days: 1)))
            .isPromotedAt(now),
        isTrue,
      );
      expect(
        _listing(tier: RealtyTier.urgent, tierUntil: now.add(const Duration(minutes: 1)))
            .isPromotedAt(now),
        isTrue,
      );
    });

    test('муддати ўтган ёки айнан ҳозир тугаган — амалда эмас', () {
      expect(
        _listing(tier: RealtyTier.promo, tierUntil: now.subtract(const Duration(seconds: 1)))
            .isPromotedAt(now),
        isFalse,
      );
      expect(_listing(tier: RealtyTier.urgent, tierUntil: now).isPromotedAt(now), isFalse);
    });

    test('пуллик даража, лекин tierUntil йўқ — амалда эмас', () {
      expect(_listing(tier: RealtyTier.promo).isPromotedAt(now), isFalse);
    });

    test('ОДДИЙ — tierUntil бўлса ҳам амалда эмас', () {
      expect(
        _listing(tier: RealtyTier.plain, tierUntil: now.add(const Duration(days: 9)))
            .isPromotedAt(now),
        isFalse,
      );
    });

    test('displayTier: амалда — ўз даражаси; тугаган — ОДДИЙ', () {
      expect(_listing(tier: RealtyTier.urgent, tierUntil: future).displayTier, RealtyTier.urgent);
      expect(_listing(tier: RealtyTier.promo, tierUntil: past).displayTier, RealtyTier.plain);
      expect(_listing(tier: RealtyTier.promo).displayTier, RealtyTier.plain);
      expect(_listing().displayTier, RealtyTier.plain);
    });

    test('Firestore ҳужжатидан: tier + Timestamp tierUntil', () {
      final live = RealtyListing.fromMap('x', {
        'tier': 'promo',
        'tierUntil': Timestamp.fromDate(now.add(const Duration(days: 3))),
      });
      expect(live.isPromotedAt(now), isTrue);
      final unknownTier = RealtyListing.fromMap('y', {
        'tier': 'vip',
        'tierUntil': Timestamp.fromDate(now.add(const Duration(days: 3))),
      });
      expect(unknownTier.isPromotedAt(now), isFalse, reason: 'номаълум даража = ОДДИЙ');
    });
  });

  group('RealtyDetailScreen — мавжуд ёрлиқ (RealtyTierBadge)', () {
    Future<void> pump(WidgetTester tester, RealtyListing l) async {
      await tester.pumpWidget(MaterialApp(
        home: RealtyDetailScreen(listing: l, repository: _FakeRepo()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('амалдаги СРОЧНО — «СРОЧНО» ёрлиғи, битта, номи бор', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.urgent, tierUntil: future));
      expect(find.byKey(_pill), findsOneWidget);
      expect(find.text('realty_tier_urgent'), findsOneWidget);
      // Қатор битта семантик тугунга бирлашади: «СРОЧНО, Сотиш».
      expect(find.bySemanticsLabel(RegExp('realty_tier_urgent')), findsOneWidget);
      expect(find.text('tv_ad_label'), findsNothing, reason: 'иккинчи белги йўқ');
    });

    testWidgets('амалдаги РЕКЛАМА — «РЕКЛАМА» ёрлиғи', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.promo, tierUntil: future));
      expect(find.text('realty_tier_promo'), findsOneWidget);
    });

    testWidgets('REGRESSION: муддати ўтган РЕКЛАМА — пуллик ёрлиқ йўқ (ОДДИЙ)', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.promo, tierUntil: past));
      expect(find.text('realty_tier_promo'), findsNothing);
      expect(find.text('realty_tier_plain'), findsOneWidget);
    });

    testWidgets('ОДДИЙ — пуллик ёрлиқ йўқ', (tester) async {
      await pump(tester, _listing());
      expect(find.text('realty_tier_promo'), findsNothing);
      expect(find.text('realty_tier_urgent'), findsNothing);
      expect(find.byKey(_pill), findsOneWidget, reason: '«ОДДИЙ» ёрлиғи аввалгидек');
    });
  });

  group('RealtyCard — янги белги қўшилмаган', () {
    testWidgets('амалдаги пуллик картада ҳам қўшимча белги йўқ (ранг тасмаси — мавжуд)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RealtyCard(
            listing: _listing(tier: RealtyTier.promo, tierUntil: future),
            onTap: () {},
          ),
        ),
      ));
      expect(find.byKey(_pill), findsNothing);
      expect(find.text('tv_ad_label'), findsNothing);
      expect(find.text('realty_tier_promo'), findsNothing);
    });
  });

  group('HomeRealtyRow — бош саҳифа қатори (ранг изоҳи йўқ жой)', () {
    Future<void> pump(WidgetTester tester, RealtyListing l) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 14,
                child: HomeRealtyRow(listing: l, onTap: () {}),
              ),
            ),
          ),
        );

    testWidgets('амалдаги СРОЧНО — даража номи, 14 px қаторга сиғади', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.urgent, tierUntil: future));
      expect(tester.takeException(), isNull);
      expect(find.byKey(_homeLabel), findsOneWidget);
      expect(find.text('realty_tier_urgent'), findsOneWidget);
    });

    testWidgets(
        'REGRESSION: 320 px, шрифт 130%, узун нарх + узун uz_Latn ном — қатордан чиқмайди',
        (tester) async {
      // Ҳақиқий матнлар: делегатсиз `context.tr` калитни қайтаради, шунинг
      // учун «SHOSHILINCH» дан узун калит ('realty_tier_urgent', 18 белги)
      // ўз-ўзидан оғирроқ ҳолат.
      for (final w in [280.0, 320.0]) {
        for (final until in [future, null]) {
          await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: w,
                    height: 19,
                    child: HomeRealtyRow(
                      listing: RealtyListing(
                        id: 'L1',
                        ownerKey: 'k',
                        ownerName: 'E',
                        deal: RealtyDeal.sale,
                        tier: RealtyTier.urgent,
                        title: 'Uch xonali uy, Gurlan markazi',
                        text: 'x',
                        priceText: "1 200 000 000 so'm",
                        areaLat: 41.85,
                        areaLng: 60.39,
                        status: 'active',
                        tierUntil: until,
                      ),
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ));
          expect(tester.takeException(), isNull, reason: 'w=$w until=$until');
          // Сарлавҳага ҳам жой қолади.
          expect(
            tester.getSize(find.textContaining('Uch xonali')).width,
            greaterThan(w * 0.3),
            reason: 'w=$w until=$until',
          );
        }
      }
    });

    testWidgets('нуқта ва нарх ранги — displayTier (тугаган СРОЧНО = ОДДИЙ ранги)', (tester) async {
      Color priceColor() =>
          tester.widget<Text>(find.text('50 000 \$')).style!.color!;
      await pump(tester, _listing(tier: RealtyTier.urgent, tierUntil: past));
      expect(priceColor(), RealtyTabs.colorFor(RealtyTier.plain));
      await pump(tester, _listing(tier: RealtyTier.urgent, tierUntil: future));
      expect(priceColor(), RealtyTabs.colorFor(RealtyTier.urgent));
    });

    test('статик харита ранги: тугаган пуллик эълон рангни кўтармайди', () {
      String url(List<RealtyListing> l) => realtyStaticMapUrl(
          lat: 41.85, lng: 60.39, width: 400, height: 140, listings: l);
      final plainHex = (RealtyTabs.colorFor(RealtyTier.plain).toARGB32() & 0xFFFFFF)
          .toRadixString(16)
          .padLeft(6, '0');
      final urgentHex = (RealtyTabs.colorFor(RealtyTier.urgent).toARGB32() & 0xFFFFFF)
          .toRadixString(16)
          .padLeft(6, '0');
      expect(url([_listing(tier: RealtyTier.urgent, tierUntil: past)]), contains('color=0x$plainHex'));
      expect(url([_listing(tier: RealtyTier.urgent, tierUntil: future)]), contains('color=0x$urgentHex'));
    });

    testWidgets('муддати ўтган ёки ОДДИЙ — ном йўқ', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.urgent, tierUntil: past));
      expect(find.byKey(_homeLabel), findsNothing);
      await pump(tester, _listing());
      expect(find.byKey(_homeLabel), findsNothing);
    });
  });
}
