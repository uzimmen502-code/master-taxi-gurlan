import 'package:ava_gurlan/core/widgets/ava_ad_badge.dart';
import 'package:ava_gurlan/core/theme/ava_tokens.dart';
import 'package:ava_gurlan/features/realty/screens/realty_detail_screen.dart';
import 'package:ava_gurlan/features/realty/widgets/realty_card.dart';
import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:ava_gurlan/repositories/realty_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Кўчмас мулк: пуллик РЕКЛАМА/СРОЧНО жойлашуви харидорга «Реклама» деб
/// белгиланади — ФАҚАТ муддати амалда бўлса (2026-10-25).
///
/// Локализация делегати атайлаб уланмаган — `context.tr` калитнинг ўзини
/// қайтаради (`tv_ad_label`).
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

const _badge = ValueKey('ava_ad_badge');

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

  group('RealtyListing.isPromotedAt — «пуллик ва амалда»', () {
    test('РЕКЛАМА/СРОЧНО муддати келажакда — ҳа', () {
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

    test('муддати ўтган ёки айнан ҳозир тугаган — йўқ', () {
      expect(
        _listing(tier: RealtyTier.promo, tierUntil: now.subtract(const Duration(seconds: 1)))
            .isPromotedAt(now),
        isFalse,
      );
      expect(_listing(tier: RealtyTier.urgent, tierUntil: now).isPromotedAt(now), isFalse);
    });

    test('пуллик даража, лекин tierUntil йўқ — йўқ (тўлов исботи йўқ)', () {
      expect(_listing(tier: RealtyTier.promo).isPromotedAt(now), isFalse);
    });

    test('ОДДИЙ (бепул) — tierUntil бўлса ҳам йўқ', () {
      expect(
        _listing(tier: RealtyTier.plain, tierUntil: now.add(const Duration(days: 9)))
            .isPromotedAt(now),
        isFalse,
      );
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

  group('RealtyCard (лента ва хабарнома рўйхати)', () {
    Future<void> pump(WidgetTester tester, RealtyListing l) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: RealtyCard(listing: l, onTap: () {}))),
        );

    testWidgets('амалдаги пуллик — белги бор', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.promo, tierUntil: future));
      expect(find.byKey(_badge), findsOneWidget);
      expect(find.text('tv_ad_label'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('СРОЧНО ҳам пуллик — белги бор', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.urgent, tierUntil: future));
      expect(find.byKey(_badge), findsOneWidget);
    });

    testWidgets('муддати ўтган пуллик — белги йўқ', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.promo, tierUntil: past));
      expect(find.byKey(_badge), findsNothing);
    });

    testWidgets('бепул ОДДИЙ — белги йўқ', (tester) async {
      await pump(tester, _listing());
      expect(find.byKey(_badge), findsNothing);
    });
  });

  group('RealtyDetailScreen', () {
    Future<void> pump(WidgetTester tester, RealtyListing l) async {
      await tester.pumpWidget(MaterialApp(
        home: RealtyDetailScreen(listing: l, repository: _FakeRepo()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('амалдаги СРОЧНО — белги бор', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.urgent, tierUntil: future));
      expect(find.byKey(_badge), findsOneWidget);
      // Қатор битта семантик тугунга бирлашади: «СРОЧНО, Реклама, Сотиш».
      expect(find.bySemanticsLabel(RegExp('tv_ad_label')), findsOneWidget);
    });

    testWidgets('муддати ўтган — белги йўқ; ОДДИЙ — белги йўқ', (tester) async {
      await pump(tester, _listing(tier: RealtyTier.urgent, tierUntil: past));
      expect(find.byKey(_badge), findsNothing);
      await pump(tester, _listing());
      expect(find.byKey(_badge), findsNothing);
    });
  });

  group('AvaAdBadge inline (бош саҳифа 14 px қатори)', () {
    testWidgets('14 px қаторга сиғади, қутисиз, экран ўқувчиси учун ном бор', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('Уй', style: AvaText.feedRow)),
                const SizedBox(width: 8),
                const AvaAdBadge(inline: true),
                const SizedBox(width: 8),
                Text('50 000 \$', style: AvaText.feedRow),
              ],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byKey(_badge), findsOneWidget);
      expect(find.byType(DecoratedBox).evaluate().where(
            (e) => e.widget.key == _badge,
          ), isEmpty);
      expect(find.bySemanticsLabel('tv_ad_label'), findsOneWidget);
    });
  });
}
