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
    // stansiya varag'i va tanlov (haydovchi o'zi hal qiladi)
    'ev_trip_badge_recommended',
    'ev_trip_legend_backup',
    'ev_trip_add_stop',
    'ev_trip_remove_stop',
    'ev_trip_from_start',
    'ev_trip_on_route',
    'ev_trip_off_route',
    'ev_trip_station',
    'ev_trip_unverified',
    'ev_trip_sel_full',
    'ev_trip_sel_over_limit',
    'maps_open_failed',
    'ev_trip_charge_stops',
    'ev_trip_no_charging',
    'ev_trip_gap_title',
    'ev_trip_km',
    // yo'l va zaryadlash vaqti, keyingi to'xtashlar (Phase 1)
    'ev_trip_unit_h',
    'ev_trip_unit_min',
    'ev_trip_drive_time',
    'ev_trip_charge_time',
    'ev_trip_at_least',
    'ev_trip_charge_time_note',
    'ev_trip_next_stops',
    'ev_trip_continue',
    'ev_trip_nav_sent_first',
    'ev_trip_nav_sent_next',
    'ev_trip_nav_sent_last',
    // band/bo'sh belgisi (mavjud kalitlar qayta ishlatiladi)
    'home_ev_free',
    'home_ev_busy',
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

  test('qidiruv maydoni matni qisqa (katta shriftda 1.3 qirqilmaydi)', () {
    for (final l in langs) {
      expect((dict[l]!['ev_trip_search_hint'] as String).length,
          lessThanOrEqualTo(18),
          reason: l);
    }
  });

  test('rus "yo\'l topilmadi" matni "shahar" bilan cheklanmagan', () {
    expect(dict['ru']!['ev_trip_error_geometry'], isNot(contains('города')));
  });

  test('"Tavsiya" / "Zaxira" belgilari va tugma matnlari uch tilda to\'g\'ri',
      () {
    expect(dict['uz_Cyrl']!['ev_trip_badge_recommended'], 'Тавсия');
    expect(dict['uz_Latn']!['ev_trip_badge_recommended'], 'Tavsiya');
    expect(dict['ru']!['ev_trip_badge_recommended'], 'Рекомендуем');
    expect(dict['uz_Cyrl']!['ev_trip_legend_backup'], 'Заҳира');
    expect(dict['uz_Latn']!['ev_trip_legend_backup'], 'Zaxira');
    expect(dict['uz_Cyrl']!['ev_trip_add_stop'], 'Тўхташ режасига қўшиш');
    expect(dict['uz_Cyrl']!['ev_trip_remove_stop'], 'Режадан олиб ташлаш');
  });

  test('o\'rinbosarlar ({n}, {t}) uch tilda bor', () {
    for (final l in langs) {
      expect(dict[l]!['ev_trip_sel_full'], contains('{n}'), reason: l);
      expect(dict[l]!['ev_trip_sel_over_limit'], contains('{n}'), reason: l);
      expect(dict[l]!['ev_trip_sel_over_limit'], contains('{c}'), reason: l);
      for (final k in const [
        'ev_trip_next_stops',
        'ev_trip_nav_sent_first',
        'ev_trip_nav_sent_next',
        'ev_trip_nav_sent_last',
      ]) {
        expect(dict[l]![k], contains('{n}'), reason: '$l/$k');
      }
      expect(dict[l]!['ev_trip_at_least'], contains('{t}'), reason: l);
    }
  });

  test('"dastlabki N ta to\'xtash yuborildi" matni uch tilda to\'g\'ri', () {
    expect(
        dict['uz_Cyrl']!['ev_trip_nav_sent_first'],
        "Google Maps'га дастлабки {n} та тўхташ юборилди. "
        'Қолганлари кейин таклиф қилинади');
    expect(
        dict['uz_Latn']!['ev_trip_nav_sent_first'],
        "Google Maps'ga dastlabki {n} ta to'xtash yuborildi. "
        'Qolganlari keyin taklif qilinadi');
    expect(dict['ru']!['ev_trip_nav_sent_first'], contains('{n}'));
  });

  test('vaqt birliklari 3 tilda alohida (qattiq h/min yo\'q)', () {
    expect(dict['uz_Cyrl']!['ev_trip_unit_h'], 'с');
    expect(dict['uz_Cyrl']!['ev_trip_unit_min'], 'дақ');
    expect(dict['uz_Latn']!['ev_trip_unit_h'], 's');
    expect(dict['uz_Latn']!['ev_trip_unit_min'], 'daq');
    expect(dict['ru']!['ev_trip_unit_h'], 'ч');
    expect(dict['ru']!['ev_trip_unit_min'], 'мин');
  });

  test('"Davom etish" va "Keyingi to\'xtashlar" matnlari qisqa', () {
    for (final l in langs) {
      expect((dict[l]!['ev_trip_continue'] as String).length,
          lessThanOrEqualTo(14),
          reason: l);
    }
  });

  test('eski zaxira tanlash varag\'i kalitlari olib tashlangan (uch tilda)', () {
    for (final l in langs) {
      for (final k in const [
        'ev_trip_nav_backups_title',
        'ev_trip_nav_backups_hint',
        'ev_trip_nav_backups_limit',
        'ev_trip_nav_continue',
        'ev_trip_nav_primary_only',
      ]) {
        expect(dict[l]!.containsKey(k), isFalse, reason: '$l/$k');
      }
    }
  });
}
