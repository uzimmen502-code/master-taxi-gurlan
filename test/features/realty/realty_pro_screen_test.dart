import 'dart:async';

import 'package:ava_gurlan/features/realty/screens/realty_pro_screen.dart';
import 'package:ava_gurlan/features/realty/widgets/realty_package_sheet.dart';
import 'package:ava_gurlan/repositories/realty_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _plans = [
  RealtyProPlan(id: 'pro_25', objects: 25, days: 30, price: 250000),
  RealtyProPlan(id: 'pro_60', objects: 60, days: 30, price: 500000),
];
const _quota = RealtyQuota(used: 2, limit: 2, isPro: false);

/// Фақат керакли методлар; қолгани чақирилса — хато (тест аниқ).
class _FakeRepo implements RealtyRepository {
  final plansC = Completer<List<RealtyProPlan>>();
  final quotaC = Completer<RealtyQuota>();
  final templateC = Completer<String>();
  final calls = <String>[];
  final proKeys = <String>[];
  final pkgKeys = <String>[];

  /// Навбатдаги харид натижаси: `null` — муваффақият, `Exception` — отилади.
  final List<Object?> proResults = [];
  final List<Object?> pkgResults = [];
  Map<int, int> pricing = const {5: 30000, 10: 50000};
  int pricingLoads = 0;

  @override
  Future<List<RealtyProPlan>> loadProPlans() {
    calls.add('plans');
    return plansC.future;
  }

  @override
  Future<RealtyQuota> fetchQuota() {
    calls.add('quota');
    return quotaC.future;
  }

  @override
  Future<String> loadTemplateText() {
    calls.add('template');
    return templateC.future;
  }

  @override
  Future<void> purchaseProPackage(String planId, {String? idempotencyKey}) async {
    proKeys.add(idempotencyKey ?? '');
    final r = proResults.isEmpty ? null : proResults.removeAt(0);
    if (r != null) throw r;
  }

  @override
  Future<Map<int, int>> loadPackagePricing() async {
    pricingLoads++;
    return pricing;
  }

