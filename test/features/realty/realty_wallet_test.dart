import 'dart:async';

import 'package:ava_gurlan/features/realty/screens/realty_pro_screen.dart';
import 'package:ava_gurlan/features/realty/widgets/realty_package_sheet.dart';
import 'package:ava_gurlan/features/realty/widgets/realty_tier_sheet.dart';
import 'package:ava_gurlan/features/realty/widgets/realty_wallet.dart';
import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:ava_gurlan/repositories/realty_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _plans = [
  RealtyProPlan(id: 'pro_25', objects: 25, days: 30, price: 250000),
  RealtyProPlan(id: 'pro_60', objects: 60, days: 30, price: 500000),
];

class _FakeRepo implements RealtyRepository {
  final List<Object?> pkgResults = [];
  final List<Object?> proResults = [];
  final List<Object?> tierResults = [];

  @override
  Future<Map<int, int>> loadPackagePricing() async => const {5: 30000, 10: 50000};

  @override
  Future<int> purchasePackage(int size, {String? idempotencyKey}) async {
    final r = pkgResults.isEmpty ? null : pkgResults.removeAt(0);
    if (r != null) throw r;
    return size;
  }

  @override
  Future<List<RealtyProPlan>> loadProPlans() async => _plans;

  @override
  Future<RealtyQuota> fetchQuota() async => const RealtyQuota(used: 2, limit: 2, isPro: false);

  @override
  Future<String> loadTemplateText() async => '';

  @override
  Future<void> purchaseProPackage(String planId, {String? idempotencyKey}) async {
    final r = proResults.isEmpty ? null : proResults.removeAt(0);
    if (r != null) throw r;
  }

  @override
  Future<Map<RealtyTier, Map<int, int>>> loadPricing() async => const {
        RealtyTier.promo: {7: 20000, 15: 35000, 30: 60000},
        RealtyTier.urgent: {3: 25000, 7: 45000, 15: 80000},
      };

