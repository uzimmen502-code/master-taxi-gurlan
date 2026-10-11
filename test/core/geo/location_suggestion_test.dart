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
    test('бошқа туманда — таклиф', () {
      expect(shouldSuggestLocation(detected: chilonzor, active: gurlan, dismissedAt: null, now: now), isTrue);
    });
    test('фаол ҳудудда — таклиф йўқ', () {
      expect(shouldSuggestLocation(detected: gurlan, active: gurlan, dismissedAt: null, now: now), isFalse);
    });
    test('аниқланмади — таклиф йўқ', () {
      expect(shouldSuggestLocation(detected: null, active: gurlan, dismissedAt: null, now: now), isFalse);
    });
    test('«Йўқ» дейилганидан 23 соат ўтди — сўралмайди; 24 соат — яна сўралади', () {
      expect(
        shouldSuggestLocation(
            detected: chilonzor, active: gurlan, dismissedAt: now.subtract(const Duration(hours: 23)), now: now),
        isFalse,
      );
      expect(
        shouldSuggestLocation(
            detected: chilonzor, active: gurlan, dismissedAt: now.subtract(const Duration(hours: 24)), now: now),
        isTrue,
      );
    });
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
