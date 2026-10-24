import 'package:ava_gurlan/features/admin_web/screens/account_deletion_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/account_deletion_admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Админ «Ҳисобни ўчириш» экрани: Firebase'сиз (сохта сервис). Матнлар кирилл (админ панел ҳаммаси шундай).
class _FakeSvc extends AccountDeletionAdminService {
  _FakeSvc({
    this.rows = const [],
    AdminDeletionGate? gate,
    this.detailFor,
    this.cancelError,
    this.retryError,
    this.setGateError,
    this.requestError,
  }) : gate0 = gate ?? const AdminDeletionGate(enabled: true, waitDays: 10, allow: ['998901112233']);

  List<AdminDeletionRow> rows;
  AdminDeletionGate gate0;
  final AdminDeletionDetail Function(String uid)? detailFor;
  final Object? cancelError;
  final Object? retryError;
  final Object? setGateError;
  final Object? requestError;
  bool listFails = false;

  final listCalls = <List<String>?>[];
  final cancels = <(String, String)>[];
  final retries = <(String, String)>[];
  final requests = <(String, String)>[];
  final gateSaves = <Map<String, Object?>>[];

  @override
  Future<List<AdminDeletionRow>> list({List<String>? statuses, int limit = 100}) async {
    listCalls.add(statuses);
    if (listFails) {
      listFails = false;
      throw Exception('network');
    }
    return rows;
  }

  @override
  Future<AdminDeletionDetail> detail(String uid) async =>
      detailFor?.call(uid) ?? AdminDeletionDetail(row: rows.firstWhere((r) => r.uid == uid), steps: const {}, events: const [], hiddenCount: 0);

