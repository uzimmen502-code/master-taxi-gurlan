import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Shaharlararo taksi auditida qo'shilgan matnlar uch tilda ham bor
/// (uz_Cyrl, uz_Latn, ru) va bo'sh emas. Yangi kalit qo'shilsa — shu yerga.
void main() {
  const langs = ['uz_Cyrl', 'uz_Latn', 'ru'];
  const keys = [
    // haydovchi: e'lon qilish oynasi va xatolar
    'ic_sheet_title',
    'ic_from_hint',
    'ic_to_hint',
    'ic_today',
    'ic_tomorrow',
    'ic_depart_at',
    'ic_price_hint',
    'ic_seats_label',
    'ic_saving',
    'ic_confirm',
    'ic_err_from_required',
    'ic_err_to_required',
    'ic_err_price_required',
    'ic_err_phone_missing',
    'ic_err_time_past',
    'ic_err_no_permission',
    'ic_err_index_pending',
    // yo'lovchi: natijalar sahifasi
    'intercity_no_rides',
    'intercity_search_again',
    'intercity_search_tomorrow',
    'intercity_search_next_day',
    'intercity_ride_departed',
    // haydovchi paneli: tugatish / boshlash natijalari
    'ic_end_failed',
    'ic_end_bookings_failed',
    'ic_end_refund_failed',
    'ic_start_trip_failed',
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

  test('o\'rin belgilari ({time}) hamma tilda saqlangan', () {
    for (final l in langs) {
      expect((dict[l]!['ic_depart_at'] as String).contains('{time}'), isTrue,
          reason: l);
    }
  });

  test('tillar nusxa emas (kirill / lotin / rus har xil)', () {
    for (final k in keys) {
      final set = {
        dict['uz_Cyrl']![k],
        dict['uz_Latn']![k],
        dict['ru']![k],
      };
      // "OK"/qisqa so'zlar bundan mustasno emas: hammasi farqli bo'lishi kerak.
      expect(set.length, 3, reason: k);
    }
  });
}
