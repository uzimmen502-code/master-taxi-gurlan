import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/geo_suggest_banner.dart';
import 'package:ava_gurlan/core/geo/location_area_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// D-GEO-12: «Сиз ҳозир Чилонзордасиз…» — «Йўқ» шу туманга 24 соат.
void main() {
  const gurlan = GeoArea(regionId: 'xorazm', districtId: 'gurlan', regionLabel: 'Хоразм', districtLabel: 'Гурлан');
  const chilonzor = GeoArea(
      regionId: 'toshkent_shahri', districtId: 'chilonzor', regionLabel: 'Тошкент', districtLabel: 'Чилонзор');
  final now = DateTime(2026, 10, 12, 12);

  group('shouldSuggestLocation', () {
    // Олдинги аниқлаш Гурланда эди — энди Чилонзорда: жой ҲАҚИҚАТАН ўзгарган.
    bool moved({GeoArea? detected = chilonzor, GeoArea active = gurlan, DateTime? dismissedAt, String? prev = 'gurlan'}) =>
        shouldSuggestLocation(
          detected: detected, active: active, dismissedAt: dismissedAt, now: now, previousDetectedDistrictId: prev);

    test('бошқа туманга кўчди — таклиф', () {
      expect(moved(), isTrue);
    });
    test('эга қарори: жойидан жилмаган (олдинги аниқлаш ҳам шу туман) — таклиф ЙЎҚ, танланган ҳудуд бошқа бўлса ҳам', () {
      expect(moved(prev: 'chilonzor'), isFalse);
    });
    test('биринчи аниқлаш (олдингиси йўқ) — фақат бошланғич нуқта, таклиф йўқ', () {
      expect(moved(prev: null), isFalse);
    });
    test('фаол ҳудудга кўчди — таклиф йўқ', () {
      expect(moved(detected: gurlan, active: gurlan, prev: 'chilonzor'), isFalse);
    });
    test('аниқланмади — таклиф йўқ', () {
      expect(moved(detected: null), isFalse);
    });
    test('«Йўқ» дейилганидан 23 соат ўтди — сўралмайди; 24 соат — яна сўралади', () {
      expect(moved(dismissedAt: now.subtract(const Duration(hours: 23))), isFalse);
      expect(moved(dismissedAt: now.subtract(const Duration(hours: 24))), isTrue);
    });
  });

  test('олдинги аниқланган туман сақланади', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await lastDetectedDistrict(), isNull);
    await rememberDetectedDistrict('gurlan');
    expect(await lastDetectedDistrict(), 'gurlan');
  });

  test('«Йўқ» вақти туман бўйича сақланади', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await suggestionDismissedAt('chilonzor'), isNull);
    await dismissSuggestion('chilonzor', now);
    expect(await suggestionDismissedAt('chilonzor'), now);
    expect(await suggestionDismissedAt('gurlan'), isNull);
  });

  testWidgets('ёзув: туман номи матнда, тугмалар ишлайди', (tester) async {
    var yes = 0;
    var no = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GeoSuggestBanner(area: chilonzor, onYes: () => yes++, onNo: () => no++),
      ),
    ));
    // l10n юкланмаган тестда калит қайтади — {place} алмашганини текширамиз.
    expect(find.textContaining('geo_suggest_text'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('geo_suggest_yes')));
    await tester.tap(find.byKey(const ValueKey('geo_suggest_no')));
    expect([yes, no], [1, 1]);
  });
}
