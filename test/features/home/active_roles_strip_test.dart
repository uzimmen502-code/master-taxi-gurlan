import 'package:ava_gurlan/core/theme/ava_tokens.dart';
import 'package:ava_gurlan/features/home/widgets/active_roles_strip.dart';
import 'package:ava_gurlan/models/driver_roles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uz = <String, String>{
  'role_strip_driver': '{parts} ҳайдовчисиз',
  'role_strip_courier': 'Курьерсиз',
  'role_strip_courier_driver': 'Курьер+{parts} ҳайдовчисиз',
  'role_strip_many': '{n} хизматда фаолсиз',
  'role_type_intercity': 'Шаҳарлараро',
  'role_type_local': 'Маҳаллий такси',
  'role_type_marshrut': 'Маршрут такси',
};

String? _label(DriverRoles r) => activeRolesLabel(r, (k) => _uz[k] ?? k);

void main() {
  group('activeRolesLabel', () {
    test('фаол ҳеч нарса йўқ — null', () {
      expect(_label(DriverRoles.none), isNull);
      expect(
        _label(const DriverRoles(types: ['intercity'], active: {})),
        isNull,
      );
    });

    test('фақат шаҳарлараро', () {
      expect(
        _label(const DriverRoles(
            types: ['intercity', 'local'], active: {'intercity'})),
        'Шаҳарлараро ҳайдовчисиз',
      );
    });

    test('курьер + шаҳарлараро', () {
      expect(
        _label(const DriverRoles(
            types: ['intercity'], active: {'intercity'}, courierOnline: true)),
        'Курьер+Шаҳарлараро ҳайдовчисиз',
      );
    });

    test('маҳаллий такси ва курьер + маҳаллий такси', () {
      expect(
        _label(const DriverRoles(types: ['local'], active: {'local'})),
        'Маҳаллий такси ҳайдовчисиз',
      );
      expect(
        _label(const DriverRoles(
            types: ['local'], active: {'local'}, courierOnline: true)),
        'Курьер+Маҳаллий такси ҳайдовчисиз',
      );
    });

    test('фақат курьер онлайн', () {
      expect(_label(const DriverRoles(courierOnline: true)), 'Курьерсиз');
    });

    test('икки тур фаол — «+» билан', () {
      expect(
        _label(const DriverRoles(
            types: ['intercity', 'local'], active: {'intercity', 'local'})),
        'Шаҳарлараро+Маҳаллий такси ҳайдовчисиз',
      );
    });

    test('тўртта фаол хизмат — қисқа ёзув', () {
      expect(
        _label(const DriverRoles(
          types: ['intercity', 'local', 'marshrut'],
          active: {'intercity', 'local', 'marshrut'},
          courierOnline: true,
        )),
        '4 хизматда фаолсиз',
      );
    });
  });

  group('ActiveRolesStrip', () {
    testWidgets('фаол бўлмаса ҳеч нарса чизмайди', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ActiveRolesStrip(roles: DriverRoles.none)),
      ));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('фаол бўлса матн чиқади ва босилади', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ActiveRolesStrip(
            roles: const DriverRoles(courierOnline: true),
            onTap: () => taps++,
          ),
        ),
      ));
      // Локализациясиз калитнинг ўзи чиқади.
      expect(find.text('role_strip_courier'), findsOneWidget);
      await tester.tap(find.text('role_strip_courier'));
      expect(taps, 1);
    });

    // Аудит 2026-10-19: `Colors.green/grey` ўрнига токенлар.
    testWidgets('нуқта `ok`, матн `ink` токенида', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ActiveRolesStrip(roles: DriverRoles(courierOnline: true)),
        ),
      ));
      final text = tester.widget<Text>(find.text('role_strip_courier'));
      expect(text.style!.color, AvaLight.ink);
      final dot = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(ActiveRolesStrip),
            matching: find.byType(Container),
          ))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .single;
      expect(dot.color, AvaLight.ok);
      expect(dot.shape, BoxShape.circle);
    });

    testWidgets('«анимацияни камайтириш» ёқилса нуқта қимирламайди',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(
            body: ActiveRolesStrip(roles: DriverRoles(courierOnline: true)),
          ),
        ),
      ));
      // Чексиз анимация бўлмаса pumpAndSettle тугайди.
      await tester.pumpAndSettle();
      expect(find.text('role_strip_courier'), findsOneWidget);
    });
  });
}