  @override
  Future<int> purchasePackage(int size, {String? idempotencyKey}) async {
    pkgKeys.add(idempotencyKey ?? '');
    final r = pkgResults.isEmpty ? null : pkgResults.removeAt(0);
    if (r != null) throw r;
    return size;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pumpPro(WidgetTester t, _FakeRepo repo, {RealtyQuota? initial, Future<List<RealtyProPlan>>? prepared}) async {
  await t.pumpWidget(MaterialApp(
    home: RealtyProScreen(repository: repo, initialQuota: initial, plansFuture: prepared),
  ));
}

void main() {
  group('RealtyProScreen — тез очилиши', () {
    testWidgets('REGRESSION: учала сўров ПАРАЛЛЕЛ бошланади (аввал кетма-кет эди)', (t) async {
      final repo = _FakeRepo();
      await _pumpPro(t, repo);
      // Ҳеч бири тугамаган — аммо учаласи аллақачон чақирилган.
      expect(repo.calls.toSet(), {'plans', 'quota', 'template'});
    });

    testWidgets('экран дарҳол очилади: тўлиқ экран айлантирувчи йўқ, бўлимлар ўз юкланишини кўрсатади', (t) async {
      final repo = _FakeRepo();
      await _pumpPro(t, repo);
      expect(find.byKey(const ValueKey('pro-quota-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-plans-loading')), findsOneWidget);
      expect(find.byType(TextField), findsWidgets, reason: 'шаблон ва жамоа бўлимлари кутмасдан кўринади');
    });

    testWidgets('чақирувчи билган квота дарҳол кўринади (квота айлантирувчиси йўқ)', (t) async {
      final repo = _FakeRepo();
      await _pumpPro(t, repo, initial: _quota);
      expect(find.byKey(const ValueKey('pro-quota-loading')), findsNothing);
    });

    testWidgets('олдиндан бошланган режалар сўрови қайта юборилмайди', (t) async {
      final repo = _FakeRepo();
      await _pumpPro(t, repo, prepared: Future.value(_plans));
      await t.pump();
      expect(repo.calls.contains('plans'), isFalse);
      expect(find.byKey(const ValueKey('pro-buy-pro_25')), findsOneWidget);
    });

    testWidgets('режалар келгач кўринади, бошқа бўлимлар кутилмайди', (t) async {
      final repo = _FakeRepo();
      await _pumpPro(t, repo);
      repo.plansC.complete(_plans);
      await t.pump();
      expect(find.byKey(const ValueKey('pro-buy-pro_25')), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-quota-loading')), findsOneWidget, reason: 'квота ҳали келмади — алоҳида');
    });

    testWidgets('REGRESSION: режалар юкланмаса — жим бўш жой эмас, «қайта юклаш»', (t) async {
      final repo = _FakeRepo();
      await _pumpPro(t, repo);
      repo.plansC.complete(const []);
      await t.pump();
      expect(find.byKey(const ValueKey('pro-plans-failed')), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-plans-retry')), findsOneWidget);
    });

    testWidgets('квота хатода (маълумот йўқ) — «0 / 0» ва «тўлди» кўрсатилмайди', (t) async {
      final repo = _FakeRepo();
      await _pumpPro(t, repo);
      repo.quotaC.complete(RealtyQuota.empty);
      await t.pump();
      expect(find.byKey(const ValueKey('pro-quota-loading')), findsNothing);
      expect(find.textContaining('0 / 0'), findsNothing);
    });

    testWidgets('шаблон юкланганда фойдаланувчи ёзган матн устидан ЁЗИЛМАЙДИ', (t) async {
      final repo = _FakeRepo();
      await _pumpPro(t, repo);
      await t.enterText(find.byType(TextField).first, 'менинг матним');
      repo.templateC.complete('сервердаги шаблон');
      await t.pump();
      expect(find.text('менинг матним'), findsOneWidget);
      expect(find.text('сервердаги шаблон'), findsNothing);
    });
  });

  group('харид: идемпотентлик калити ва тугма ҳолати', () {
    Future<_FakeRepo> ready(WidgetTester t) async {
      final repo = _FakeRepo();
      await _pumpPro(t, repo);
      repo.plansC.complete(_plans);
      repo.quotaC.complete(_quota);
      repo.templateC.complete('');
      await t.pump();
      return repo;
    }

    testWidgets('REGRESSION: тармоқ узилди (натижа номаълум) → қайта уриниш ШУ калит билан', (t) async {
      final repo = await ready(t);
      repo.proResults.add(TimeoutException('lost'));
      await t.tap(find.byKey(const ValueKey('pro-buy-pro_25')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('pro-buy-pro_25')));
      await t.pump();
      expect(repo.proKeys.length, 2);
      expect(repo.proKeys[0], isNotEmpty);
      expect(repo.proKeys[1], repo.proKeys[0], reason: 'бир хил калит — сервер пулни иккинчи марта ечмайди');
    });

    testWidgets('REGRESSION: кутилмаган хатодан кейин тугма қотиб қолмайди', (t) async {
      final repo = await ready(t);
      repo.proResults.add(StateError('boom'));
      await t.tap(find.byKey(const ValueKey('pro-buy-pro_25')));
      await t.pump();
      final btn = t.widget<ElevatedButton>(find.byKey(const ValueKey('pro-buy-pro_25')));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('сервер АНИҚ рад этди (баланс етмайди) → кейинги уриниш янги калит', (t) async {
      final repo = await ready(t);
      repo.proResults.add(const RealtyException('insufficient_balance'));
      await t.tap(find.byKey(const ValueKey('pro-buy-pro_25')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('pro-buy-pro_25')));
      await t.pump();
      expect(repo.proKeys.length, 2);
      expect(repo.proKeys[1], isNot(repo.proKeys[0]));
    });

    testWidgets('муваффақият → кейинги харид янги калит; бошқа режа — бошқа калит', (t) async {
      final repo = await ready(t);
      await t.tap(find.byKey(const ValueKey('pro-buy-pro_25')));
      await t.pumpAndSettle();
      // Муваффақиятдан кейин квота қайта юкланади — натижасини берамиз.
      await t.tap(find.byKey(const ValueKey('pro-buy-pro_60')));
      await t.pumpAndSettle();
      expect(repo.proKeys.length, 2);
      expect(repo.proKeys[0], isNot(repo.proKeys[1]));
    });
  });

  group('showRealtyPackageSheet', () {
    Future<void> open(WidgetTester t, _FakeRepo repo) async {
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(onPressed: () => showRealtyPackageSheet(ctx, repository: repo), child: const Text('open')),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    Finder buy() => find.byType(ElevatedButton).last;

    testWidgets('REGRESSION: тармоқ узилди → қайта босиш ШУ калит билан (иккинчи марта ечилмайди)', (t) async {
      final repo = _FakeRepo()..pkgResults.add(TimeoutException('lost'));
      await open(t, repo);
      await t.tap(buy());
      await t.pumpAndSettle();
      await t.tap(buy());
      await t.pumpAndSettle();
      expect(repo.pkgKeys.length, 2);
      expect(repo.pkgKeys[1], repo.pkgKeys[0]);
    });

    testWidgets('REGRESSION: кутилмаган хатодан кейин тугма қотиб қолмайди', (t) async {
      final repo = _FakeRepo()..pkgResults.add(StateError('boom'));
      await open(t, repo);
      await t.tap(buy());
      await t.pumpAndSettle();
      expect(t.widget<ElevatedButton>(buy()).onPressed, isNotNull);
    });

    testWidgets('бошқа ўлчам — бошқа калит', (t) async {
      final repo = _FakeRepo()
        ..pkgResults.addAll([TimeoutException('a'), TimeoutException('b')]);
      await open(t, repo);
      await t.tap(buy());
      await t.pumpAndSettle();
      await t.tap(find.text('10'));
      await t.pump();
      await t.tap(buy());
      await t.pumpAndSettle();
      expect(repo.pkgKeys.length, 2);
      expect(repo.pkgKeys[0], isNot(repo.pkgKeys[1]));
    });

    testWidgets('нарх юкланмаса — «қайта юклаш» тугмаси, босилса қайта сўралади', (t) async {
      final repo = _FakeRepo()..pricing = const {};
      await open(t, repo);
      expect(find.byKey(const ValueKey('realty-pricing-retry')), findsOneWidget);
      repo.pricing = const {5: 30000, 10: 50000};
      await t.tap(find.byKey(const ValueKey('realty-pricing-retry')));
      await t.pumpAndSettle();
      expect(repo.pricingLoads, 2);
      expect(find.byKey(const ValueKey('realty-pricing-retry')), findsNothing);
    });
  });
}
