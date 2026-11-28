// Компьютерда QR орқали кириш (эга 2026-11-28) — соф ёрдамчилар + виджет тестлари (Firebase'сиз).
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/qr_login/data/qr_login_api.dart';
import 'package:ava_gurlan/features/qr_login/qr_login_codes.dart';
import 'package:ava_gurlan/features/qr_login/screens/qr_login_confirm_screen.dart';
import 'package:ava_gurlan/features/qr_login/screens/qr_web_login_screen.dart';
import 'package:ava_gurlan/features/qr_login/screens/web_sessions_screen.dart';
import 'package:ava_gurlan/features/qr_login/widgets/qr_web_login_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../restaurants/restaurants_l10n_harness.dart';
import 'fake_qr_api.dart';

void main() {
  final d = JsonL10nDelegate();
  String t(String k) => d.tr(k);

  group('соф', () {
    test('QR матни: AVAQR1:<32 hex>, бошқаси рад', () {
      final sid = 'a' * 32;
      expect(parseQrLoginPayload('AVAQR1:$sid'), sid);
      expect(parseQrLoginPayload('AVAQR1:${'A' * 32}'), sid);
      expect(parseQrLoginPayload(' AVAQR1:$sid '), sid);
      expect(parseQrLoginPayload('AVAQR1:${'a' * 31}'), '');
      expect(parseQrLoginPayload('AVAQR1:${'g' * 32}'), '');
      expect(parseQrLoginPayload('https://evil.example/$sid'), '');
      expect(parseQrLoginPayload(null), '');
    });

    test('сервер коди → l10n калити (номаълум → умумий)', () {
      expect(qrLoginErrorKey('QR_SESSION_OTHER_USER'), 'qrl_err_other_user');
      expect(qrLoginErrorKey('QR_SESSION_NOT_PENDING'), 'qrl_err_used');
      expect(qrLoginErrorKey('DEVICE_NOT_BOUND'), 'qrl_not_main_phone');
      expect(qrLoginErrorKey('QR_LOGIN_DISABLED'), 'qrl_disabled');
      expect(qrLoginErrorKey('internal'), 'qrl_err_generic');
      expect(qrLoginErrorKey(null), 'qrl_err_generic');
    });

    test('watch ҳолати', () {
      expect(qrWatchStateOf('approved'), QrWatchState.approved);
      expect(qrWatchStateOf('cancelled'), QrWatchState.expired);
      expect(qrWatchStateOf('bogus'), QrWatchState.unknown);
    });

    test('qrl_* калитлари 3 тилда бир хил ва экранларда ишлатилганлари бор', () {
      Map<String, dynamic> load(String l) =>
          jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;
      final langs = {for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) l: load(l)};
      Set<String> qrl(Map<String, dynamic> m) => m.keys.where((k) => k.startsWith('qrl_')).toSet();
      final base = qrl(langs['uz_Cyrl']!);
      expect(base.length, greaterThanOrEqualTo(40));
      expect(qrl(langs['uz_Latn']!), base);
      expect(qrl(langs['ru']!), base);
      final used = <String>{};
      for (final f in Directory('lib/features/qr_login').listSync(recursive: true).whereType<File>()) {
        used.addAll(RegExp(r"(?<!ValueKey\()'(qrl_[a-z_]+)'").allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
      }
      used.addAll(['qrl_sessions_title', 'qrl_sessions_sub']); // profile_screen.dart
      for (final k in used) {
        for (final l in langs.keys) {
          expect((langs[l]![k] ?? '').toString(), isNotEmpty, reason: '$l.$k');
        }
      }
    });
  });

  group('телефон: тасдиқлаш экрани', () {
    Future<FakeQrApi> open(WidgetTester tester, {FakeQrApi? api}) async {
      final a = api ?? FakeQrApi();
      await tester.pumpWidget(l10nApp(
        delegate: d,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await Navigator.of(ctx).push<bool>(
                    MaterialPageRoute(builder: (_) => QrLoginConfirmScreen(sid: 'a' * 32, api: a)),
                  );
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('result:$r')));
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return a;
    }

    testWidgets('сарлавҳа, браузер, жой, огоҳлантириш ва {hours} соат ёпиқ', (tester) async {
      await open(tester);
      expect(find.text(t('qrl_confirm_title')), findsOneWidget);
      expect(find.text('Chrome · Windows'), findsOneWidget);
      expect(find.text('Urgench'), findsOneWidget);
      expect(find.text(t('qrl_confirm_warning')), findsOneWidget);
      expect(find.text(t('qrl_confirm_outflow').replaceAll('{hours}', '24')), findsOneWidget);
    });

    testWidgets('«Тасдиқлайман» → decide(true), экран true билан ёпилади', (tester) async {
      final api = await open(tester);
      await tester.tap(find.byKey(const ValueKey('qrl_confirm_yes')));
      await tester.pumpAndSettle();
      expect(api.decisions, [true]);
      expect(find.text('result:true'), findsOneWidget);
    });

    testWidgets('«Бекор қилиш» → decide(false), false', (tester) async {
      final api = await open(tester);
      await tester.tap(find.byKey(const ValueKey('qrl_confirm_no')));
      await tester.pumpAndSettle();
      expect(api.decisions, [false]);
      expect(find.text('result:false'), findsOneWidget);
    });

    testWidgets('бошқа телефон сканерлаган — хато матни, тасдиқ тугмаси йўқ', (tester) async {
      final api = FakeQrApi()..peekError = const QrLoginException('QR_SESSION_OTHER_USER');
      await open(tester, api: api);
      expect(find.text(t('qrl_err_other_user')), findsOneWidget);
      expect(find.byKey(const ValueKey('qrl_confirm_yes')), findsNothing);
      expect(api.decisions, isEmpty);
    });

    testWidgets('тасдиқ рад этилса (масалан бир вақтда иккинчи) — хато кўрсатилади, экран очиқ', (tester) async {
      final api = FakeQrApi()..decideError = const QrLoginException('QR_SESSION_NOT_PENDING');
      await open(tester, api: api);
      await tester.tap(find.byKey(const ValueKey('qrl_confirm_yes')));
      await tester.pumpAndSettle();
      expect(find.text(t('qrl_err_used')), findsOneWidget);
      expect(find.text('result:true'), findsNothing);
    });
  });

  group('телефон: «Компьютерда кириш»', () {
    testWidgets('рўйхат, «Чиқиш» → тасдиқ → revoke(w1)', (tester) async {
      final api = FakeQrApi();
      await tester.pumpWidget(l10nApp(delegate: d, home: WebSessionsScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('qrl_scan_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('qrl_session_w1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qrl_logout_w1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qrl_logout_yes')));
      await tester.pumpAndSettle();
      expect(api.revokedIds, ['w1']);
      expect(find.text(t('qrl_logout_done')), findsOneWidget);
    });

    testWidgets('сканер → тасдиқлаш экрани → тасдиқ → «тасдиқланди»', (tester) async {
      final api = FakeQrApi();
      await tester.pumpWidget(l10nApp(
        delegate: d,
        home: WebSessionsScreen(api: api, scan: (_) async => 'b' * 32),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qrl_scan_btn')));
      await tester.pumpAndSettle();
      expect(find.text(t('qrl_confirm_title')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qrl_confirm_yes')));
      await tester.pump();
      await tester.pump();
      expect(api.decisions, [true]);
      expect(find.text(t('qrl_confirm_done')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // рўйхатни кечиктириб янгилаш
      expect(api.listCalls, 2);
    });

    testWidgets('босқич OFF — «ёпиқ» матни, сканер йўқ; фаол сессиядан чиқиш барибир мумкин', (tester) async {
      final api = FakeQrApi()
        ..list = const QrWebSessionsList(enabled: false, canManage: true, items: [
          QrWebSessionItem(webSessionId: 'w9', browserLabel: 'Edge · Windows'),
        ]);
      await tester.pumpWidget(l10nApp(delegate: d, home: WebSessionsScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('qrl_disabled_text')), findsOneWidget);
      expect(find.byKey(const ValueKey('qrl_scan_btn')), findsNothing);
      expect(find.byKey(const ValueKey('qrl_logout_w9')), findsOneWidget);
    });

    testWidgets('асосий телефон эмас (canManage=false) — сканер ва «Чиқиш» йўқ', (tester) async {
      final api = FakeQrApi()
        ..list = const QrWebSessionsList(enabled: true, canManage: false, items: [
          QrWebSessionItem(webSessionId: 'w2'),
        ]);
      await tester.pumpWidget(l10nApp(delegate: d, home: WebSessionsScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.text(t('qrl_not_main_phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('qrl_scan_btn')), findsNothing);
      expect(find.byKey(const ValueKey('qrl_logout_w2')), findsNothing);
    });
  });

  group('веб: QR экрани', () {
    testWidgets('QR кўринади → scanned → approved → consume(sid, secret) → onSignedIn', (tester) async {
      final api = FakeQrApi();
      QrConsumeResult? signed;
      await tester.pumpWidget(l10nApp(
        delegate: d,
        home: QrWebLoginScreen(api: api, onSignedIn: (_, r) async => signed = r),
      ));
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text(t('qrl_web_step2')), findsOneWidget);
      api.watchCtrl.add('scanned');
      await tester.pump();
      expect(find.text(t('qrl_web_scanned')), findsOneWidget);
      api.watchCtrl.add('approved');
      await tester.pump();
      await tester.pump();
      expect(api.consumed, ['${'sid1'.padRight(32, '0')}|secret1']);
      expect(signed?.customToken, 't');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('телефонда рад этилди — матн ва «Янги QR код», consume йўқ', (tester) async {
      final api = FakeQrApi();
      await tester.pumpWidget(l10nApp(delegate: d, home: QrWebLoginScreen(api: api, onSignedIn: (_, __) async {})));
      await tester.pump();
      api.watchCtrl.add('rejected');
      await tester.pump();
      expect(find.text(t('qrl_web_rejected')), findsOneWidget);
      expect(api.consumed, isEmpty);
      await tester.tap(find.byKey(const ValueKey('qrl_refresh')));
      await tester.pump();
      expect(api.starts, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('муддат: ўзи янгиланади ($kQrAutoRefreshMax марта), кейин тугма', (tester) async {
      final api = FakeQrApi();
      await tester.pumpWidget(l10nApp(delegate: d, home: QrWebLoginScreen(api: api, onSignedIn: (_, __) async {})));
      await tester.pump();
      for (var i = 0; i < kQrAutoRefreshMax; i++) {
        api.watchCtrl.add('expired');
        await tester.pump();
        await tester.pump();
      }
      expect(api.starts, kQrAutoRefreshMax + 1);
      api.watchCtrl.add('expired');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('qrl_refresh')), findsOneWidget);
      expect(find.text(t('qrl_web_expired')), findsOneWidget);
      expect(api.starts, kQrAutoRefreshMax + 1, reason: 'чексиз янгиланмайди');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('consume рад (replay/эскирган) — хато ва қайта QR тугмаси', (tester) async {
      final api = FakeQrApi()..consumeError = const QrLoginException('QR_SESSION_NOT_PENDING');
      var signedIn = false;
      await tester.pumpWidget(l10nApp(delegate: d, home: QrWebLoginScreen(api: api, onSignedIn: (_, __) async => signedIn = true)));
      await tester.pump();
      api.watchCtrl.add('approved');
      await tester.pump();
      await tester.pump();
      expect(signedIn, isFalse);
      expect(find.text(t('qrl_err_used')), findsOneWidget);
      expect(find.byKey(const ValueKey('qrl_refresh')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('сервер OFF — «ёпиқ» матни', (tester) async {
      final api = FakeQrApi()..startError = const QrLoginException('QR_LOGIN_DISABLED');
      await tester.pumpWidget(l10nApp(delegate: d, home: QrWebLoginScreen(api: api, onSignedIn: (_, __) async {})));
      await tester.pump();
      await tester.pump();
      expect(find.text(t('qrl_disabled')), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });
  });

  group('веб: кириш тугмаси', () {
    setUp(QrWebLoginEntry.resetProbeCache);

    testWidgets('веб + босқич ёқиқ — тугма, босилса QR экрани', (tester) async {
      final api = FakeQrApi();
      await tester.pumpWidget(l10nApp(delegate: d, home: Scaffold(body: QrWebLoginEntry(api: api, forceWeb: true))));
      await tester.pump();
      expect(find.byKey(const ValueKey('qrl_web_entry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qrl_web_entry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(t('qrl_web_title')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('босқич OFF — ҳеч нарса', (tester) async {
      final api = FakeQrApi()..probe = false;
      await tester.pumpWidget(l10nApp(delegate: d, home: Scaffold(body: QrWebLoginEntry(api: api, forceWeb: true))));
      await tester.pump();
      expect(find.byKey(const ValueKey('qrl_web_entry')), findsNothing);
    });

    testWidgets('телефон иловасида (веб эмас) — ҳеч нарса, probe чақирилмайди', (tester) async {
      final api = FakeQrApi();
      await tester.pumpWidget(l10nApp(delegate: d, home: Scaffold(body: QrWebLoginEntry(api: api))));
      await tester.pump();
      expect(find.byKey(const ValueKey('qrl_web_entry')), findsNothing);
    });
  });
}
