import 'package:ava_gurlan/features/courier/screens/courier_scopes_screen.dart';
import 'package:ava_gurlan/repositories/courier_scopes_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

/// «Иш ҳудуди» (эга қарори 2026-10-31): туман дарҳол; вилоят/республика —
/// машина маълумоти тўлиқ бўлмаса серверга юборилмайди; ҳолатлар кўринади.
class _FakeRepo implements CourierScopesRepository {
  _FakeRepo(this.data);

  CourierScopes data;
  final requests = <List<String>>[];
  final vehicles = <Map<String, String>>[];

  @override
  Future<CourierScopes> load(String uid) async => data;

  @override
  Future<void> saveVehicle(String uid, Map<String, String> vehicle) async => vehicles.add(vehicle);

  @override
  Future<Map<String, String>> requestScopes(List<String> scopes) async {
    requests.add(scopes);
    return const {};
  }
}

final _l10n = JsonL10nDelegate('uz_Cyrl');

Future<void> _pump(WidgetTester tester, _FakeRepo repo) async {
  await tester.pumpWidget(l10nApp(
    delegate: _l10n,
    home: CourierScopesScreen(uid: '998901112233', repository: repo),
  ));
  await tester.pumpAndSettle();
}

const _empty = <String, String>{};

void main() {
  testWidgets('эски ҳужжат: «Туман» белгиланган, машина бўлими йўқ, сақлаш → [district]', (tester) async {
    final repo = _FakeRepo(const CourierScopes(scopes: ['district'], review: _empty, vehicle: _empty));
    await _pump(tester, repo);
    expect(find.text('Иш ҳудуди'), findsOneWidget);
    expect(find.text('Машина ва ҳужжат'), findsNothing);
    await tester.tap(find.text('Сақлаш'));
    await tester.pumpAndSettle();
    expect(repo.requests, [
      ['district'],
    ]);
    expect(repo.vehicles, isEmpty);
  });

  testWidgets('вилоят: машинасиз — хато, серверга юборилмайди; тўлдирилгач юборилади', (tester) async {
    final repo = _FakeRepo(const CourierScopes(scopes: ['district'], review: _empty, vehicle: _empty));
    await _pump(tester, repo);
    await tester.tap(find.text('Вилоят'));
    await tester.pumpAndSettle();
    expect(find.text('Машина ва ҳужжат'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Сақлаш'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Сақлаш'));
    await tester.pumpAndSettle();
    expect(find.text('Вилоят ва республика учун машина маълумотини тўлиқ киритинг'), findsOneWidget);
    expect(repo.requests, isEmpty);

    await tester.tap(find.text('Менда машина бор'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '90A123BC');
    await tester.enterText(fields.at(1), 'Cobalt');
    await tester.enterText(fields.at(2), 'AF1234567');
    await tester.scrollUntilVisible(find.text('Сақлаш'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Сақлаш'));
    await tester.pumpAndSettle();
    expect(repo.vehicles.single['vehicleType'], 'car');
    expect(repo.requests.single, ['district', 'region']);
  });

  testWidgets('ҳолатлар: вилоят кутилмоқда, туман ўчирилса огоҳлантириш', (tester) async {
    final repo = _FakeRepo(const CourierScopes(
      scopes: ['district', 'region'],
      review: {'region': 'pending'},
      vehicle: {'vehicleType': 'car', 'carPlate': '90A', 'carModel': 'Nexia', 'driverLicenseNo': 'AF1'},
    ));
    await _pump(tester, repo);
    expect(find.text('Тасдиқ кутилмоқда'), findsOneWidget);
    await tester.tap(find.text('Туман'));
    await tester.pumpAndSettle();
    expect(find.text('«Туман» танланмаган — туман ичидаги буюртмалар келмайди.'), findsOneWidget);
  });

  testWidgets('ҳеч нарса танланмаса — серверга юборилмайди', (tester) async {
    final repo = _FakeRepo(const CourierScopes(scopes: ['district'], review: _empty, vehicle: _empty));
    await _pump(tester, repo);
    await tester.tap(find.text('Туман'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сақлаш'));
    await tester.pumpAndSettle();
    expect(find.text('Камида битта ҳудудни танланг'), findsOneWidget);
    expect(repo.requests, isEmpty);
  });
}
