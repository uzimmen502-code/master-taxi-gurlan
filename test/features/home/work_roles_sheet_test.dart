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
