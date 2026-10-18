import 'package:ava_gurlan/features/profile/widgets/wallet_amount_sheet.dart';
import 'package:ava_gurlan/shared/widgets/wallet_topup_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Қанча тўлдирасиз?» — ботни очишдан олдин сумма танлаш.
void main() {
  group('walletAmountOptions', () {
    test('таклиф минг сўмгача ЮҚОРИГА яхлитланади ва биринчи туради; ундан катта тайёр суммалар', () {
      expect(walletAmountOptions(suggested: 149733), [150000, 200000, 300000, 500000]);
    });

    test('таклиф тайёр сумма билан бир хил — такрорланмайди', () {
      expect(walletAmountOptions(suggested: 200000), [200000, 300000, 500000]);
    });

    test('таклиф йўқ — барча тайёр суммалар', () {
      expect(walletAmountOptions(), [50000, 100000, 200000, 300000, 500000]);
    });

    test('max чегараси: ундан каттаси чиқмайди (таклиф ҳам)', () {
      expect(walletAmountOptions(suggested: 150000, max: 250000), [150000, 200000]);
      expect(walletAmountOptions(suggested: 400000, max: 250000), [50000, 100000, 200000]);
    });

    test('max = 0 (номаълум) — чегара қўйилмайди', () {
      expect(walletAmountOptions(suggested: 700000), [700000]);
    });

    test('нолга тенг/манфий таклиф — эътиборсиз', () {
      expect(walletAmountOptions(suggested: 0), walletAmountOptions());
      expect(walletAmountOptions(suggested: -5), walletAmountOptions());
    });
  });

  group('parseWalletAmount', () {
    test('бутун сон, 1..max', () {
      expect(parseWalletAmount('150000'), 150000);
      expect(parseWalletAmount('150 000'), 150000);
      expect(parseWalletAmount('500000', max: 500000), 500000);
    });

    test('чегарадан ошса, нол/манфий/ҳарф/бўш — null', () {
      expect(parseWalletAmount('500001', max: 500000), isNull);
      expect(parseWalletAmount('0'), isNull);
      expect(parseWalletAmount('-5'), isNull);
      expect(parseWalletAmount('12a'), isNull);
      expect(parseWalletAmount(''), isNull);
      expect(parseWalletAmount('1234567890'), isNull);
    });
  });

  test('бот ҳаволаси: сервер ўқийдиган deposit_<сумма> шакли', () {
    expect(walletBotDepositUrl('AvaZonaWalletBot', 150000),
        'https://t.me/AvaZonaWalletBot?start=deposit_150000');
  });

  group('WalletAmountSheet', () {
    Future<int?> open(WidgetTester t, {int? suggested, int max = 0}) async {
      int? result = -1;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  result = await showWalletAmountSheet(context, suggested: suggested, max: max),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('таклиф бор — олдиндан танланган: бир босишда давом этилади', (t) async {
      int? out = -1;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => out = await showWalletAmountSheet(context, suggested: 150000),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wallet-amount-continue')));
      await t.pumpAndSettle();
      expect(out, 150000);
    });

    testWidgets('REGRESSION: фойдаланувчи КЎПРОҚ тайёр сумма танлай олади', (t) async {
      int? out = -1;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => out = await showWalletAmountSheet(context, suggested: 150000),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wallet-amount-300000')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('wallet-amount-continue')));
      await t.pumpAndSettle();
      expect(out, 300000);
    });

    testWidgets('REGRESSION: ўз суммасини ёзади (тугмадан устун)', (t) async {
      int? out = -1;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => out = await showWalletAmountSheet(context, suggested: 150000, max: 500000),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('wallet-amount-custom')), '420000');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('wallet-amount-continue')));
      await t.pumpAndSettle();
      expect(out, 420000);
    });

    testWidgets('max\'дан катта ёзилса — давом этиш ўчиқ', (t) async {
      await open(t, suggested: 150000, max: 500000);
      await t.enterText(find.byKey(const ValueKey('wallet-amount-custom')), '900000');
      await t.pump();
      final btn = t.widget<FilledButton>(find.byKey(const ValueKey('wallet-amount-continue')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('таклифсиз — ҳеч нарса танланмагунча давом этиш ўчиқ', (t) async {
      await open(t);
      final btn = t.widget<FilledButton>(find.byKey(const ValueKey('wallet-amount-continue')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('ёпилса (свайп/орқага) — null: бот очилмайди', (t) async {
      int? out = -1;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => out = await showWalletAmountSheet(context, suggested: 150000),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10)); // варақ ташқарисига
      await t.pumpAndSettle();
      expect(out, isNull);
    });
  });

  group('WalletBalanceBar.onTopUpAmount', () {
    testWidgets('етишмаётган сумма узатилади (нарх − баланс)', (t) async {
      int? got;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WalletBalanceBar(
            balance: 50000,
            price: 200000,
            onTopUp: () {},
            onTopUpAmount: (a) => got = a,
          ),
        ),
      ));
      await t.tap(find.byKey(const ValueKey('wallet-balance-topup')));
      expect(got, 150000);
    });
  });
}
