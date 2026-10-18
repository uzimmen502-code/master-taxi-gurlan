import 'package:ava_gurlan/core/theme/ava_tokens.dart';
import 'package:ava_gurlan/features/home/widgets/work_roles_sheet.dart';
import 'package:ava_gurlan/models/driver_roles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workRowState', () {
    test('такси: декларация йўқ — «Бўлиш»', () {
      final s = workRowState(WorkChoice.intercity, DriverRoles.none);
      expect(s.key, 'work_state_join');
      expect(s.tone, WorkTone.join);
    });

    test('такси: декларация бор, фаол', () {
      const r = DriverRoles(types: ['local'], active: {'local'});
      expect(workRowState(WorkChoice.local, r).tone, WorkTone.active);
      expect(workRowState(WorkChoice.local, r).key, 'driver_chip_active');
    });

    test('такси: декларация бор, фаол эмас', () {
      const r = DriverRoles(types: ['marshrut'], active: {});
      expect(workRowState(WorkChoice.marshrut, r).tone, WorkTone.inactive);
    });

    test('курьер: ҳолат ўқилмаган ёки not_registered — «Бўлиш»', () {
      expect(workRowState(WorkChoice.courier, DriverRoles.none).tone,
          WorkTone.join);
      expect(
        workRowState(
                WorkChoice.courier, const DriverRoles(courierStatus: 'not_registered'))
            .tone,
        WorkTone.join,
      );
    });

    test('курьер: ариза админ навбатида', () {
      final s = workRowState(
          WorkChoice.courier, const DriverRoles(courierStatus: 'applied'));
      expect(s.key, 'work_state_pending');
      expect(s.tone, WorkTone.pending);
    });

    test('курьер: ишлайди — онлайн/оффлайн', () {
      expect(
        workRowState(WorkChoice.courier,
                const DriverRoles(courierStatus: 'trial', courierOnline: true))
            .tone,
        WorkTone.active,
      );
      expect(
        workRowState(
                WorkChoice.courier, const DriverRoles(courierStatus: 'trial'))
            .tone,
        WorkTone.inactive,
      );
    });

    test('курьер: тўхтатилган', () {
      final s = workRowState(
          WorkChoice.courier, const DriverRoles(courierStatus: 'suspended'));
      expect(s.key, 'work_state_suspended');
      expect(s.tone, WorkTone.blocked);
    });
  });

  testWidgets('ойна: тўрт йўналиш ва танлов қайтади', (tester) async {
    WorkChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => result = await showWorkRolesSheet(
              context,
              roles: const DriverRoles(
                  types: ['intercity'],
                  active: {'intercity'},
                  courierStatus: 'applied'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final k in const [
      'role_type_intercity',
      'role_type_local',
      'role_type_marshrut',
      'work_type_courier',
      'work_state_pending',
    ]) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    await tester.tap(find.text('work_type_courier'));
    await tester.pumpAndSettle();
    expect(result, WorkChoice.courier);
  });
  // Аудит 2026-10-19: ҳолат ранглари `Colors.green/grey/orange/red` эди —
  // токенларга ўтди; «қўшилиш» матни `brand` (1.97:1) эмас, `brandText`.
  testWidgets('ҳолат ёрлиқлари токен рангларида', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showWorkRolesSheet(
              context,
              roles: const DriverRoles(
                  types: ['intercity', 'local'],
                  active: {'intercity'},
                  courierStatus: 'applied'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Color? colorOf(String key) =>
        tester.widget<Text>(find.text(key)).style?.color;

    expect(colorOf('driver_chip_active'), AvaLight.ok); // intercity
    expect(colorOf('driver_chip_inactive'), AvaLight.ink2); // local
    expect(colorOf('work_state_pending'), AvaLight.warn); // courier applied
    expect(colorOf('work_state_join'), AvaLight.brandText); // marshrut
  });

  group('confirmBecomeDriver', () {
    Future<bool?> run(WidgetTester tester, String tapKey) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  result = await confirmBecomeDriver(context, WorkChoice.intercity),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('work_confirm_title'), findsOneWidget);
      await tester.tap(find.text(tapKey));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('«Бекор қилиш» — false (рўйхатдан ўтказилмайди)', (tester) async {
      expect(await run(tester, 'cancel'), isFalse);
    });

    testWidgets('«Тасдиқлаш» — true', (tester) async {
      expect(await run(tester, 'confirm'), isTrue);
    });
  });}
