import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/profile/data/account_deletion_repository.dart';
import 'package:ava_gurlan/features/profile/screens/delete_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

/// «Ҳисобни ўчириш» экрани: Firebase'сиз (сохта репозиторий), ҳақиқий `assets/lang/uz_Latn.json` матнлари.
class _FakeRepo extends AccountDeletionRepository {
  _FakeRepo(this.previews, {this.requestError, this.cancelError});

  final List<AccountDeletionPreview> previews; // ҳар preview() навбатдаги қийматни беради (охиргиси такрорланади)
  final Object? requestError;
  final Object? cancelError;
  int previewCalls = 0;
  int requestCalls = 0;
  int cancelCalls = 0;
  Object? previewError;

  @override
  Future<AccountDeletionPreview> preview() async {
    previewCalls++;
    final e = previewError;
    if (e != null) {
      previewError = null;
      throw e;
    }
    return previews[(previewCalls - 1).clamp(0, previews.length - 1)];
  }

  @override
  Future<DateTime?> request() async {
    requestCalls++;
    if (requestError != null) throw requestError!;
    return DateTime(2030, 1, 10);
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (cancelError != null) throw cancelError!;
  }
}

AccountDeletionPreview _p({
  bool enabled = true,
  int waitDays = 10,
  List<AccountDeletionBlocker> blockers = const [],
  int wallet = 0,
  List<String> paid = const [],
  String? status,
  DateTime? scheduled,
}) =>
    AccountDeletionPreview(
      enabled: enabled,
      waitDays: waitDays,
      exists: true,
      blockers: blockers,
      walletAmount: wallet,
      paidServices: paid,
      status: status,
      scheduledFor: scheduled,
    );

