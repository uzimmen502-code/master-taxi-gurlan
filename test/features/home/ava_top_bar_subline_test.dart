import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/active_roles_strip.dart';
import 'package:ava_gurlan/features/home/widgets/ava_top_bar.dart';
import 'package:ava_gurlan/models/driver_roles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double scale = 1.0}) => MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
      ),
    );

void main() {
  setUp(ServiceConfigHolder.resetForTest);
  tearDown(ServiceConfigHolder.resetForTest);

  testWidgets('subline йўқ — аввалги кўриниш (ихчам эмас)', (tester) async {
    await tester.pumpWidget(_host(AvaTopBar(onPickRegion: () {})));
    await tester.pump();
    expect(find.byType(ActiveRolesStrip), findsNothing);
    // Ҳудуд тугмаси одатий (ихчам эмас) баландликда қолади.
    final inkWell = tester.getSize(find.byType(InkWell).first);
    expect(inkWell.height, greaterThan(40));
  });

  testWidgets('subline бор — ёзув ҳудуд матнининг тагида, оралиқ ≤ 8 dp',
      (tester) async {
    await tester.pumpWidget(_host(AvaTopBar(
      onPickRegion: () {},
      subline: const ActiveRolesStrip(roles: DriverRoles(courierOnline: true)),
    )));
    await tester.pump();
    expect(find.text('role_strip_courier'), findsOneWidget);

    // Ҳудуд тугмаси ихчам (28 dp), ёзув унинг ЭНГ ТАГИДАН бошланади.
    final region = tester.getRect(find.byType(InkWell).first);
    final strip = tester.getRect(find.byType(ActiveRolesStrip));
    expect(region.height, lessThan(40), reason: 'ихчам тугма');
    expect(strip.top - region.bottom, closeTo(0, 0.5), reason: 'оралиқ 0 px');
    expect(strip.top, greaterThanOrEqualTo(region.bottom));

    // Бутун қатор баландлиги қуйидан ошиб кетмайди (логотип 42 + 12 чет).
    final bar = tester.getRect(find.byType(AvaTopBar));
    expect(bar.height, lessThanOrEqualTo(42 + 12 + 24));
  });

  testWidgets('катта шрифтда ҳам тошмайди (×1.3)', (tester) async {
    await tester.pumpWidget(_host(
      AvaTopBar(
        onPickRegion: () {},
        subline: const ActiveRolesStrip(
          roles: DriverRoles(
            types: ['intercity', 'local'],
            active: {'intercity', 'local'},
            courierOnline: true,
          ),
        ),
      ),
      scale: 1.3,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
