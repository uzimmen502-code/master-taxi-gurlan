import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/wholesale/widgets/ship_from_fields.dart';
import 'package:ava_gurlan/models/geo_area.dart';
import 'package:ava_gurlan/repositories/service_config_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Firebase'сиз: ҳудуд рўйхати бўш.
class _FakeGeo implements ServiceConfigRepository {
  @override
  Future<List<GeoRegion>> fetchRegions({bool activeOnly = true}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, {required bool required, ShipFromDraft value = const ShipFromDraft()}) async {
  tester.view.physicalSize = const Size(360 * 2, 900 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ShipFromFields(
          value: value,
          locationRequired: required,
          geoRepository: _FakeGeo(),
          onChanged: (_) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('рўйхатдан ўтиш (locationRequired): «шарт» ёзуви ва «харитада белгилаш» тугмаси бор', (tester) async {
    await _pump(tester, required: true);
    expect(find.text('wholesale_location_required_hint'), findsOneWidget);
    expect(find.text('wholesale_location_optional'), findsNothing);
    expect(find.text('wholesale_pick_on_map'), findsOneWidget);
    expect(find.text('wholesale_locate_me'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '360px кенгликда overflow бўлмаслиги керак');
  });

  testWidgets('таҳрир (эски сотувчи): координата ихтиёрий ёзуви сақланади', (tester) async {
    await _pump(tester, required: false);
    expect(find.text('wholesale_location_optional'), findsOneWidget);
    expect(find.text('wholesale_location_required_hint'), findsNothing);
    expect(find.text('wholesale_pick_on_map'), findsOneWidget);
  });

  testWidgets('координата белгиланган бўлса — «сақланди» ёзуви (икки ҳолатда ҳам)', (tester) async {
    await _pump(tester, required: true, value: const ShipFromDraft(lat: 41.3, lng: 69.2));
    expect(find.text('wholesale_location_set'), findsOneWidget);
    expect(find.text('wholesale_location_required_hint'), findsNothing);
  });
}