  @override
  Future<void> cancel(String uid, String reason) async {
    cancels.add((uid, reason));
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> retry(String uid, String reason) async {
    retries.add((uid, reason));
    if (retryError != null) throw retryError!;
  }

  @override
  Future<void> request(String phone, String reason) async {
    requests.add((phone, reason));
    if (requestError != null) throw requestError!;
  }

  @override
  Future<AdminDeletionGate> gate() async => gate0;

  @override
  Future<void> setGate({required bool enabled, required int waitDays, required List<String> allow, required String reason}) async {
    gateSaves.add({'enabled': enabled, 'waitDays': waitDays, 'allow': allow, 'reason': reason});
    if (setGateError != null) throw setGateError!;
  }
}

AdminDeletionRow _row(String uid, String status, {String err = '', int attempts = 0, String source = 'app'}) => AdminDeletionRow(
      uid: uid,
      status: status,
      source: source,
      attempts: attempts,
      walletAtRequest: 12000,
      hidePending: false,
      lastError: err,
      blockers: const [],
      requestedAt: DateTime(2026, 10, 24, 9, 5),
      scheduledFor: DateTime(2026, 11, 3, 9, 5),
      completedAt: status == 'DONE' ? DateTime(2026, 11, 3, 10, 0) : null,
    );

void main() {
  Future<void> pump(WidgetTester tester, _FakeSvc svc, {bool isSuper = false, double width = 900}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    // эски State қайта ишлатилмасин (late final сервис): аввал бўш дарахт
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: AccountDeletionAdminScreen(service: svc, isSuperAdmin: isSuper)));
    await tester.pumpAndSettle();
  }

  testWidgets('рўйхат ва дарвоза юкланади; админ учун ўзгартириш/қўлда сўров тугмалари йўқ', (tester) async {
    final svc = _FakeSvc(rows: [_row('998901112233', 'PENDING'), _row('998907776655', 'FAILED', err: 'auth down', attempts: 5)]);
    await pump(tester, svc);
    expect(find.text('+998901112233'), findsOneWidget);
    expect(find.text('+998907776655'), findsOneWidget);
    expect(find.textContaining('хато: auth down'), findsOneWidget);
    expect(find.textContaining('уриниш: 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('acct_admin_gate_mode')), findsOneWidget);
    expect(find.textContaining('ИЧКИ СИНОВ — фақат 1 та рақам'), findsOneWidget);
    expect(find.byKey(const ValueKey('acct_admin_gate_edit')), findsNothing);
    expect(find.byKey(const ValueKey('acct_admin_request')), findsNothing);
  });

  testWidgets('superadmin: дарвозани ўзгартириш ва қўлда сўров тугмалари кўринади', (tester) async {
    await pump(tester, _FakeSvc(), isSuper: true);
    expect(find.byKey(const ValueKey('acct_admin_gate_edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('acct_admin_request')), findsOneWidget);
  });

  testWidgets('дарвоза ҳолатлари матни: ёпиқ / ички / очиқ', (tester) async {
    await pump(tester, _FakeSvc(gate: const AdminDeletionGate(enabled: false, waitDays: 10, allow: [])));
    expect(find.textContaining('ЁПИҚ'), findsOneWidget);
    await pump(tester, _FakeSvc(gate: const AdminDeletionGate(enabled: true, waitDays: 7, allow: [])));
    expect(find.textContaining('ОЧИҚ — ҳамма учун'), findsOneWidget);
    expect(find.text('Кутиш: 7 кун'), findsOneWidget);
  });

  testWidgets('фильтр: «Муваффақиятсиз» FAILED ни сўрайди; бўш рўйхат матни', (tester) async {
    final svc = _FakeSvc();
    await pump(tester, svc);
    expect(svc.listCalls.last, isNull); // стандарт — фаол
    expect(find.byKey(const ValueKey('acct_admin_empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('acct_admin_filter_1')));
    await tester.pumpAndSettle();
    expect(svc.listCalls.last, ['FAILED']);
    await tester.tap(find.byKey(const ValueKey('acct_admin_filter_2')));
    await tester.pumpAndSettle();
    expect(svc.listCalls.last, ['DONE']);
    await tester.tap(find.byKey(const ValueKey('acct_admin_filter_3')));
    await tester.pumpAndSettle();
    expect(svc.listCalls.last, ['CANCELLED']);
  });

  testWidgets('юклаш хатоси: қайта уриниш тугмаси', (tester) async {
    final svc = _FakeSvc(rows: [_row('998901112233', 'PENDING')])..listFails = true;
    await pump(tester, svc);
    expect(find.text('Юклаб бўлмади. Қайта уриниб кўринг.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('acct_admin_retry')));
    await tester.pumpAndSettle();
    expect(find.text('+998901112233'), findsOneWidget);
  });

  testWidgets('тафсилот: ҳолат, қадамлар, воқеалар, хато; PENDING да «Бекор қилиш» бор, «Қайта юритиш» йўқ', (tester) async {
    final r = _row('998901112233', 'PENDING');
    final svc = _FakeSvc(
      rows: [r],
      detailFor: (_) => AdminDeletionDetail(
        row: r,
        steps: const {'forfeit_wallet': true, 'auth_delete': false},
        hiddenCount: 4,
        events: [
          AdminDeletionEvent(type: 'requested', at: DateTime(2026, 10, 24, 9, 5)),
          AdminDeletionEvent(type: 'cancelled', at: DateTime(2026, 10, 25), meta: const {'by': '998901000002'}),
        ],
      ),
    );
    await pump(tester, svc, isSuper: true);
    await tester.tap(find.byKey(const ValueKey('acct_admin_row_998901112233')));
    await tester.pumpAndSettle();
    expect(find.text('Ҳолат: Кутилмоқда'), findsOneWidget);
    expect(find.text('✓ Ҳамён сўндирилди'), findsOneWidget);
    expect(find.text('… Кириш ҳисоби ўчирилди'), findsOneWidget);
    expect(find.textContaining('Яширилган ҳужжатлар: 4'), findsOneWidget);
    expect(find.textContaining('Сўров юборилди'), findsOneWidget);
    expect(find.textContaining('Бекор қилинди (998901000002)'), findsOneWidget);
    expect(find.byKey(const ValueKey('acct_admin_cancel_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('acct_admin_retry_btn')), findsNothing);
  });

  testWidgets('«Қайта юритиш» фақат FAILED да ва фақат superadmin учун; DONE да иккаласи ҳам йўқ', (tester) async {
    final failed = _row('998907776655', 'FAILED', err: 'x');
    final done = _row('998901234500', 'DONE');
    final svc = _FakeSvc(rows: [failed, done]);
    await pump(tester, svc, isSuper: false);
    await tester.tap(find.byKey(const ValueKey('acct_admin_row_998907776655')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acct_admin_retry_btn')), findsNothing); // админга йўқ
    expect(find.byKey(const ValueKey('acct_admin_cancel_btn')), findsOneWidget);
    await tester.tap(find.text('Ёпиш'));
    await tester.pumpAndSettle();
    await pump(tester, svc, isSuper: true);
    await tester.tap(find.byKey(const ValueKey('acct_admin_row_998907776655')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acct_admin_retry_btn')), findsOneWidget);
    await tester.tap(find.text('Ёпиш'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('acct_admin_filter_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('acct_admin_row_998901234500')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acct_admin_retry_btn')), findsNothing);
    expect(find.byKey(const ValueKey('acct_admin_cancel_btn')), findsNothing);
  });

  testWidgets('бекор қилиш: сабаб 3 белгидан кам бўлса тугма ўчиқ; сабаб билан сервисга кетади ва рўйхат янгиланади', (tester) async {
    final svc = _FakeSvc(rows: [_row('998901112233', 'PENDING')]);
    await pump(tester, svc);
    await tester.tap(find.byKey(const ValueKey('acct_admin_row_998901112233')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('acct_admin_cancel_btn')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('acct_admin_reason_ok'))).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'ab');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('acct_admin_reason_ok'))).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'чатда фикридан қайтди');
    await tester.pump();
    final callsBefore = svc.listCalls.length;
    await tester.tap(find.byKey(const ValueKey('acct_admin_reason_ok')));
    await tester.pumpAndSettle();
    expect(svc.cancels, [('998901112233', 'чатда фикридан қайтди')]);
    expect(svc.listCalls.length, callsBefore + 1); // рўйхат қайта юкланди
    expect(find.byKey(const ValueKey('acct_admin_detail_status')), findsNothing); // ойна ёпилди
  });

  testWidgets('бекор қилишда сервер «ижро бошланган» деса — ойна очиқ қолади, тушунарли матн', (tester) async {
    final svc = _FakeSvc(rows: [_row('998901112233', 'PENDING')], cancelError: const AdminDeletionFailure('ACCOUNT_DELETION_IN_PROGRESS'));
    await pump(tester, svc);
    await tester.tap(find.byKey(const ValueKey('acct_admin_row_998901112233')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('acct_admin_cancel_btn')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'керак эди');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('acct_admin_reason_ok')));
    await tester.pumpAndSettle();
    expect(find.text('Ижро бошланган, бекор қилиб бўлмайди.'), findsOneWidget);
    expect(find.byKey(const ValueKey('acct_admin_detail_status')), findsOneWidget);
  });

  testWidgets('қайта юритиш (superadmin, FAILED): сабаб билан чақирилади', (tester) async {
    final svc = _FakeSvc(rows: [_row('998907776655', 'FAILED', err: 'auth down')]);
    await pump(tester, svc, isSuper: true);
    await tester.tap(find.byKey(const ValueKey('acct_admin_row_998907776655')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('acct_admin_retry_btn')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'Auth тикланди');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('acct_admin_reason_ok')));
    await tester.pumpAndSettle();
    expect(svc.retries, [('998907776655', 'Auth тикланди')]);
  });

  testWidgets('қўлда сўров: телефон ва сабаб тўғри бўлмагунча тугма ўчиқ; рақамлар тозаланиб юборилади', (tester) async {
    final svc = _FakeSvc();
    await pump(tester, svc, isSuper: true);
    await tester.tap(find.byKey(const ValueKey('acct_admin_request')));
    await tester.pumpAndSettle();
    final ok = find.byKey(const ValueKey('acct_admin_request_ok'));
    expect(tester.widget<FilledButton>(ok).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('acct_admin_phone')), '12345');
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'email орқали');
    await tester.pump();
    expect(tester.widget<FilledButton>(ok).onPressed, isNull); // телефон нотўғри
    await tester.enterText(find.byKey(const ValueKey('acct_admin_phone')), '+998 90 111-22-33');
    await tester.pump();
    expect(tester.widget<FilledButton>(ok).onPressed, isNotNull);
    await tester.tap(ok);
    await tester.pumpAndSettle();
    expect(svc.requests, [('998901112233', 'email орқали')]);
  });

  testWidgets('қўлда сўровда сервер блок десa — тушунарли матн (snackbar)', (tester) async {
    final svc = _FakeSvc(requestError: const AdminDeletionFailure('ACCOUNT_DELETION_BLOCKED'));
    await pump(tester, svc, isSuper: true);
    await tester.tap(find.byKey(const ValueKey('acct_admin_request')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('acct_admin_phone')), '998901112233');
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'сабаб бор');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('acct_admin_request_ok')));
    await tester.pumpAndSettle();
    expect(find.text('Ҳисобда тугамаган ишлар бор — ўчириб бўлмайди.'), findsOneWidget);
  });

  testWidgets('дарвоза: ИЧКИ режимда рақамлар шарт ва шакли текширилади; сақлаш сабаб билан, рақамлар тозаланади', (tester) async {
    final svc = _FakeSvc(gate: const AdminDeletionGate(enabled: false, waitDays: 10, allow: []));
    await pump(tester, svc, isSuper: true);
    await tester.tap(find.byKey(const ValueKey('acct_admin_gate_edit')));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('acct_admin_gate_save'));
    await tester.tap(find.byKey(const ValueKey('acct_admin_mode_internal')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'ички синов');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull); // рақам йўқ
    await tester.enterText(find.byKey(const ValueKey('acct_admin_allow')), '123');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull); // нотўғри рақам
    await tester.enterText(find.byKey(const ValueKey('acct_admin_allow')), '+998 90 111-22-33\n901234567, 998907776655');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(svc.gateSaves, [
      {'enabled': true, 'waitDays': 10, 'allow': ['998901112233', '901234567', '998907776655'], 'reason': 'ички синов'},
    ]);
  });

  testWidgets('дарвоза: «Ёпиқ» режим рўйхатни юбормайди; кун 1–60 дан ташқари бўлса тугма ўчиқ', (tester) async {
    final svc = _FakeSvc();
    await pump(tester, svc, isSuper: true);
    await tester.tap(find.byKey(const ValueKey('acct_admin_gate_edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('acct_admin_mode_off')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'тўхтатиш');
    await tester.enterText(find.byKey(const ValueKey('acct_admin_days')), '61');
    await tester.pump();
    final save = find.byKey(const ValueKey('acct_admin_gate_save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('acct_admin_days')), '0');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('acct_admin_days')), '14');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(svc.gateSaves.single['enabled'], false);
    expect(svc.gateSaves.single['allow'], isEmpty);
    expect(svc.gateSaves.single['waitDays'], 14);
  });

  testWidgets('дарвоза «Очиқ»: қўшимча тасдиқ; «Йўқ» — ҳеч нарса юборилмайди, «Ҳа» — юборилади', (tester) async {
    final svc = _FakeSvc();
    await pump(tester, svc, isSuper: true);
    await tester.tap(find.byKey(const ValueKey('acct_admin_gate_edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('acct_admin_mode_public')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'ҳамма учун очиш');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('acct_admin_gate_save')));
    await tester.pumpAndSettle();
    expect(find.text('Ҳамма учун очилсинми?'), findsOneWidget);
    await tester.tap(find.text('Йўқ'));
    await tester.pumpAndSettle();
    expect(svc.gateSaves, isEmpty);
    await tester.tap(find.byKey(const ValueKey('acct_admin_gate_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('acct_admin_public_yes')));
    await tester.pumpAndSettle();
    expect(svc.gateSaves.single['enabled'], true);
    expect(svc.gateSaves.single['allow'], isEmpty);
  });

  testWidgets('дарвозани сақлашда сервер хато берса — ойна очиқ, тушунарли матн', (tester) async {
    final svc = _FakeSvc(setGateError: const AdminDeletionFailure('INVALID_GATE'));
    await pump(tester, svc, isSuper: true);
    await tester.tap(find.byKey(const ValueKey('acct_admin_gate_edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('acct_admin_reason')), 'синов');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('acct_admin_gate_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acct_admin_gate_error')), findsOneWidget);
    expect(find.text('Дарвоза қиймати нотўғри.'), findsOneWidget);
  });

  testWidgets('тор экран (360 px) ва узун хато матни — overflow йўқ', (tester) async {
    final svc = _FakeSvc(rows: [_row('998901112233', 'FAILED', err: 'x' * 280, attempts: 5, source: 'admin')]);
    await pump(tester, svc, isSuper: true, width: 360);
    expect(tester.takeException(), isNull);
  });

  group('моделлар', () {
    test('AdminDeletionGate.mode', () {
      expect(const AdminDeletionGate(enabled: false, waitDays: 10, allow: ['x']).mode, 'off');
      expect(const AdminDeletionGate(enabled: true, waitDays: 10, allow: ['x']).mode, 'internal');
      expect(const AdminDeletionGate(enabled: true, waitDays: 10, allow: []).mode, 'public');
    });

    test('AdminDeletionRow.fromMap: тўлиқ ва бўш жавоб', () {
      final r = AdminDeletionRow.fromMap({
        'uid': '998901112233',
        'status': 'POSTPONED',
        'attempts': 2,
        'requestedAtMs': 1800000000000,
        'lastBlockers': [
          {'code': 'ORDER_ACTIVE', 'area': 'orders', 'count': 2},
        ],
      });
      expect(r.canCancel, isTrue);
      expect(r.canRetry, isFalse);
      expect(r.blockers, ['ORDER_ACTIVE:2']);
      expect(r.requestedAt, DateTime.fromMillisecondsSinceEpoch(1800000000000));
      final e = AdminDeletionRow.fromMap(const {});
      expect(e.status, '');
      expect(e.canCancel, isFalse);
    });

    test('AdminDeletionDetail.fromMap: қадамлар ва воқеалар', () {
      final d = AdminDeletionDetail.fromMap({
        'uid': 'u',
        'status': 'DONE',
        'steps': {
          'user_shell': {'done': true},
          'auth_delete': {'done': false},
        },
        'hiddenCount': 3,
        'events': [
          {'type': 'done', 'atMs': 1800000000000, 'meta': {}},
        ],
      });
      expect(d.steps, {'user_shell': true, 'auth_delete': false});
      expect(d.hiddenCount, 3);
      expect(d.events.single.type, 'done');
    });
  });
}
