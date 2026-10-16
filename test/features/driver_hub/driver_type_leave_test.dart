import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/driver_hub/driver_hub_actions.dart';
import 'package:ava_gurlan/features/driver_hub/driver_type_leave.dart';
import 'package:ava_gurlan/features/driver_hub/screens/driver_hub_screen.dart';
import 'package:ava_gurlan/features/home/widgets/work_roles_sheet.dart';
import 'package:ava_gurlan/models/driver_roles.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Битта такси турини ўзи бекор қилиш (эга, 2026-10-16). Сервер қоидалари
/// `functions/test/driver_leave_type_cf.test.js` да; бу ерда — клиент: натижа
/// хариталаши, тасдиқ ва тугма кўриниши.
void main() {
  group('leaveDriverType натижаси', () {
    Future<DriverTypeLeaveResult> run(Future<Map<String, dynamic>> Function(Map<String, dynamic>) c) =>
        leaveDriverType(uid: '998901234567', taxiType: 'local', callable: c);

    test('ok → left; алоҳида аргументлар серверга тўғри кетади', () async {
      Map<String, dynamic>? sent;
      final r = await run((a) async {
        sent = a;
        return {'ok': true, 'alreadyLeft': false};
      });
      expect(r, DriverTypeLeaveResult.left);
      expect(sent, {'userPhone': '998901234567', 'taxiType': 'local'});
    });

    test('alreadyLeft → alreadyLeft (қайта чақирув хато эмас)', () async {
      expect(
        await run((_) async => {'ok': true, 'alreadyLeft': true}),
        DriverTypeLeaveResult.alreadyLeft,
      );
    });

    test('failed-precondition → blockedActive', () async {
      expect(
        await run((_) async => throw FirebaseFunctionsException(
            code: 'failed-precondition', message: 'DRIVER_TYPE_ACTIVE')),
        DriverTypeLeaveResult.blockedActive,
      );
    });

    test('permission-denied, unavailable ва ҳар қандай бошқа хато → failed', () async {
      for (final code in const ['permission-denied', 'unavailable', 'internal']) {
        expect(
          await run((_) async => throw FirebaseFunctionsException(code: code, message: 'x')),
          DriverTypeLeaveResult.failed,
          reason: code,
        );
      }
      expect(await run((_) async => throw StateError('net')), DriverTypeLeaveResult.failed);
    });

    test('ok:false ёки бўш жавоб → failed (муваффақият деб ҳисобланмайди)', () async {
      expect(await run((_) async => {'ok': false}), DriverTypeLeaveResult.failed);
      expect(await run((_) async => const {}), DriverTypeLeaveResult.failed);
    });
  });

  group('leaveDriverTypeWithConfirm', () {
    Future<DriverTypeLeaveResult?> open(
      WidgetTester t,
      LeaveTypeCallable callable, {
      String tap = 'confirm',
    }) async {
      DriverTypeLeaveResult? result;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => result = await leaveDriverTypeWithConfirm(
                context,
                uid: '998901234567',
                taxiType: 'marshrut',
                callable: callable,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('hub_leave_type_confirm_title'), findsOneWidget);
      await t.tap(find.text(tap));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('бекор қилинса сервер ЧАҚИРИЛМАЙДИ', (t) async {
      var calls = 0;
      await open(t, (_) async {
        calls++;
        return {'ok': true};
      }, tap: 'cancel');
      expect(calls, 0);
    });

    testWidgets('тасдиқ → сервер → «Тур олиб ташланди»', (t) async {
      final r = await open(t, (_) async => {'ok': true, 'alreadyLeft': false});
      expect(r, DriverTypeLeaveResult.left);
      expect(find.text('hub_leave_type_done'), findsOneWidget);
    });

    testWidgets('фаол иш бўлса — тушунарли хабар, муваффақият хабари йўқ', (t) async {
      final r = await open(
        t,
        (_) async => throw FirebaseFunctionsException(
            code: 'failed-precondition', message: 'DRIVER_TYPE_ACTIVE'),
      );
      expect(r, DriverTypeLeaveResult.blockedActive);
      expect(find.text('hub_leave_type_active'), findsOneWidget);
      expect(find.text('hub_leave_type_done'), findsNothing);
    });

    testWidgets('тармоқ хатоси — умумий хабар', (t) async {
      final r = await open(t, (_) async => throw StateError('offline'));
      expect(r, DriverTypeLeaveResult.failed);
      expect(find.text('error_generic'), findsOneWidget);
    });
  });

  group('Ҳайдовчи панелида «Бу турдан чиқиш»', () {
    Widget host(DriverRoles roles, {Future<void> Function(WorkChoice)? onLeaveType}) =>
        MaterialApp(
          theme: AppTheme.light,
          home: DriverHubScreen(
            key: UniqueKey(),
            choices: const [WorkChoice.intercity, WorkChoice.local, WorkChoice.marshrut],
            loadRoles: () async => roles,
            loadCar: () async => null,
            onAction: (_, __) async {},
            onEditCar: () async {},
            onSubmitVerification: () async => HubSubmitResult.sent,
            onOpenWallet: () async {},
            onLeaveType: onLeaveType,
          ),
        );

    void tall(WidgetTester t) {
      t.view.physicalSize = const Size(400 * 2, 2800 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
    }

    testWidgets('қўшилган ва фаол бўлмаган турларда кўринади, қўшилмаганида йўқ', (t) async {
      tall(t);
      await t.pumpWidget(host(
        const DriverRoles(types: ['intercity', 'local']),
        onLeaveType: (_) async {},
      ));
      await t.pumpAndSettle();
      // intercity + local қўшилган → 2 та; marshrut қўшилмаган → тугма йўқ.
      expect(find.text('hub_leave_type'), findsNWidgets(2));
    });

    testWidgets('ҳозир ФАОЛ тур картасида тугма йўқ (аввал ишни тугатиш керак)', (t) async {
      tall(t);
      await t.pumpWidget(host(
        const DriverRoles(types: ['intercity', 'local'], active: {'local'}),
        onLeaveType: (_) async {},
      ));
      await t.pumpAndSettle();
      expect(find.text('hub_leave_type'), findsOneWidget);
    });

    testWidgets('callback берилмаса умуман чиқмайди (орқага мослик)', (t) async {
      tall(t);
      await t.pumpWidget(host(const DriverRoles(types: ['intercity'])));
      await t.pumpAndSettle();
      expect(find.text('hub_leave_type'), findsNothing);
    });

    testWidgets('босилса ТЎҒРИ тур билан callback чақирилади', (t) async {
      tall(t);
      WorkChoice? got;
      await t.pumpWidget(host(
        const DriverRoles(types: ['marshrut']),
        onLeaveType: (c) async => got = c,
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('hub_leave_type'));
      await t.pumpAndSettle();
      expect(got, WorkChoice.marshrut);
    });
  });
}
