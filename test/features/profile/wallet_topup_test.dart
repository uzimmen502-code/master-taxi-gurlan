import 'package:ava_gurlan/core/utils/wallet_ledger_labels.dart';
import 'package:ava_gurlan/features/admin_web/utils/wallet_bot_card_state.dart';
import 'package:ava_gurlan/features/profile/models/wallet_topup_request.dart';
import 'package:ava_gurlan/features/profile/models/wallet_topup_status.dart';
import 'package:ava_gurlan/features/profile/widgets/wallet_topup_notice.dart';
import 'package:ava_gurlan/features/profile/widgets/wallet_topup_requests.dart';
import 'package:ava_gurlan/models/wallet_ledger_entry.dart';
import 'package:ava_gurlan/services/push_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 18, 12);

WalletTopUpRequest _req(
  String id,
  String status, {
  int amount = 50000,
  Duration age = const Duration(hours: 1),
  Duration? ttl,
  String reason = '',
}) {
  final created = _now.subtract(age);
  return WalletTopUpRequest(
    id: id,
    amount: amount,
    status: status,
    createdAt: created,
    expiresAt: ttl == null ? created.add(const Duration(hours: 24)) : created.add(ttl),
    rejectReason: reason,
  );
}

WalletLedgerEntry _entry(String type, {String module = '', Map<String, dynamic> meta = const {}, String refType = '', String refId = ''}) =>
    WalletLedgerEntry(
      id: 'e',
      type: type,
      amount: 1000,
      createdAt: _now,
      module: module,
      refType: refType,
      refId: refId,
      meta: meta,
    );

String _tr(String key, [Map<String, String>? params]) =>
    params == null ? '<$key>' : '<$key:${(params.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join(',')}>';

