import 'package:ava_gurlan/features/assistant/models/assistant_status.dart';
import 'package:ava_gurlan/features/assistant/services/assistant_service.dart';
import 'package:ava_gurlan/features/assistant/widgets/assistant_pro_sheet.dart';
import 'package:ava_gurlan/features/local_taxi/passenger/widgets/local_taxi_wallet_panel.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_ad_tier_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Ҳамённи тўлдириш» йўли модулларда (2026-10-18): баланс етмаса фойдаланувчи
/// ҳар қаерда босадиган тугма кўради. Сервер мантиғи ўзгармаган.

class _FakeAssistant implements AssistantService {
  _FakeAssistant(this.error);
  final Object error;
  int calls = 0;

  @override
  Future<AssistantPurchaseResult> buyPackage(String packageId) async {
    calls++;
    throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

AssistantStatus _status({int balance = 1000}) => AssistantStatus(
      enabled: true,
      pro: false,
      paidUntil: null,
      usedToday: 0,
      dailyLimit: 10,
      freeDailyLimit: 5,
      webSearchesToday: 0,
      webSearchLimit: 0,
      balance: balance,
      packages: const [AssistantPackage(id: 'p7', days: 7, price: 30000, promo: false)],
    );

void main() {
  group('TvAdTierPicker — реклама', () {
    Future<int> pump(WidgetTester t, {required int balance, bool withTopUp = true}) async {
      var topUps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TvAdTierPicker(
              selectedTier: 'premium',
              selectedDays: 30,
              pricing: const {
                'premium': {30: 90000},
              },
              walletBalance: balance,
              onTierChanged: (_) {},
              onDaysChanged: (_) {},
              onTopUp: withTopUp ? () => topUps++ : null,
            ),
          ),
        ),
      ));
      final btn = find.byKey(const ValueKey('tv-ad-topup'));
      if (btn.evaluate().isNotEmpty) {
        // Тариф рўйхати баланд — тугма экрандан пастда бўлиши мумкин.
        await t.ensureVisible(btn);
        await t.pump();
        await t.tap(btn);
      }
      return topUps;
    }

    testWidgets('REGRESSION: баланс етмаса — «Ҳамённи тўлдириш» тугмаси босилади', (t) async {
      final topUps = await pump(t, balance: 100);
      expect(topUps, 1);
    });

    testWidgets('баланс етарли — тугма йўқ', (t) async {
      await pump(t, balance: 10000000);
      expect(find.byKey(const ValueKey('tv-ad-topup')), findsNothing);
    });

    testWidgets('onTopUp берилмаган — тугма йўқ (эски чақирувлар синмайди)', (t) async {
      await pump(t, balance: 100, withTopUp: false);
      expect(find.byKey(const ValueKey('tv-ad-topup')), findsNothing);
    });
  });

  group('LocalTaxiWalletPanel — маҳаллий такси', () {
    Future<void> pump(WidgetTester t, {required int balance, required int fare}) {
      return t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocalTaxiWalletPanel(
              tripId: '',
              walletBalance: balance,
              fareEstimate: fare,
              initialIntent: 0,
              enabled: true,
            ),
          ),
        ),
      ));
    }

    testWidgets('REGRESSION: ҳамён 0 — «Ҳамённи тўлдириш» тугмаси бор', (t) async {
      await pump(t, balance: 0, fare: 20000);
      expect(find.byKey(const ValueKey('local-taxi-wallet-topup')), findsOneWidget);
    });

    testWidgets('ҳамён қисман етади — тугма бор', (t) async {
      await pump(t, balance: 5000, fare: 20000);
      expect(find.byKey(const ValueKey('local-taxi-wallet-topup')), findsOneWidget);
    });

    testWidgets('ҳамён тўлиқ етади — тугма йўқ', (t) async {
      await pump(t, balance: 50000, fare: 20000);
      expect(find.byKey(const ValueKey('local-taxi-wallet-topup')), findsNothing);
    });
  });

  group('AssistantProSheet — AI пакет варағи', () {
    Future<_FakeAssistant> open(WidgetTester t, {required Object error, int balance = 100000}) async {
      final svc = _FakeAssistant(error);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssistantProSheet(
              status: _status(balance: balance),
              service: svc,
              onTopUp: () {},
            ),
          ),
        ),
      ));
      return svc;
    }

    Future<void> buyFirst(WidgetTester t) async {
      // Пакет плиткаси — нарх матни билан.
      await t.tap(find.textContaining('30'));
      await t.pumpAndSettle();
      await t.tap(find.byType(FilledButton).last);
      await t.pumpAndSettle();
    }

    testWidgets('REGRESSION: сервер «баланс етмайди» деса — хато ВАРАҚ ИЧИДА + тўлдириш тугмаси', (t) async {
      await open(t, error: const AssistantException('insufficient_balance', details: {'balance': 500}));
      await buyFirst(t);
      expect(find.byKey(const ValueKey('wallet-inline-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-inline-error-topup')), findsOneWidget);
    });

    testWidgets('локал баланс етмаса — сервер чақирилмайди, хато варақ ичида', (t) async {
      final svc = await open(t, error: const AssistantException('x'), balance: 10);
      await t.tap(find.textContaining('30'));
      await t.pumpAndSettle();
      expect(svc.calls, 0);
      expect(find.byKey(const ValueKey('wallet-inline-error-topup')), findsOneWidget);
    });

    testWidgets('бошқа хато — варақ ичида, лекин тўлдириш тугмасисиз', (t) async {
      await open(t, error: const AssistantException('boom'));
      await buyFirst(t);
      expect(find.byKey(const ValueKey('wallet-inline-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-inline-error-topup')), findsNothing);
    });
  });
}
