import 'package:ava_gurlan/features/admin_web/screens/device_approvals_screen.dart';
import 'package:ava_gurlan/features/onboarding/screens/device_transfer_approve_screen.dart';
import 'package:ava_gurlan/features/onboarding/widgets/device_binding_conflict_sheet.dart';
import 'package:ava_gurlan/repositories/device_binding_repository.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Qurilma xavfsizligi (ega 2026-11-28): «Бу сизми?» ekrani, «Эски телефоним
/// йўқ» tugmasi, admin «Қурилма тасдиқлари». Firebase'siz; lokalizatsiya
/// delegati ulanmagan — `context.tr` kalitni qaytaradi.

void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpLauncher(WidgetTester tester, Widget screen) async {
  _tallSurface(tester);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.push(
                ctx, MaterialPageRoute<bool>(builder: (_) => screen)),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

class _FakeApi implements DeviceApprovalsApi {
  _FakeApi(this.items);
  final List<DeviceApprovalItem> items;
  final decisions = <Map<String, Object>>[];

  final phones = <String>[];

  @override
  Future<List<DeviceApprovalItem>> list(String status, {String phone = ''}) async {
    phones.add(phone);
    if (phone.isNotEmpty) return items.where((e) => e.phone == phone).toList();
    return items.where((e) => e.status == status && e.channel == 'admin_review').toList();
  }

  @override
  Future<void> decide({
    required String requestId,
    required bool approve,
    String note = '',
    String identityCheck = '',
  }) async {
    decisions.add({
      'requestId': requestId,
      'approve': approve,
      'note': note,
      'identityCheck': identityCheck,
    });
  }
}

void main() {
  group('«Бу сизми?» (DeviceTransferApproveScreen)', () {
    testWidgets('qurilma, platforma, shahar va vaqt ko\'rinadi; Ҳа/Йўқ bor',
        (tester) async {
      await _pumpLauncher(
        tester,
        DeviceTransferApproveScreen(
          requestId: 'r1',
          newDeviceLabel: 'Xiaomi Redmi 12',
          platform: 'android',
          approxCity: 'Urganch',
          createdAtMs: DateTime(2026, 11, 28, 14, 5).millisecondsSinceEpoch,
          responder: (_) async =>
              const DeviceTransferRespondResult(status: 'approved'),
        ),
      );
      expect(find.text('ob_dev_isyou_title'), findsOneWidget);
      expect(find.text('Xiaomi Redmi 12'), findsOneWidget);
      expect(find.text('ob_dev_platform_android'), findsOneWidget);
      expect(find.text('Urganch'), findsOneWidget);
      expect(find.text('28.11 14:05'), findsOneWidget);
      expect(find.byKey(const Key('devApproveYes')), findsOneWidget);
      expect(find.byKey(const Key('devApproveNo')), findsOneWidget);
      expect(find.text('ob_dev_isyou_admin_note'), findsNothing);
    });

    testWidgets('Йўқ → responder(false), sessiya bekor bo\'lsa jim qayta kirish',
        (tester) async {
      final calls = <bool>[];
      var reauthed = 0;
      await _pumpLauncher(
        tester,
        DeviceTransferApproveScreen(
          requestId: 'r2',
          responder: (approve) async {
            calls.add(approve);
            return const DeviceTransferRespondResult(
                status: 'rejected', reauthRequired: true);
          },
          reauth: () async => reauthed++,
        ),
      );
      await tester.tap(find.byKey(const Key('devApproveNo')));
      await tester.pumpAndSettle();
      expect(calls, [false]);
      expect(reauthed, 1);
      expect(find.text('ob_dev_isyou_no_done'), findsOneWidget);
      expect(find.text('OPEN'), findsOneWidget, reason: 'ekran yopildi');
    });

    testWidgets('Ҳа → responder(true), qayta kirish chaqirilmaydi',
        (tester) async {
      final calls = <bool>[];
      var reauthed = 0;
      await _pumpLauncher(
        tester,
        DeviceTransferApproveScreen(
          requestId: 'r3',
          responder: (approve) async {
            calls.add(approve);
            return const DeviceTransferRespondResult(status: 'approved');
          },
          reauth: () async => reauthed++,
        ),
      );
      await tester.tap(find.byKey(const Key('devApproveYes')));
      await tester.pumpAndSettle();
      expect(calls, [true]);
      expect(reauthed, 0);
      expect(find.text('ob_dev_approve_done'), findsOneWidget);
    });

    testWidgets('admin ko\'rigi so\'rovi — ogohlantirish; DEVICE_NOT_BOUND xatosi',
        (tester) async {
      await _pumpLauncher(
        tester,
        DeviceTransferApproveScreen(
          requestId: 'r4',
          channel: 'admin_review',
          responder: (_) async => throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'x',
            details: const {'code': 'DEVICE_NOT_BOUND'},
          ),
        ),
      );
      expect(find.text('ob_dev_isyou_admin_note'), findsOneWidget);
      expect(find.text('ob_dev_isyou_unknown_device'), findsOneWidget);
      await tester.tap(find.byKey(const Key('devApproveYes')));
      await tester.pumpAndSettle();
      expect(find.text('ob_dev_isyou_not_bound'), findsOneWidget);
      expect(find.byType(DeviceTransferApproveScreen), findsOneWidget);
    });
  });

  group('Conflict sheet — «Эски телефоним йўқ»', () {
    Future<void> pumpBody(WidgetTester tester, DeviceBindingCheckResult r) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: DeviceBindingConflictSheetBody(result: r)),
        ));

    testWidgets('raqam boshqa qurilmada: eski qurilmadan tasdiq + «Эски телефоним йўқ»',
        (tester) async {
      await pumpBody(
        tester,
        const DeviceBindingCheckResult(
          status: DeviceBindingStatus.phoneBoundOtherDevice,
          selfServeAvailable: true,
          adminReviewAvailable: true,
          oldDeviceLabel: 'samsung SM-A515F',
        ),
      );
      expect(find.byKey(const Key('devConflictConfirmOld')), findsOneWidget);
      expect(find.byKey(const Key('devConflictNoOldPhone')), findsOneWidget);
      expect(find.text('ob_dev_no_old_phone'), findsOneWidget);
      expect(find.text('ob_dev_no_old_phone_hint'), findsOneWidget);
    });

    testWidgets('hisob bor, bog\'langan qurilma yo\'q: faqat «Эски телефоним йўқ»',
        (tester) async {
      await pumpBody(
        tester,
        const DeviceBindingCheckResult(
          status: DeviceBindingStatus.phoneBoundOtherDevice,
          adminReviewAvailable: true,
          reason: 'account_unbound',
        ),
      );
      expect(find.text('ob_dev_unbound_title'), findsOneWidget);
      expect(find.byKey(const Key('devConflictConfirmOld')), findsNothing);
      expect(find.byKey(const Key('devConflictNoOldPhone')), findsOneWidget);
    });

    testWidgets('egasi «Йўқ» degan (24 s blok) — tushuntirish, tugma yo\'q',
        (tester) async {
      await pumpBody(
        tester,
        const DeviceBindingCheckResult(
          status: DeviceBindingStatus.blocked,
          code: 'DEVICE_DENIED_24H',
          reason: 'owner_rejected',
        ),
      );
      expect(find.text('ob_dev_denied_title'), findsOneWidget);
      expect(find.byKey(const Key('devConflictNoOldPhone')), findsNothing);
      expect(find.text('ob_dev_lost_hint'), findsOneWidget);
    });

    testWidgets('eski server javobi (adminReviewAvailable yo\'q) — avvalgidek',
        (tester) async {
      await pumpBody(
        tester,
        const DeviceBindingCheckResult(
          status: DeviceBindingStatus.phoneBoundOtherDevice,
          selfServeAvailable: true,
        ),
      );
      expect(find.byKey(const Key('devConflictConfirmOld')), findsOneWidget);
      expect(find.byKey(const Key('devConflictNoOldPhone')), findsNothing);
    });

    test('server ichki kodlari → 3 tildagi kalit', () {
      FirebaseFunctionsException ex(String code, String c) =>
          FirebaseFunctionsException(code: code, message: 'x', details: {'code': c});
      expect(deviceSecurityErrorKey(ex('failed-precondition', 'DEVICE_DENIED_24H')),
          'ob_dev_denied_body');
      expect(deviceSecurityErrorKey(ex('resource-exhausted', 'ADMIN_REVIEW_LIMIT')),
          'ob_dev_review_limit');
      expect(deviceSecurityErrorKey(ex('resource-exhausted', 'DEVICE_BINDING_RATE_LIMITED')),
          'err_too_many');
      expect(deviceSecurityErrorKey(ex('failed-precondition', 'PHONE_NOT_BOUND')),
          'ob_dev_phone_not_bound');
    });
  });

  group('Admin «Қурилма тасдиқлари»', () {
    const normal = DeviceApprovalItem(
      requestId: 'q1',
      phone: '998911000001',
      name: 'Ali',
      newDeviceLabel: 'Xiaomi Redmi 12',
      platform: 'android',
      note: 'telefon o\'g\'irlandi',
      canDecide: true,
      decidable: true,
      accountExists: true,
    );
    const privileged = DeviceApprovalItem(
      requestId: 'q2',
      phone: '998911000002',
      role: 'admin',
      privileged: true,
      canDecide: false,
      decidable: true,
    );

    testWidgets('ro\'yxat; admin raqami — faqat superadmin (tugma o\'chiq)',
        (tester) async {
      _tallSurface(tester);
      final api = _FakeApi([normal, privileged]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeviceApprovalsScreen(api: api)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Қурилма тасдиқлари'), findsOneWidget);
      expect(find.textContaining('998911000001'), findsOneWidget);
      expect(find.textContaining('telefon o\'g\'irlandi'), findsOneWidget);
      expect(find.textContaining('АДМИН РАҚАМИ'), findsOneWidget);
      expect(find.text('Фақат superadmin қарор қилади.'), findsOneWidget);
      final btn = tester.widget<ButtonStyleButton>(find.byKey(const Key('devApprove_q2')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('Тасдиқлаш → шахс текшируви матни билан decide()', (tester) async {
      _tallSurface(tester);
      final api = _FakeApi([normal]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeviceApprovalsScreen(api: api)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('devApprove_q1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('devApprovalIdentity')), 'qo\'ng\'iroq qilindi');
      await tester.tap(find.byKey(const Key('devApprovalConfirm')));
      await tester.pumpAndSettle();
      expect(api.decisions, hasLength(1));
      expect(api.decisions.single['approve'], true);
      expect(api.decisions.single['requestId'], 'q1');
      expect(api.decisions.single['identityCheck'], 'qo\'ng\'iroq qilindi');
    });

    testWidgets('рақам бўйича қидирув: эски APK peer сўрови топилади ва тасдиқланади',
        (tester) async {
      _tallSurface(tester);
      const peer = DeviceApprovalItem(
        requestId: 'q9',
        phone: '998911000009',
        status: 'expired',
        channel: 'old_device_push',
        decidable: true,
        canDecide: true,
      );
      final api = _FakeApi([normal, peer]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeviceApprovalsScreen(api: api)),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('devApproval_q9')), findsNothing);
      await tester.enterText(find.byKey(const Key('devApprovalPhoneSearch')), '998911000009');
      await tester.tap(find.byKey(const Key('devApprovalPhoneSearchGo')));
      await tester.pumpAndSettle();
      expect(api.phones.last, '998911000009');
      expect(find.byKey(const Key('devApproval_q9')), findsOneWidget);
      expect(find.textContaining('эски қурилмадан тасдиқлаш сўрови'), findsOneWidget);
      await tester.tap(find.byKey(const Key('devApprove_q9')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('devApprovalConfirm')));
      await tester.pumpAndSettle();
      expect(api.decisions.single['requestId'], 'q9');
    });

    testWidgets('Рад этиш → approve=false', (tester) async {
      _tallSurface(tester);
      final api = _FakeApi([normal]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeviceApprovalsScreen(api: api)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('devReject_q1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('devApprovalConfirm')));
      await tester.pumpAndSettle();
      expect(api.decisions.single['approve'], false);
    });
  });
}
