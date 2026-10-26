import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/my_shop/screens/my_shop_screen.dart';
import 'package:ava_gurlan/features/my_shop/seller_tg_channel.dart';
import 'package:ava_gurlan/features/my_shop/widgets/seller_tg_channel_card.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Менинг Telegram каналим» (2026-10-25). Локализация делегати уланмаган — `context.tr` калитнинг ўзини қайтаради.

FirebaseFunctionsException _err(String code) =>
    FirebaseFunctionsException(message: code, code: 'failed-precondition', details: {'code': code});

class _FakeApi implements SellerTgChannelApi {
  _FakeApi(this.state);

  SellerTgChannelState state;
  Object? statusError;
  Object? prepareError;
  Object? connectError;
  SellerTgChannel? prepareResult;
  final prepared = <String>[];
  var connects = 0;
  var disconnects = 0;

  @override
  Future<SellerTgChannelState> status() async {
    if (statusError != null) throw statusError!;
    return state;
  }

  @override
  Future<SellerTgChannel> prepare(String username) async {
    prepared.add(username);
    if (prepareError != null) throw prepareError!;
    return prepareResult ??
        SellerTgChannel(
          status: 'pending',
          username: 'non_shop',
          code: 'AVA-ABC234',
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        );
  }

  @override
  Future<SellerTgChannel> connect() async {
    connects++;
    if (connectError != null) throw connectError!;
    return const SellerTgChannel(status: 'connected', username: 'non_shop', title: 'Нон дўкони');
  }

  @override
  Future<void> disconnect() async => disconnects++;
}

SellerTgChannelState _st(SellerTgChannel c, {bool available = true}) =>
    SellerTgChannelState(available: available, botUsername: available ? 'ava_test_bot' : '', channel: c);