void main() {
  final d = JsonL10nDelegate();
  String t(String k) => d.tr(k);

  Future<void> pump(WidgetTester tester, _FakeRepo repo,
      {Future<void> Function(BuildContext, int)? onRequested, double width = 400, double scale = 1.0}) async {
    // ListView экрандан ташқаридаги элементларни қурмайди — баландлик катта (барча блоклар қурилсин).
    tester.view.physicalSize = Size(width, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(l10nApp(
      delegate: d,
      textScale: scale,
      home: DeleteAccountScreen(repository: repo, onRequested: onRequested ?? (_, __) async {}),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('дарвоза ёпиқ: тушунтириш матни, ўчириш тугмаси йўқ', (tester) async {
    await pump(tester, _FakeRepo([_p(enabled: false)]));
    expect(find.text(t('acct_del_off_body')), findsOneWidget);
    expect(find.byKey(const ValueKey('acct-del-confirm')), findsNothing);
  });

  testWidgets('блок бор: ҳудуд бўйича бир матндан (такрорсиз), ўчириш тугмаси йўқ', (tester) async {
    await pump(
      tester,
      _FakeRepo([
        _p(blockers: const [
          AccountDeletionBlocker(code: 'ORDER_ACTIVE', area: 'orders', count: 2),
          AccountDeletionBlocker(code: 'CARPET_ACTIVE', area: 'orders', count: 1),
          AccountDeletionBlocker(code: 'TAXI_DEBT', area: 'courier', count: 1),
          AccountDeletionBlocker(code: 'STAFF_ROLE', area: 'staff', count: 1),
        ]),
      ]),
    );
    expect(find.byKey(const ValueKey('acct-del-blocked')), findsOneWidget);
    expect(find.text(t('acct_del_blk_orders')), findsOneWidget); // иккита orders блоки — битта сатр
    expect(find.text(t('acct_del_blk_courier')), findsOneWidget);
    expect(find.text(t('acct_del_blk_staff')), findsOneWidget);
    expect(find.text(t('acct_del_blk_money')), findsNothing);
    expect(find.byKey(const ValueKey('acct-del-confirm')), findsNothing);
    // техник код/атама кўринмайди (45-банд)
    expect(find.textContaining('ORDER_ACTIVE'), findsNothing);
    expect(find.textContaining('ZONE'), findsNothing);
  });

  testWidgets('оддий ҳолат: сумма «қайтарилмайди» билан, пулли хизматлар, тугма белгисиз ўчиқ', (tester) async {
    await pump(tester, _FakeRepo([_p(wallet: 150000, paid: const ['realty_pro', 'assistant_package'])]));
    expect(find.text(t('acct_del_what_body')), findsOneWidget);
    expect(find.text(t('acct_del_keep_body')), findsOneWidget);
    expect(find.textContaining('150 000'), findsOneWidget);
    expect(find.textContaining(t('acct_del_wait').split('{days}').first), findsOneWidget);
    expect(find.text(t('acct_del_paid_realty_pro')), findsOneWidget);
    expect(find.text(t('acct_del_paid_assistant')), findsOneWidget);
    expect(find.text(t('acct_del_paid_realty_unlocks')), findsNothing);
    final btn = tester.widget<FilledButton>(find.byKey(const ValueKey('acct-del-confirm')));
    expect(btn.onPressed, isNull); // белги қўйилмагунча ўчиқ
  });

  testWidgets('ҳамён бўш ва пулли хизмат йўқ: тегишли блоклар кўринмайди', (tester) async {
    await pump(tester, _FakeRepo([_p()]));
    expect(find.text(t('acct_del_wallet_zero')), findsOneWidget);
    expect(find.byKey(const ValueKey('acct-del-paid')), findsNothing);
  });

  testWidgets('белги қўйилса тугма ёқилади; босилса сўров юборилади ва onRequested кунлар билан чақирилади', (tester) async {
    final repo = _FakeRepo([_p(waitDays: 7)]);
    int? gotDays;
    await pump(tester, repo, onRequested: (_, days) async => gotDays = days);
    await tester.tap(find.byKey(const ValueKey('acct-del-check')));
    await tester.pump();
    final btn = tester.widget<FilledButton>(find.byKey(const ValueKey('acct-del-confirm')));
    expect(btn.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('acct-del-confirm')));
    await tester.pumpAndSettle();
    expect(repo.requestCalls, 1);
    expect(gotDays, 7);
  });

  testWidgets('сервер блок деса (ҳолат ўзгарган): экран қайта юкланиб блокларни кўрсатади, onRequested чақирилмайди', (tester) async {
    final repo = _FakeRepo(
      [
        _p(),
        _p(blockers: const [AccountDeletionBlocker(code: 'TRIP_ACTIVE', area: 'trips', count: 1)]),
      ],
      requestError: const AccountDeletionFailure('ACCOUNT_DELETION_BLOCKED'),
    );
    var called = false;
    await pump(tester, repo, onRequested: (_, __) async => called = true);
    await tester.tap(find.byKey(const ValueKey('acct-del-check')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('acct-del-confirm')));
    await tester.pumpAndSettle();
    expect(called, isFalse);
    expect(repo.previewCalls, 2);
    expect(find.text(t('acct_del_blk_trips')), findsOneWidget);
  });

  testWidgets('бошқа хато: тушунарли матн, навигация йўқ, тугма яна ишлайди', (tester) async {
    final repo = _FakeRepo([_p()], requestError: const AccountDeletionFailure('INTERNAL'));
    var called = false;
    await pump(tester, repo, onRequested: (_, __) async => called = true);
    await tester.tap(find.byKey(const ValueKey('acct-del-check')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('acct-del-confirm')));
    await tester.pumpAndSettle();
    expect(called, isFalse);
    expect(find.text(t('acct_del_error')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('acct-del-confirm'))).onPressed, isNotNull);
    expect(find.textContaining('INTERNAL'), findsNothing); // ичкари код кўринмайди (25-банд)
  });

  testWidgets('кутилаётган сўров: сана ва «бекор қилиш»; бекор қилингач маълумот қайта юкланади', (tester) async {
    final repo = _FakeRepo([
      _p(status: 'PENDING', scheduled: DateTime(2026, 11, 3)),
      _p(), // бекор қилингандан кейин: сўров йўқ
    ]);
    await pump(tester, repo);
    expect(find.byKey(const ValueKey('acct-del-pending')), findsOneWidget);
    expect(find.textContaining('03.11.2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('acct-del-confirm')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('acct-del-cancel')));
    await tester.pumpAndSettle();
    expect(repo.cancelCalls, 1);
    expect(repo.previewCalls, 2);
    expect(find.byKey(const ValueKey('acct-del-pending')), findsNothing);
    expect(find.text(t('acct_del_cancelled')), findsOneWidget);
    expect(find.byKey(const ValueKey('acct-del-confirm')), findsOneWidget);
  });

  testWidgets('ижро бошланган (EXECUTING): бекор қилиш тугмаси йўқ', (tester) async {
    await pump(tester, _FakeRepo([_p(status: 'EXECUTING', scheduled: DateTime(2026, 11, 3))]));
    expect(find.byKey(const ValueKey('acct-del-cancel')), findsNothing);
    expect(find.text(t('acct_del_in_progress')), findsOneWidget);
  });

  testWidgets('бекор қилишда сервер «ижро бошланган» деса — тушунарли матн', (tester) async {
    final repo = _FakeRepo(
      [_p(status: 'PENDING', scheduled: DateTime(2026, 11, 3))],
      cancelError: const AccountDeletionFailure('ACCOUNT_DELETION_IN_PROGRESS'),
    );
    await pump(tester, repo);
    await tester.tap(find.byKey(const ValueKey('acct-del-cancel')));
    await tester.pumpAndSettle();
    expect(find.text(t('acct_del_in_progress')), findsOneWidget);
  });

  testWidgets('юклаш хатоси: қайта уриниш тугмаси; босилса юкланади', (tester) async {
    final repo = _FakeRepo([_p()])..previewError = Exception('network');
    await pump(tester, repo);
    expect(find.text(t('acct_del_load_error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('acct-del-retry')));
    await tester.pumpAndSettle();
    expect(find.text(t('acct_del_what_body')), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('320 px кенглик, матн ×$scale — overflow йўқ (барча блоклар билан)', (tester) async {
      await pump(
        tester,
        _FakeRepo([_p(wallet: 12345678, paid: const ['realty_pro', 'realty_unlocks', 'assistant_package'])]),
        width: 320,
        scale: scale,
      );
      expect(tester.takeException(), isNull);
    });
  }

  group('3 тилдаги матнлар', () {
    final keys = <String>[];
    final langs = {for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) l: loadLang(l)};
    langs['uz_Latn']!.keys.where((k) => k.startsWith('acct_del_')).forEach(keys.add);

    test('калитлар сони 37 та ва ҳар учала тилда бор, бўш эмас', () {
      expect(keys.length, 37);
      for (final e in langs.entries) {
        for (final k in keys) {
          expect(e.value[k], isNotNull, reason: '${e.key}: $k йўқ');
          expect(e.value[k]!.trim(), isNotEmpty, reason: '${e.key}: $k бўш');
        }
      }
    });

    test('жой белгилари ({amount},{days},{date}) учала тилда бир хил', () {
      final re = RegExp(r'\{(\w+)\}');
      for (final k in keys) {
        Set<String> ph(String lang) => re.allMatches(langs[lang]![k]!).map((m) => m.group(1)!).toSet();
        expect(ph('uz_Cyrl'), ph('uz_Latn'), reason: k);
        expect(ph('ru'), ph('uz_Latn'), reason: k);
      }
    });

    test('JSON файллар бутун (ёмон қўштирноқ/қўшилиш йўқ)', () {
      for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        expect(() => jsonDecode(File('assets/lang/$l.json').readAsStringSync()), returnsNormally);
      }
    });
  });

  group('AccountDeletionPreview.fromMap', () {
    test('тўлиқ жавоб', () {
      final p = AccountDeletionPreview.fromMap({
        'enabled': true,
        'waitDays': 10,
        'exists': true,
        'blockers': [
          {'code': 'ORDER_ACTIVE', 'area': 'orders', 'count': 2},
        ],
        'walletAmount': 5000,
        'paidServices': ['realty_pro'],
        'state': {'status': 'PENDING', 'scheduledForMs': 1800000000000},
      });
      expect(p.enabled, isTrue);
      expect(p.blockers.single.area, 'orders');
      expect(p.walletAmount, 5000);
      expect(p.paidServices, ['realty_pro']);
      expect(p.hasActiveRequest, isTrue);
      expect(p.canCancel, isTrue);
      expect(p.scheduledFor, DateTime.fromMillisecondsSinceEpoch(1800000000000));
    });

    test('бўш/нотўғри жавоб — хавфсиз қийматлар (ёпиқ дарвоза эмас, лекин блоксиз, сўровсиз)', () {
      final p = AccountDeletionPreview.fromMap(const {});
      expect(p.enabled, isFalse); // дарвоза очиқ деб ҳисобланмайди
      expect(p.blockers, isEmpty);
      expect(p.hasActiveRequest, isFalse);
      expect(p.walletAmount, 0);
    });

    test('EXECUTING бекор қилинмайди', () {
      final p = AccountDeletionPreview.fromMap({'state': {'status': 'EXECUTING'}});
      expect(p.hasActiveRequest, isTrue);
      expect(p.canCancel, isFalse);
    });
  });
}
