import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/driver_hub/screens/driver_hub_screen.dart';
import 'package:ava_gurlan/features/home/widgets/work_roles_sheet.dart';
import 'package:ava_gurlan/models/driver_roles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ҳайдовчи панелидаги янги тугмалар (эга, 2026-10-16): автомобилни ўчириш,
/// сменани тугатиш, ҳайдовчиликдан чиқиш. Улар Кабинетдан кўчирилди.
Widget _host({
  required DriverRoles roles,
  Map<String, String>? car,
  Future<bool> Function()? onDeleteCar,
  Future<void> Function()? onEndShift,
  Future<void> Function()? onLeaveDriver,
}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: DriverHubScreen(
        key: UniqueKey(),
        // Курьер энди бу панелда йўқ — алоҳида банд.
        choices: const [WorkChoice.intercity, WorkChoice.local, WorkChoice.marshrut],
        loadRoles: () async => roles,
        loadCar: () async => car,
        onAction: (_, __) async {},
        onEditCar: () async {},
        onDeleteCar: onDeleteCar,
        onEndShift: onEndShift,
        onLeaveDriver: onLeaveDriver,
        onSubmitVerification: () async => HubSubmitResult.sent,
        onOpenWallet: () async {},
      ),
    );

const _car = {
  'carModel': 'Cobalt',
  'carColor': 'Oq',
  'carPlate': '01A123BC',
  'carSeats': '4',
};

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(400 * 2, 2400 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('панелда курьер картаси йўқ (алоҳида банд бўлди)', (t) async {
    _tall(t);
    await t.pumpWidget(_host(roles: const DriverRoles(types: ['intercity'])));
    await t.pumpAndSettle();
    expect(find.text('work_type_courier'), findsNothing);
    expect(find.text('role_type_intercity'), findsOneWidget);
  });

  testWidgets('автомобиль бор: «Ўчириш» босилади ва callback чақирилади', (t) async {
    _tall(t);
    var calls = 0;
    await t.pumpWidget(_host(
      roles: const DriverRoles(types: ['intercity']),
      car: _car,
      onDeleteCar: () async {
        calls++;
        return true;
      },
    ));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'delete'));
    await t.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('автомобиль йўқ: «Ўчириш» тугмаси кўринмайди', (t) async {
    _tall(t);
    await t.pumpWidget(_host(
      roles: const DriverRoles(types: ['intercity']),
      onDeleteCar: () async => true,
    ));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'delete'), findsNothing);
    expect(find.text('hub_car_add'), findsOneWidget);
  });

  testWidgets('callback берилмаса тугмалар умуман чиқмайди (орқага мослик)', (t) async {
    _tall(t);
    await t.pumpWidget(_host(
      roles: const DriverRoles(types: ['local'], active: {'local'}),
      car: _car,
    ));
    await t.pumpAndSettle();
    expect(find.text('delete'), findsNothing);
    expect(find.text('end_shift'), findsNothing);
    expect(find.text('leave_driver_permanent'), findsNothing);
  });

  group('«Сменани тугатиш»', () {
    testWidgets('маҳаллий тур онлайн — кўринади ва ишлайди', (t) async {
      _tall(t);
      var calls = 0;
      await t.pumpWidget(_host(
        roles: const DriverRoles(types: ['local'], active: {'local'}),
        onEndShift: () async => calls++,
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('end_shift'));
      await t.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('маршрут тур онлайн — кўринади', (t) async {
      _tall(t);
      await t.pumpWidget(_host(
        roles: const DriverRoles(types: ['marshrut'], active: {'marshrut'}),
        onEndShift: () async {},
      ));
      await t.pumpAndSettle();
      expect(find.text('end_shift'), findsOneWidget);
    });

    testWidgets('фақат шаҳарлараро «фаол» (рейс) — смена тугмаси ЙЎҚ', (t) async {
      _tall(t);
      await t.pumpWidget(_host(
        roles: const DriverRoles(types: ['intercity'], active: {'intercity'}),
        onEndShift: () async {},
      ));
      await t.pumpAndSettle();
      expect(find.text('end_shift'), findsNothing);
    });

    testWidgets('ҳеч қайси тур онлайн эмас — тугма йўқ', (t) async {
      _tall(t);
      await t.pumpWidget(_host(
        roles: const DriverRoles(types: ['local', 'marshrut']),
        onEndShift: () async {},
      ));
      await t.pumpAndSettle();
      expect(find.text('end_shift'), findsNothing);
    });
  });

  group('«Ҳайдовчиликдан чиқиш»', () {
    testWidgets('ҳайдовчи (тури бор) — кўринади ва callback чақирилади', (t) async {
      _tall(t);
      var calls = 0;
      await t.pumpWidget(_host(
        roles: const DriverRoles(types: ['intercity']),
        onLeaveDriver: () async => calls++,
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('leave_driver_permanent'));
      await t.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('ҳайдовчи эмас — кўринмайди', (t) async {
      _tall(t);
      await t.pumpWidget(_host(
        roles: DriverRoles.none,
        onLeaveDriver: () async {},
      ));
      await t.pumpAndSettle();
      expect(find.text('leave_driver_permanent'), findsNothing);
    });
  });
}
