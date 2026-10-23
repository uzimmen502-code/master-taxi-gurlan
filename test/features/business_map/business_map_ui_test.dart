import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/controllers/business_map_gps_controller.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/widgets/business_category_chips.dart';
import 'package:ava_gurlan/features/business_map/widgets/business_marker_icons.dart';
import 'package:ava_gurlan/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class _Loc implements LocationService {
  _Loc({this.fail});

  /// `init` ($getCurrentCoords) хатоси; `null` — GPS бор.
  LocationErrorKind? fail;

  /// `getCoordsIfAllowed` натижаси: `null` — GPS/рухсат ҳали йўқ.
  LocationCoords? allowed;

  @override
  Future<LocationCoords> getCurrentCoords({
    Duration mediumTimeout = const Duration(seconds: 5),
    Duration highTimeout = const Duration(seconds: 10),
  }) async {
    if (fail != null) throw LocationException(fail!);
    return const LocationCoords(lat: 41.8, lng: 60.4);
  }

  @override
  Future<LocationCoords?> getCoordsIfAllowed({Duration timeout = const Duration(seconds: 6)}) async => allowed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('BusinessCategory ранглари', () {
    test('14 та ранг, ҳаммаси турлича ва тўлиқ шаффоф эмас (чип ва маркер учун)', () {
      final colors = [for (final c in BusinessCategory.values) c.color.toARGB32()];
      expect(colors.length, 14);
      expect(colors.toSet().length, 14, reason: 'иккита тур бир хил рангда бўлмаслиги керак');
      for (final c in BusinessCategory.values) {
        expect(c.color.a, 1.0, reason: c.wire);
      }
    });

    test('иконкалар ҳам турлича (чипда ажратиш осон)', () {
      expect({for (final c in BusinessCategory.values) c.icon.codePoint}.length, 14);
    });
  });

  group('BusinessCategoryChips', () {
    Future<void> pump(WidgetTester tester, {BusinessCategory? selected, required ValueChanged<BusinessCategory?> onChanged}) async {
      tester.view.physicalSize = const Size(380 * 2, 400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: BusinessCategoryChips(selected: selected, onChanged: onChanged)),
      ));
    }

    testWidgets('«Ҳаммаси» + БАРЧА 14 тур чипи (скроллда ҳам мавжуд, яшириб қўйилмайди)', (tester) async {
      await pump(tester, onChanged: (_) {});
      expect(find.byKey(const ValueKey('biz_chip_all')), findsOneWidget);
      // ListView кечиктирилган қурилади: ҳар бирига скролл қилиб, мавжудлигини текшириб чиқамиз.
      for (final c in BusinessCategory.values) {
        await tester.scrollUntilVisible(find.byKey(ValueKey('biz_chip_${c.wire}')), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.byKey(ValueKey('biz_chip_${c.wire}')), findsOneWidget, reason: c.wire);
        expect(find.text(c.labelKey), findsOneWidget);
      }
    });

    testWidgets('босилганда танланган тур қайтади; «Ҳаммаси» — null', (tester) async {
      final picked = <BusinessCategory?>[];
      await pump(tester, selected: BusinessCategory.food, onChanged: picked.add);
      await tester.tap(find.byKey(const ValueKey('biz_chip_all')));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('biz_chip_food')), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.byKey(const ValueKey('biz_chip_food'))); // марказ экран ичида бўлсин
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('biz_chip_food')));
      await tester.pump();
      expect(picked, [null, BusinessCategory.food]);
    });

    testWidgets('танланган чип ўз ранги билан тўлдирилади; танланмаган — оқ', (tester) async {
      await pump(tester, selected: BusinessCategory.food, onChanged: (_) {});
      Color bgOf(String key) {
        final m = tester.widget<Material>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Material)).first);
        return m.color!;
      }

      expect(bgOf('biz_chip_all'), Colors.white);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('biz_chip_food')), 120,
          scrollable: find.byType(Scrollable).first);
      expect(bgOf('biz_chip_food'), BusinessCategory.food.color);
    });
  });

  group('BusinessMapGpsController', () {
    test('GPS ўчиқ: init хабар қолдиради, харита барибир ишлайди; GPS ёқилгач refresh хабарни ЎЧИРАДИ', () async {
      final loc = _Loc(fail: LocationErrorKind.serviceDisabled);
      final c = BusinessMapGpsController(locationService: loc);
      expect(await c.init(), isFalse);
      expect(c.error, LocationException.userMessage(LocationErrorKind.serviceDisabled));
      expect(c.hasLocation, isFalse);

      // GPS ҳали ўчиқ: хабар қолади.
      expect(await c.refresh(), isFalse);
      expect(c.error, isNotNull);

      // Фойдаланувчи GPS'ни ёқди.
      loc.allowed = const LocationCoords(lat: 41.5, lng: 60.4);
      var notified = 0;
      c.addListener(() => notified++);
      expect(await c.refresh(), isTrue);
      expect(c.error, isNull, reason: 'GPS ёқилгач хабар ўчиши шарт');
      expect([c.lat, c.lng], [41.5, 60.4]);
      expect(notified, 1);
      c.dispose();
    });

    test('рухсат йўқ — тегишли матн; GPS бор — хато йўқ ва координата', () async {
      final denied = BusinessMapGpsController(locationService: _Loc(fail: LocationErrorKind.permissionDenied));
      await denied.init();
      expect(denied.error, LocationException.userMessage(LocationErrorKind.permissionDenied));
      denied.dispose();

      final ok = BusinessMapGpsController(locationService: _Loc());
      expect(await ok.init(), isTrue);
      expect(ok.error, isNull);
      expect(ok.hasLocation, isTrue);
      // хато йўқ — refresh ҳеч нарса қилмайди (ортиқча GPS сўрови йўқ)
      expect(await ok.refresh(), isFalse);
      ok.dispose();
    });

    test('контроллер ёпилгандан кейин тугаган сўров — хато бермайди', () async {
      final loc = _Loc(fail: LocationErrorKind.timeout);
      final c = BusinessMapGpsController(locationService: loc);
      await c.init();
      loc.allowed = const LocationCoords(lat: 1, lng: 2);
      c.dispose();
      expect(await c.refresh(), isFalse);
    });
  });

  group('BusinessMarkerIcons', () {
    testWidgets('барча 14 тур учун иконка чизилади ва тур бўйича кешланади', (tester) async {
      await tester.runAsync(() async {
        for (final c in BusinessCategory.values) {
          final a = await BusinessMarkerIcons.of(c);
          final b = await BusinessMarkerIcons.of(c);
          expect(a, isA<BitmapDescriptor>());
          expect(identical(a, b), isTrue, reason: '${c.wire} кешланмади');
        }
      });
    });
  });
}