void main() {
  group('WalletTopUpRequest.effectiveStatus', () {
    test('чек кутилмоқда, лекин 24 соатлик муддат ўтди → «муддати тугади» (сервер ёпмайди)', () {
      expect(_req('a', 'awaiting_transfer', age: const Duration(hours: 30)).effectiveStatus(_now), 'expired');
    });

    test('муддат ичида — ўз ҳолатида', () {
      expect(_req('a', 'awaiting_transfer').effectiveStatus(_now), 'awaiting_transfer');
    });

    test('чек юборилган (текширувда) — муддатдан қатъи назар текширувда', () {
      expect(_req('a', 'awaiting_review', age: const Duration(days: 5)).effectiveStatus(_now), 'awaiting_review');
    });

    test('муддат ёзилмаган — ўзгармайди', () {
      const r = WalletTopUpRequest(id: 'a', amount: 1, status: 'awaiting_transfer');
      expect(r.effectiveStatus(_now), 'awaiting_transfer');
    });

    test('isOpen: фақат кутилаётганлар', () {
      expect(_req('a', 'awaiting_transfer').isOpen(_now), isTrue);
      expect(_req('a', 'awaiting_review').isOpen(_now), isTrue);
      expect(_req('a', 'credited').isOpen(_now), isFalse);
      expect(_req('a', 'rejected').isOpen(_now), isFalse);
      expect(_req('a', 'awaiting_transfer', age: const Duration(days: 2)).isOpen(_now), isFalse);
    });
  });

  group('visibleTopUpRequests', () {
    test('очиқлар ҳар доим; ёпиқлар — фақат 7 кун ичида; янгиси биринчи', () {
      final out = visibleTopUpRequests([
        _req('old_credited', 'credited', age: const Duration(days: 10)),
        _req('open_old', 'awaiting_review', age: const Duration(days: 9)),
        _req('new_credited', 'credited', age: const Duration(days: 1)),
        _req('mid_rejected', 'rejected', age: const Duration(days: 3)),
      ], _now);
      expect(out.map((r) => r.id), ['new_credited', 'mid_rejected', 'open_old']);
    });

    test('энг кўпи 5 та', () {
      final out = visibleTopUpRequests([
        for (var i = 0; i < 9; i++) _req('r$i', 'credited', age: Duration(hours: i + 1)),
      ], _now);
      expect(out.length, 5);
      expect(out.first.id, 'r0');
    });

    test('муддати ўтган «чек кутилмоқда» сўров ёпиқ ҳисобланади (7 кундан эски — кўринмайди)', () {
      final out = visibleTopUpRequests([_req('x', 'awaiting_transfer', age: const Duration(days: 9))], _now);
      expect(out, isEmpty);
    });

    test('бўш рўйхат', () => expect(visibleTopUpRequests(const [], _now), isEmpty));
  });

  group('WalletTopUpRequests виджети', () {
    Future<void> pump(WidgetTester t, List<WalletTopUpRequest> items) => t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WalletTopUpRequests(uid: '998901234567', stream: Stream.value(items), clock: () => _now),
            ),
          ),
        ));

    testWidgets('REGRESSION: «чек қабул қилинди — текширувда» иловада кўринади', (t) async {
      await pump(t, [_req('r1', 'awaiting_review')]);
      await t.pump();
      expect(find.byKey(const ValueKey('topup-status-awaiting_review')), findsOneWidget);
    });

    testWidgets('ҳар ҳолат ўз ёрлиғи билан; рад сабаби кўринади', (t) async {
      await pump(t, [
        _req('a', 'awaiting_transfer', age: const Duration(hours: 1)),
        _req('b', 'credited', age: const Duration(hours: 2)),
        _req('c', 'rejected', age: const Duration(hours: 3), reason: 'Чек ўқилмайди'),
        _req('d', 'awaiting_transfer', age: const Duration(hours: 30)),
      ]);
      await t.pump();
      expect(find.byKey(const ValueKey('topup-status-awaiting_transfer')), findsOneWidget);
      expect(find.byKey(const ValueKey('topup-status-credited')), findsOneWidget);
      expect(find.byKey(const ValueKey('topup-status-rejected')), findsOneWidget);
      expect(find.byKey(const ValueKey('topup-status-expired')), findsOneWidget);
      expect(find.text('Чек ўқилмайди'), findsOneWidget);
    });

    testWidgets('сўров йўқ — виджет жой эгалламайди', (t) async {
      await pump(t, const []);
      await t.pump();
      expect(find.byKey(const ValueKey('wallet-topup-requests')), findsNothing);
    });

    testWidgets('оқим хатоси (индекс/рухсат) — жим, экран синмайди', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WalletTopUpRequests(uid: '998901234567', stream: Stream.error(StateError('x')), clock: () => _now),
        ),
      ));
      await t.pump();
      expect(find.byKey(const ValueKey('wallet-topup-requests')), findsNothing);
    });
  });

  group('WalletTopUpStatus / WalletTopUpNotice', () {
    test('ready ёки card_invalid — блокланмайди; бот ўчиқ ва карта йўқ — блок', () {
      expect(const WalletTopUpStatus(ready: true, reason: 'ok').blockedKey, isNull);
      expect(const WalletTopUpStatus(ready: true, reason: 'card_invalid').blockedKey, isNull);
      expect(const WalletTopUpStatus(ready: false, reason: 'bot_disabled').blockedKey, 'wlt_tu_bot_off');
      expect(const WalletTopUpStatus(ready: false, reason: 'card_missing').blockedKey, 'wlt_tu_unavailable');
    });

    test('fromMap', () {
      final s = WalletTopUpStatus.fromMap({'ready': true, 'reason': 'ok', 'maxTopUp': 500000, 'dailyTopUpLimit': 1000000});
      expect([s.ready, s.reason, s.maxTopUp, s.dailyTopUpLimit], [true, 'ok', 500000, 1000000]);
    });

    Future<void> pump(WidgetTester t, WalletTopUpStatus? s) =>
        t.pumpWidget(MaterialApp(home: Scaffold(body: WalletTopUpNotice(status: s))));

    testWidgets('ҳолат номаълум (null) — ҳеч нарса', (t) async {
      await pump(t, null);
      expect(find.byKey(const ValueKey('wallet-topup-blocked')), findsNothing);
      expect(find.byKey(const ValueKey('wallet-topup-limits')), findsNothing);
    });

    testWidgets('REGRESSION: карта созланмаган — ботга боришдан ОЛДИН тушунтириш', (t) async {
      await pump(t, const WalletTopUpStatus(ready: false, reason: 'card_missing'));
      expect(find.byKey(const ValueKey('wallet-topup-blocked')), findsOneWidget);
    });

    testWidgets('тайёр — лимитлар кўрсатилади', (t) async {
      await pump(t, const WalletTopUpStatus(ready: true, reason: 'ok', maxTopUp: 500000, dailyTopUpLimit: 1000000));
      expect(find.byKey(const ValueKey('wallet-topup-limits')), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-topup-blocked')), findsNothing);
    });
  });

  group('тарих ёрлиқлари таржима орқали (қаттиқ матн йўқ)', () {
    test('модулли тўлов', () {
      expect(walletLedgerTitle(_entry('purchase_debit', module: 'bread'), _tr), '<wlt_l_purchase_mod:module=<wlt_m_bread>>');
    });

    test('модулсиз тўлов ва номаълум тур', () {
      expect(walletLedgerTitle(_entry('purchase_debit'), _tr), '<wlt_l_purchase>');
      expect(walletLedgerTitle(_entry(''), _tr), '<wlt_l_operation>');
      expect(walletLedgerTitle(_entry('weird_type'), _tr), 'weird_type');
    });

    test('REGRESSION: қайтим кирилл+лотин аралашмаган — калит орқали', () {
      expect(walletLedgerTitle(_entry('change_accrued'), _tr), '<wlt_l_change>');
      expect(walletLedgerTitle(_entry('settlement_credit', module: 'taxi'), _tr), '<wlt_l_change_mod:module=<wlt_m_taxi>>');
      expect(walletLedgerTitle(_entry('settlement_debit'), _tr), '<wlt_l_change_given>');
    });

    test('номаълум модул — ўз номи билан', () {
      expect(walletLedgerTitle(_entry('purchase_debit', module: 'garden'), _tr), '<wlt_l_purchase_mod:module=garden>');
    });

    test('ҳамма тур калитга боғланган', () {
      for (final t in [
        'cash_to_wallet', 'wallet_to_cash', 'float_to_wallet_migration', 'wallet_p2p_credit', 'wallet_p2p_debit',
        'payout_request', 'payout_paid', 'admin_adjust', 'birthday_bonus',
      ]) {
        expect(walletLedgerTitle(_entry(t), _tr), startsWith('<wlt_l_'), reason: t);
      }
    });

    test('изоҳ: буюртма, нақд, рақам', () {
      final s = walletLedgerSubtitle(
        _entry('purchase_debit', meta: {'note': 'ok', 'orderTotal': 20000, 'cashPaid': 5000}, refType: 'order', refId: 'ABCDEFGHIJKL'),
        _tr,
      );
      expect(s, contains('wlt_l_order'));
      expect(s, contains('wlt_l_cash'));
      expect(s, contains('ok'));
      expect(s, contains('№ ABCDEFGH'));
    });
  });

  group('админ: депозит картаси ҳолати', () {
    test('Луна', () {
      expect(walletCardIsValid('4111111111111111'), isTrue);
      expect(walletCardIsValid('4111 1111 1111 1111'), isTrue);
      expect(walletCardIsValid('4111111111111112'), isFalse);
      expect(walletCardIsValid('411111111111'), isFalse);
      expect(walletCardIsValid(''), isFalse);
    });

    test('ҳолатлар', () {
      expect(evaluateWalletBotCard(enabled: true, card: '4111111111111111'), WalletBotCardState.ok);
      expect(evaluateWalletBotCard(enabled: true, card: ''), WalletBotCardState.missing);
      expect(evaluateWalletBotCard(enabled: true, card: '   '), WalletBotCardState.missing);
      expect(evaluateWalletBotCard(enabled: true, card: '8600000000000001'), WalletBotCardState.invalid);
      expect(evaluateWalletBotCard(enabled: false, card: ''), WalletBotCardState.botOff);
    });
  });

  group('push: screen=wallet', () {
    test('REGRESSION: ҳамён push\'и ҳамён экранини очади; бошқалар — йўқ', () {
      expect(PushNavigation.opensWallet('wallet'), isTrue);
      expect(PushNavigation.opensWallet('news'), isFalse, reason: 'молия навбати хабари ҳамённи очмайди');
      expect(PushNavigation.opensWallet(''), isFalse);
      expect(PushNavigation.opensWallet('realty_my'), isFalse);
    });
  });
}
