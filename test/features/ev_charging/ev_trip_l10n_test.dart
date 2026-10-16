import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// EV safar yordamchisi matnlari uch tilda ham bor (uz_Cyrl, uz_Latn, ru) va
/// bo'sh emas. Yangi kalit qo'shilsa - shu yerga.
void main() {
  const langs = ['uz_Cyrl', 'uz_Latn', 'ru'];
  const keys = [
    // manzil qidiruvi (shahar + tuman + viloyat)
    'ev_trip_search_hint',
    'ev_trip_not_found',
    'ev_trip_error_geometry',
    'ev_trip_error_route',
    // to'liq ekranli xarita
    'ev_trip_show_map',
    'ev_trip_recenter',
    // xaritadagi katta tugma va uni ochib bo'lmasa snackbar (mavjud kalit)
    'ev_trip_navigate',
    'ev_trip_nav_backups_title',
    'ev_trip_nav_backups_hint',
    'ev_trip_nav_backups_limit',
    'ev_trip_nav_continue',
    'ev_trip_nav_primary_only',
    'maps_open_failed',
    'ev_trip_charge_stops',
    'ev_trip_no_charging',
    'ev_trip_gap_title',
    'ev_trip_km',
  ];

  final dict = <String, Map<String, dynamic>>{};
  setUpAll(() {
    for (final l in langs) {
      dict[l] = json.decode(File('assets/lang/$l.json').readAsStringSync())
          as Map<String, dynamic>;
    }
  });

  test('har bir kalit 3 tilda bor va bo\'sh emas', () {
    for (final l in langs) {
      for (final k in keys) {
        final v = dict[l]![k];
        expect(v, isA<String>(), reason: '$l/$k yo\'q');
        expect((v as String).trim(), isNotEmpty, reason: '$l/$k bo\'sh');
      }
    }
  });

  test('"Navigatsiya" tugmasi matni uch tilda to\'g\'ri', () {
    expect(dict['uz_Cyrl']!['ev_trip_navigate'], 'Навигация');
    expect(dict['uz_Latn']!['ev_trip_navigate'], 'Navigatsiya');
    expect(dict['ru']!['ev_trip_navigate'], 'Навигация');
  });

  test('qidiruv maydoni matni tumanni ham eslatadi (faqat shahar emas)', () {
    expect(dict['uz_Cyrl']!['ev_trip_search_hint'], contains('туман'));
    expect(dict['uz_Latn']!['ev_trip_search_hint'], contains('tuman'));
    expect(dict['ru']!['ev_trip_search_hint'], contains('район'));
  });

  test('rus "yo\'l topilmadi" matni "shahar" bilan cheklanmagan', () {
    expect(dict['ru']!['ev_trip_error_geometry'], isNot(contains('города')));
  });
}
