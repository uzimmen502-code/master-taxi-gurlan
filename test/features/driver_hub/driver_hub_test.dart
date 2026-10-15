import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/driver_hub/driver_hub_state.dart';
import 'package:ava_gurlan/features/driver_hub/screens/driver_hub_screen.dart';
import 'package:ava_gurlan/features/home/widgets/work_roles_sheet.dart';
import 'package:ava_gurlan/models/driver_roles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 15, 12);

DriverRoles _starter(Duration left) => DriverRoles(
      types: const ['intercity'],
      taxiStatus: 'starter',
      starterEndsAt: _now.add(left),
    );

Widget _host({
  required DriverRoles roles,
  Map<String, String>? car,
  Future<void> Function(WorkChoice, DriverRoles)? onAction,
  Future<HubSubmitResult> Function()? onSubmit,
  Future<void> Function()? onEditCar,
}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: DriverHubScreen(
        key: UniqueKey(), // қайта pump'да ҳолат қайта юклансин
        choices: const [
          WorkChoice.intercity,
          WorkChoice.local,
          WorkChoice.marshrut,
          WorkChoice.courier,
        ],
        loadRoles: () async => roles,
        loadCar: () async => car,
        onAction: onAction ?? (_, __) async {},
        onEditCar: onEditCar ?? () async {},
        onSubmitVerification: onSubmit ?? () async => HubSubmitResult.sent,
        onOpenWallet: () async {},
        clock: () => _now,
      ),
    );

