// «Уй-жой бозори» қўшиш формаси (эга 2026-11-19): тур чиплари, ерда хона
// яширилади, сотих, «Қўшимча маълумотлар», расм 0/10, манзил ёрлиғи.
import 'package:ava_gurlan/features/realty/screens/add_realty_listing_screen.dart';
import 'package:ava_gurlan/repositories/realty_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo implements RealtyRepository {
  @override
  Future<RealtyQuota> fetchQuota() async => RealtyQuota.empty;

  @override
  Future<String> loadTemplateText() async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pump(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(1080, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: AddRealtyListingScreen(repository: _FakeRepo())));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('тур чиплари; ер танланса хона/қават яширилади, сотих чиқади', (t) async {
    await _pump(t);
    expect(find.byKey(const ValueKey('realty_type_apartment')), findsOneWidget);
    expect(find.text('realty_field_rooms'), findsOneWidget);
    expect(find.byKey(const ValueKey('realty_field_land_sotix')), findsNothing);

    await t.tap(find.byKey(const ValueKey('realty_type_land')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('realty_field_rooms'), findsNothing);
    expect(find.text('realty_field_floor'), findsNothing);
    expect(find.byKey(const ValueKey('realty_field_land_sotix')), findsOneWidget);

    // Чегарадан ташқари сотих — хато матни.
    await t.enterText(find.byKey(const ValueKey('realty_field_land_sotix')), '0.05');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('realty_error_sotix'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('realty_field_land_sotix')), '6');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('realty_error_sotix'), findsNothing);

    // Қайта босилса — тур бекор, хона қайтади, сотих яширилади.
    await t.tap(find.byKey(const ValueKey('realty_type_land')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('realty_field_rooms'), findsOneWidget);
    expect(find.byKey(const ValueKey('realty_field_land_sotix')), findsNothing);
  });

  testWidgets('ҳовлида сотих ҳам, хона ҳам бор', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const ValueKey('realty_type_house')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('realty_field_rooms'), findsOneWidget);
    expect(find.byKey(const ValueKey('realty_field_land_sotix')), findsOneWidget);
  });

  testWidgets('«Қўшимча маълумотлар» йиғиқ; очилса майдонлар, йил чегараси', (t) async {
    await _pump(t);
    expect(find.text('realty_more_info'), findsOneWidget);
    expect(find.byKey(const ValueKey('realty_renovation_euro')), findsNothing);
    await t.tap(find.text('realty_more_info'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('realty_renovation_euro')), findsOneWidget);
    expect(find.byKey(const ValueKey('realty_utility_gas')), findsOneWidget);
    expect(find.byKey(const ValueKey('realty_flag_barter')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('realty_field_year_built')), '1850');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('realty_error_year'), findsOneWidget);
  });

  testWidgets('ижарада муддат ва депозит; валюта чиплари; расм 0/10; манзил *', (t) async {
    await _pump(t);
    expect(find.text('realty_field_deposit'), findsNothing);
    await t.tap(find.text('realty_deal_rent'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('realty_rent_month')), findsOneWidget);
    expect(find.text('realty_field_deposit'), findsOneWidget);
    expect(find.byKey(const ValueKey('realty_currency_UZS')), findsOneWidget);
    expect(find.byKey(const ValueKey('realty_currency_USD')), findsOneWidget);
    expect(find.text('realty_field_photos (0/10)'), findsOneWidget);
    expect(find.text('realty_field_address *'), findsOneWidget);
  });
}