Future<void> _pump(WidgetTester tester, _FakeApi api) async {
  tester.view.physicalSize = const Size(420 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: SellerTgChannelCard(api: api))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('SellerTgChannel.fromMap', () {
    test('pending: kod va muddat; noma\'lum — none', () {
      final c = SellerTgChannel.fromMap({
        'status': 'pending', 'username': 'non_shop', 'code': 'AVA-ABC234', 'expiresAtMs': 1761400000000,
      });
      expect([c.isPending, c.handle, c.code], [true, '@non_shop', 'AVA-ABC234']);
      expect(c.expiresAt, DateTime.fromMillisecondsSinceEpoch(1761400000000));
      expect(SellerTgChannel.fromMap(null).status, 'none');
      expect(SellerTgChannel.fromMap('x').isConnected, false);
    });
    test('xato kodi → tushunarli matn kaliti; noma\'lum/stack — umumiy', () {
      expect(sellerTgErrorKey(_err('BOT_NOT_ADMIN')), 'seller_tg_err_BOT_NOT_ADMIN');
      expect(sellerTgErrorKey(_err('CODE_NOT_FOUND')), 'seller_tg_err_CODE_NOT_FOUND');
      expect(sellerTgErrorKey(_err('TG_BOT_UNAVAILABLE')), 'seller_tg_unavailable');
      expect(sellerTgErrorKey(_err('CONNECT_STATE_CHANGED')), 'seller_tg_err_generic');
      expect(sellerTgErrorKey(Exception('socket')), 'seller_tg_err_generic');
    });
  });

  group('SellerTgChannelCard', () {
    testWidgets('ulanmagan: «Ulash» → bot nomi (serverdan), kanal nomi → kod → tekshirish → ulandi', (tester) async {
      final api = _FakeApi(_st(SellerTgChannel.none));
      await _pump(tester, api);
      expect(find.text('seller_tg_sub_none'), findsOneWidget);
      expect(find.byKey(const ValueKey('seller_tg_username')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('seller_tg_start')));
      await tester.pumpAndSettle();
      expect(find.text('@ava_test_bot'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('seller_tg_username')), '@non_shop');
      await tester.tap(find.byKey(const ValueKey('seller_tg_get_code')));
      await tester.pumpAndSettle();
      expect(api.prepared, ['@non_shop']);
      expect(find.text('AVA-ABC234'), findsOneWidget);
      expect(find.text('seller_tg_step3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('seller_tg_verify')));
      await tester.pumpAndSettle();
      expect(api.connects, 1);
      expect(find.text('seller_tg_connected'), findsOneWidget);
      expect(find.byKey(const ValueKey('seller_tg_disconnect')), findsOneWidget);
      expect(find.byKey(const ValueKey('seller_tg_code')), findsNothing);
    });

    testWidgets('server xatosi — tushunarli matn (diagnostika kodi/stack ko\'rinmaydi), qadamlar qoladi', (tester) async {
      final api = _FakeApi(_st(SellerTgChannel.none))..prepareError = _err('BOT_NOT_ADMIN');
      await _pump(tester, api);
      await tester.tap(find.byKey(const ValueKey('seller_tg_start')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('seller_tg_username')), '@non_shop');
      await tester.tap(find.byKey(const ValueKey('seller_tg_get_code')));
      await tester.pumpAndSettle();
      expect(find.text('seller_tg_err_BOT_NOT_ADMIN'), findsOneWidget);
      expect(find.textContaining('failed-precondition'), findsNothing);
      expect(find.byKey(const ValueKey('seller_tg_username')), findsOneWidget);
    });

    testWidgets('kod tavsifda yo\'q — CODE_NOT_FOUND matni, kod va «Tekshirish» qoladi', (tester) async {
      final api = _FakeApi(_st(SellerTgChannel(
        status: 'pending', username: 'non_shop', code: 'AVA-ABC234',
        expiresAt: DateTime.now().add(const Duration(minutes: 20)),
      )))..connectError = _err('CODE_NOT_FOUND');
      await _pump(tester, api);
      // Kod bor — qadamlar o'zi ochiq, kanal nomi oldindan to'ldirilgan.
      expect(find.text('AVA-ABC234'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('seller_tg_username'))).controller!.text, '@non_shop');
      await tester.tap(find.byKey(const ValueKey('seller_tg_verify')));
      await tester.pumpAndSettle();
      expect(find.text('seller_tg_err_CODE_NOT_FOUND'), findsOneWidget);
      expect(find.byKey(const ValueKey('seller_tg_verify')), findsOneWidget);
    });

    testWidgets('needs_reconnect: ogohlantirish; «Qayta tekshirish» o\'sha kanal bilan → ulangan', (tester) async {
      final api = _FakeApi(_st(const SellerTgChannel(status: 'needs_reconnect', username: 'non_shop')))
        ..prepareResult = const SellerTgChannel(status: 'connected', username: 'non_shop');
      await _pump(tester, api);
      expect(find.byKey(const ValueKey('seller_tg_needs_reconnect')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('seller_tg_recheck')));
      await tester.pumpAndSettle();
      expect(api.prepared, ['@non_shop']);
      expect(find.byKey(const ValueKey('seller_tg_needs_reconnect')), findsNothing);
      expect(find.text('seller_tg_connected_hint'), findsOneWidget);
    });

    testWidgets('uzish: tasdiqlasa — chaqiriladi va «Ulash» qaytadi; bekor qilsa — yo\'q', (tester) async {
      final api = _FakeApi(_st(const SellerTgChannel(status: 'connected', username: 'non_shop')));
      await _pump(tester, api);
      await tester.tap(find.byKey(const ValueKey('seller_tg_disconnect')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(api.disconnects, 0);
      await tester.tap(find.byKey(const ValueKey('seller_tg_disconnect')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('seller_tg_disconnect_yes')));
      await tester.pumpAndSettle();
      expect(api.disconnects, 1);
      expect(find.byKey(const ValueKey('seller_tg_start')), findsOneWidget);
    });

    testWidgets('bot sozlanmagan — «xizmat ishlamayapti», qadamlar yo\'q', (tester) async {
      await _pump(tester, _FakeApi(_st(SellerTgChannel.none, available: false)));
      expect(find.byKey(const ValueKey('seller_tg_unavailable')), findsOneWidget);
      expect(find.byKey(const ValueKey('seller_tg_start')), findsNothing);
    });

    testWidgets('yuklash xatosi — matn va «Qayta urinish»; qayta urinsa yuklanadi', (tester) async {
      final api = _FakeApi(_st(SellerTgChannel.none))..statusError = Exception('offline');
      await _pump(tester, api);
      expect(find.byKey(const ValueKey('seller_tg_load_err')), findsOneWidget);
      api.statusError = null;
      await tester.tap(find.byKey(const ValueKey('seller_tg_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('seller_tg_start')), findsOneWidget);
    });
  });

  testWidgets('«Менинг дўконим» ekranida karta ko\'rinadi', (tester) async {
    tester.view.physicalSize = const Size(420 * 2, 1600 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: MyShopScreen(
        phone: '998901234567',
        businesses: Stream.value(const []),
        loadMainName: () async => 'Нон',
        tgChannelApi: _FakeApi(_st(const SellerTgChannel(status: 'connected', username: 'non_shop'))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seller_tg_card')), findsOneWidget);
    expect(find.text('seller_tg_connected'), findsOneWidget);
  });

  test('uch til: yangi kalitlar uz_Cyrl / uz_Latn / ru da bor, o\'rinbosarlar saqlangan', () {
    Map<String, dynamic> load(String lang) =>
        jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
    final langs = {for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) l: load(l)};
    final keys = [
      'tv_social_seller_telegram', 'tv_social_consent_check_own',
      for (final k in langs['uz_Cyrl']!.keys) if (k.startsWith('seller_tg_')) k,
    ];
    expect(keys.length, greaterThan(30));
    for (final code in sellerTgKnownErrors) {
      expect(keys, contains('seller_tg_err_$code'));
    }
    for (final k in keys) {
      final placeholders = RegExp(r'\{[a-z]+\}').allMatches('${langs['uz_Cyrl']![k]}').map((m) => m[0]).toSet();
      for (final l in langs.entries) {
        final v = l.value[k];
        expect(v is String && v.trim().isNotEmpty, true, reason: '${l.key}: $k');
        for (final p in placeholders) {
          expect((v as String).contains(p!), true, reason: '${l.key}: $k $p');
        }
      }
    }
  });
}