void main() {
  group('hubVerifKind', () {
    test('ҳайдовчи эмас — карточка йўқ', () {
      expect(hubVerifKind(DriverRoles.none, _now), HubVerifKind.none);
    });

    test('starter: 4 кун — оддий, 3 кун — огоҳлантириш (чегара)', () {
      expect(hubVerifKind(_starter(const Duration(days: 4)), _now), HubVerifKind.starter);
      expect(hubVerifKind(_starter(const Duration(days: 3)), _now), HubVerifKind.ending);
      expect(hubVerifKind(_starter(const Duration(hours: 1)), _now), HubVerifKind.ending);
    });

    test('starter: сана йўқ — кўрсатилмайди (тахмин қилинмайди)', () {
      const r = DriverRoles(types: ['intercity'], taxiStatus: 'starter');
      expect(hubVerifKind(r, _now), HubVerifKind.none);
    });

    test('verification_required: келишувга қараб юбориш / кутиш', () {
      const a = DriverRoles(types: ['intercity'], taxiStatus: 'verification_required');
      const b = DriverRoles(
        types: ['intercity'],
        taxiStatus: 'verification_required',
        agreementAccepted: true,
      );
      expect(hubVerifKind(a, _now), HubVerifKind.requiredToSubmit);
      expect(hubVerifKind(b, _now), HubVerifKind.requiredPending);
    });

    test('verified ва suspended (types бўш бўлса ҳам)', () {
      expect(hubVerifKind(const DriverRoles(taxiStatus: 'verified'), _now), HubVerifKind.verified);
      expect(hubVerifKind(const DriverRoles(taxiStatus: 'suspended'), _now), HubVerifKind.suspended);
    });
  });

  group('DriverRoles.starterDaysLeft', () {
    test('қисман кун юқорига яхлитланади, ўтган — 0, starter эмас — null', () {
      expect(_starter(const Duration(hours: 49)).starterDaysLeft(_now), 3);
      expect(_starter(const Duration(days: -1)).starterDaysLeft(_now), 0);
      expect(
        DriverRoles(taxiStatus: 'verified', starterEndsAt: _now).starterDaysLeft(_now),
        isNull,
      );
    });
  });

  group('DriverHubScreen', () {
    testWidgets('автомобиль, 4 тур ва ҳамён кўринади', (t) async {
      // Узун рўйхат: ListView экрандан ташқарини қурмайди — баланд экран.
      t.view.physicalSize = const Size(400 * 2, 2400 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(_host(
        roles: _starter(const Duration(days: 30)),
        car: {'carModel': 'Chevrolet Cobalt', 'carColor': 'Oq', 'carPlate': '01A123BC', 'carSeats': '4'},
      ));
      await t.pumpAndSettle();
      expect(find.text('Chevrolet Cobalt · Oq'), findsOneWidget);
      expect(find.text('hub_car_edit'), findsOneWidget);
      expect(find.text('role_type_intercity'), findsOneWidget);
      expect(find.text('role_type_local'), findsOneWidget);
      expect(find.text('role_type_marshrut'), findsOneWidget);
      expect(find.text('work_type_courier'), findsOneWidget);
      expect(find.text('hub_action_publish'), findsOneWidget); // шаҳарлараро — рўйхатдан ўтган
      expect(find.text('work_state_join'), findsWidgets); // қолганлари — «Бўлиш»
    });

    testWidgets('тугмалар матн ТАГИДА (ён томонда бўлса матн ингичка устунга сиқилади)', (t) async {
      t.view.physicalSize = const Size(360 * 3, 800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(_host(roles: _starter(const Duration(days: 30))));
      await t.pumpAndSettle();
      final title = t.getRect(find.text('role_type_intercity'));
      final btn = t.getRect(find.widgetWithText(FilledButton, 'hub_action_publish'));
      expect(btn.top, greaterThanOrEqualTo(title.bottom));
      expect(title.width, greaterThan(150), reason: 'матн кенг қолади');
      final carTitle = t.getRect(find.text('hub_car_title'));
      final carBtn = t.getRect(find.widgetWithText(TextButton, 'hub_car_add'));
      expect(carBtn.top, greaterThanOrEqualTo(carTitle.bottom));
    });

    testWidgets('автомобиль йўқ — «қўшиш» тугмаси', (t) async {
      await t.pumpWidget(_host(roles: DriverRoles.none));
      await t.pumpAndSettle();
      expect(find.text('hub_car_empty'), findsOneWidget);
      expect(find.text('hub_car_add'), findsOneWidget);
    });

    testWidgets('«Бўлиш» — onAction тур ва ЭНГ ЯНГИ ҳолат билан чақирилади', (t) async {
      WorkChoice? got;
      DriverRoles? gotRoles;
      final roles = _starter(const Duration(days: 30));
      await t.pumpWidget(_host(
        roles: roles,
        onAction: (c, r) async {
          got = c;
          gotRoles = r;
        },
      ));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'work_state_join').first);
      await t.pumpAndSettle();
      expect(got, WorkChoice.local);
      expect(identical(gotRoles, roles), isTrue);
    });

    testWidgets('«Текширувга юбориш» фақат келишув қабул қилинмаган даврда', (t) async {
      await t.pumpWidget(_host(
        roles: const DriverRoles(types: ['intercity'], taxiStatus: 'verification_required'),
      ));
      await t.pumpAndSettle();
      expect(find.text('hub_verif_submit'), findsOneWidget);

      await t.pumpWidget(_host(
        roles: const DriverRoles(
          types: ['intercity'],
          taxiStatus: 'verification_required',
          agreementAccepted: true,
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('hub_verif_submit'), findsNothing);
      expect(find.text('hub_verif_pending'), findsOneWidget);
    });

    testWidgets('юбориш: sent — хабар; cancelled — жим; failed — хато', (t) async {
      for (final (res, key) in [
        (HubSubmitResult.sent, 'hub_verif_pending'),
        (HubSubmitResult.failed, 'hub_verif_submit_failed'),
      ]) {
        await t.pumpWidget(_host(
          roles: const DriverRoles(types: ['intercity'], taxiStatus: 'verification_required'),
          onSubmit: () async => res,
        ));
        await t.pumpAndSettle();
        await t.tap(find.text('hub_verif_submit'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(find.descendant(of: find.byType(SnackBar), matching: find.text(key)), findsOneWidget);
        ScaffoldMessenger.of(t.element(find.byType(Scaffold))).clearSnackBars();
        await t.pumpAndSettle();
      }

      await t.pumpWidget(_host(
        roles: const DriverRoles(types: ['intercity'], taxiStatus: 'verification_required'),
        onSubmit: () async => HubSubmitResult.cancelled,
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('hub_verif_submit'));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('амалдан кейин ҳолат қайта ўқилади', (t) async {
      var loads = 0;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: DriverHubScreen(
          choices: const [WorkChoice.local],
          loadRoles: () async {
            loads++;
            return DriverRoles.none;
          },
          loadCar: () async => null,
          onAction: (_, __) async {},
          onEditCar: () async {},
          onSubmitVerification: () async => HubSubmitResult.sent,
          onOpenWallet: () async {},
        ),
      ));
      await t.pumpAndSettle();
      expect(loads, 1);
      await t.tap(find.text('hub_car_add'));
      await t.pumpAndSettle();
      expect(loads, 2);
    });
  });
}