  @override
  Future<RealtyPurchaseResult> purchaseTier({
    required String listingId,
    required RealtyTier tier,
    required int durationDays,
    String? idempotencyKey,
  }) async {
    final r = tierResults.isEmpty ? null : tierResults.removeAt(0);
    if (r != null) throw r;
    return RealtyPurchaseResult(
      listingId: listingId,
      tier: tier,
      durationDays: durationDays,
      price: 1,
      tierUntil: DateTime(2030),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

const _listing = RealtyListing(
  id: 'L1',
  ownerKey: 'k',
  ownerName: 'Али',
  deal: RealtyDeal.sale,
  tier: RealtyTier.plain,
  title: 'Уй',
  text: 'Тавсиф',
  areaLat: 41.8,
  areaLng: 60.4,
  status: 'active',
);

void main() {
  group('RealtyBalanceBar / Notice — баланс сотиб олишдан ОЛДИН', () {
    Future<int> pump(WidgetTester t, {int? balance, int? price}) async {
      var topUps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RealtyBalanceBar(balance: balance, price: price, onTopUp: () => topUps++),
        ),
      ));
      final btn = find.byKey(const ValueKey('realty-balance-topup'));
      if (btn.evaluate().isNotEmpty) await t.tap(btn);
      return topUps;
    }

    testWidgets('REGRESSION: баланс етмаса — огоҳлантириш ва «Ҳамённи тўлдириш» БИР босишда', (t) async {
      final topUps = await pump(t, balance: 1000, price: 30000);
      expect(find.byKey(const ValueKey('realty-balance-short')), findsOneWidget);
      expect(topUps, 1);
    });

    testWidgets('баланс етарли — фақат «Ҳамёнда: X», тўлдириш тугмаси йўқ', (t) async {
      await pump(t, balance: 100000, price: 30000);
      expect(find.byKey(const ValueKey('realty-balance-info')), findsOneWidget);
      expect(find.byKey(const ValueKey('realty-balance-topup')), findsNothing);
    });

    testWidgets('баланс аниқ нархга тенг — етарли', (t) async {
      await pump(t, balance: 30000, price: 30000);
      expect(find.byKey(const ValueKey('realty-balance-short')), findsNothing);
    });

    testWidgets('баланс номаълум (оқимдан ҳали келмади/хато) — ҳеч нарса, ёлғон огоҳлантириш йўқ', (t) async {
      await pump(t, balance: null, price: 30000);
      expect(find.byKey(const ValueKey('realty-balance-short')), findsNothing);
      expect(find.byKey(const ValueKey('realty-balance-info')), findsNothing);
    });

    testWidgets('нарх ҳали номаълум — етмайди деб айтилмайди', (t) async {
      await pump(t, balance: 0, price: null);
      expect(find.byKey(const ValueKey('realty-balance-short')), findsNothing);
    });

    testWidgets('оқимли вариант: оқимдан келган қиймат билан ишлайди', (t) async {
      final c = StreamController<int>();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: RealtyBalanceNotice(balance: c.stream, price: 50000, onTopUp: () {})),
      ));
      expect(find.byKey(const ValueKey('realty-balance-short')), findsNothing);
      c.add(10);
      await t.pump();
      expect(find.byKey(const ValueKey('realty-balance-short')), findsOneWidget);
      await c.close();
    });
  });

  group('харид хатоси — варақ ИЧИДА, баланс етмаса «Ҳамённи тўлдириш» тугмаси билан', () {
    Future<void> openPackage(WidgetTester t, _FakeRepo repo, {Stream<int>? balance, required VoidCallback onWallet}) async {
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showRealtyPackageSheet(ctx, repository: repo, balance: balance, openWallet: onWallet),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('REGRESSION: пакет: insufficient_balance → хато ВАРАҚНИНГ ИЧИДА (snackbar ортида қолмайди), тугма ҳамённи очади', (t) async {
      var wallet = 0;
      final repo = _FakeRepo()..pkgResults.add(const RealtyException('insufficient_balance'));
      await openPackage(t, repo, onWallet: () => wallet++);
      await t.tap(find.byType(ElevatedButton).last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('realty-inline-error')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing, reason: 'варақ очиқ — snackbar унинг ортида қолар эди');
      await t.tap(find.byKey(const ValueKey('realty-inline-error-topup')));
      await t.pump();
      expect(wallet, 1);
    });

    testWidgets('пакет: бошқа хато (мас., listing_blocked) — варақ ичида, тўлдириш тугмаси ЙЎҚ', (t) async {
      final repo = _FakeRepo()..pkgResults.add(const RealtyException('listing_blocked'));
      await openPackage(t, repo, onWallet: () {});
      await t.tap(find.byType(ElevatedButton).last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('realty-inline-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('realty-inline-error-topup')), findsNothing);
    });

    testWidgets('пакет: хато ўлчам алмаштирилганда ёки қайта босилганда йўқолади', (t) async {
      final repo = _FakeRepo()..pkgResults.add(const RealtyException('insufficient_balance'));
      await openPackage(t, repo, onWallet: () {});
      await t.tap(find.byType(ElevatedButton).last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('realty-inline-error')), findsOneWidget);
      await t.tap(find.text('10'));
      await t.pump();
      expect(find.byKey(const ValueKey('realty-inline-error')), findsNothing);
    });

    testWidgets('пакет: кутилмаган хато — варақ ичида умумий хабар', (t) async {
      final repo = _FakeRepo()..pkgResults.add(StateError('boom'));
      await openPackage(t, repo, onWallet: () {});
      await t.tap(find.byType(ElevatedButton).last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('realty-inline-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('realty-inline-error-topup')), findsNothing);
    });

    testWidgets('пакет варағи: баланс 5 000 — 5 объектли пакетга (30 000) етмаслиги ОЛДИНДАН кўринади', (t) async {
      var wallet = 0;
      await openPackage(t, _FakeRepo(), balance: Stream.value(5000), onWallet: () => wallet++);
      await t.pump();
      expect(find.byKey(const ValueKey('realty-balance-short')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('realty-balance-topup')));
      expect(wallet, 1);
    });

    testWidgets('пакет варағи: баланс етарли — огоҳлантириш йўқ', (t) async {
      await openPackage(t, _FakeRepo(), balance: Stream.value(500000), onWallet: () {});
      await t.pump();
      expect(find.byKey(const ValueKey('realty-balance-short')), findsNothing);
      expect(find.byKey(const ValueKey('realty-balance-info')), findsOneWidget);
    });

    testWidgets('тариф варағи: баланс етмаса олдиндан огоҳлантириш; xatoda тугма', (t) async {
      var wallet = 0;
      final repo = _FakeRepo()..tierResults.add(const RealtyException('insufficient_balance'));
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showRealtyTierSheet(ctx,
                  listing: _listing, repository: repo, balance: Stream.value(1000), openWallet: () => wallet++),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('realty-balance-short')), findsOneWidget);

      await t.tap(find.byType(ElevatedButton).last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('realty-inline-error')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await t.tap(find.byKey(const ValueKey('realty-inline-error-topup')));
      await t.pump();
      expect(wallet, 1);
    });
  });

  group('профессионал пакет экрани', () {
    Future<void> pump(WidgetTester t, _FakeRepo repo, {Stream<int>? balance, VoidCallback? onWallet}) async {
      await t.binding.setSurfaceSize(const Size(800, 1600));
      await t.pumpWidget(MaterialApp(
        home: RealtyProScreen(repository: repo, balance: balance, openWallet: onWallet ?? () {}),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('баланс 300 000: 250 000 лик режага етади, 500 000 лигига етмайди — фақат шунга белги', (t) async {
      await pump(t, _FakeRepo(), balance: Stream.value(300000));
      expect(find.byKey(const ValueKey('pro-short-pro_60')), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-short-pro_25')), findsNothing);
      expect(find.byKey(const ValueKey('realty-balance-short')), findsNothing, reason: 'энг арзон режага етади — қатор «етмайди» эмас');
    });

    testWidgets('баланс ҳеч бир режага етмайди — огоҳлантириш + «Ҳамённи тўлдириш» ишлайди', (t) async {
      var wallet = 0;
      await pump(t, _FakeRepo(), balance: Stream.value(1000), onWallet: () => wallet++);
      expect(find.byKey(const ValueKey('realty-balance-short')), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-short-pro_25')), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-short-pro_60')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('realty-balance-topup')));
      expect(wallet, 1);
    });

    testWidgets('баланс номаълум — ҳеч қандай «етмайди» белгиси йўқ', (t) async {
      await pump(t, _FakeRepo(), balance: const Stream<int>.empty());
      expect(find.byKey(const ValueKey('pro-short-pro_25')), findsNothing);
      expect(find.byKey(const ValueKey('realty-balance-short')), findsNothing);
    });

    testWidgets('харид: insufficient_balance → snackbar тугмаси ҳамённи очади', (t) async {
      var wallet = 0;
      final repo = _FakeRepo()..proResults.add(const RealtyException('insufficient_balance'));
      await pump(t, repo, balance: Stream.value(999999999), onWallet: () => wallet++);
      await t.tap(find.byKey(const ValueKey('pro-buy-pro_25')));
      await t.pumpAndSettle();
      expect(find.byType(SnackBarAction), findsOneWidget);
      await t.tap(find.byType(SnackBarAction));
      await t.pump();
      expect(wallet, 1);
    });
  });
}
