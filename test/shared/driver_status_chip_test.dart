import 'package:ava_gurlan/features/home/widgets/ava_bottom_nav.dart';
import 'package:ava_gurlan/models/driver_roles.dart';
import 'package:ava_gurlan/shared/widgets/driver_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpChip(WidgetTester tester, DriverRoles roles) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DriverStatusChip(userId: '998901112233', load: (_) async => roles),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // Локализациясиз калитнинг ўзи чиқади — матн таркиби текширилади.
  testWidgets('ҳайдовчи эмас — чип кўринмайди', (tester) async {
    await _pumpChip(tester, DriverRoles.none);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('битта тур фаол — фақат шу тур кўрсатилади', (tester) async {
    await _pumpChip(
      tester,
      const DriverRoles(
          types: ['intercity', 'local'], active: {'intercity'}),
    );
    expect(find.text('driver_chip_title · driver_type_intercity'),
        findsOneWidget);
    expect(find.textContaining('driver_type_local'), findsNothing);
  });

  testWidgets('иккала тур фаол — иккаласи кўрсатилади', (tester) async {
    await _pumpChip(
      tester,
      const DriverRoles(
          types: ['intercity', 'local'], active: {'intercity', 'local'}),
    );
    expect(
      find.text('driver_chip_title · driver_type_intercity · driver_type_local'),
      findsOneWidget,
    );
  });

  testWidgets('ҳеч бири фаол эмас — оддий «Ҳайдовчи»', (tester) async {
    await _pumpChip(
      tester,
      const DriverRoles(types: ['intercity'], active: {}),
    );
    expect(find.text('driver_chip_title'), findsOneWidget);
    expect(find.textContaining('driver_type_'), findsNothing);
  });

  testWidgets('босилса барча турлар ва ҳолатлари чиқади', (tester) async {
    await _pumpChip(
      tester,
      const DriverRoles(
          types: ['intercity', 'marshrut'], active: {'marshrut'}),
    );
    await tester.tap(find.text('driver_chip_title · driver_type_marshrut'));
    await tester.pumpAndSettle();
    expect(find.text('driver_type_intercity'), findsOneWidget);
    expect(find.text('driver_type_marshrut'), findsOneWidget);
    expect(find.text('driver_chip_active'), findsOneWidget);
    expect(find.text('driver_chip_inactive'), findsOneWidget);
  });

  testWidgets('«＋» менюси: ҳайдовчи бўлса «Ҳайдовчи панели»', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showAvaCreateSheet(
              context,
              driverRoles: const DriverRoles(
                  types: ['intercity'], active: {'intercity'}),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Курьер алоҳида банд бўлди (2026-10-16): ҳайдовчи қатори мустақил.
    expect(find.text('home_create_driver_open'), findsOneWidget);
    expect(find.text('home_create_driver'), findsNothing);
  });
}
