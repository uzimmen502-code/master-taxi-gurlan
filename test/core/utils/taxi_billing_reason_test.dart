import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/utils/taxi_billing_reason.dart';
import 'package:flutter_test/flutter_test.dart';

/// Server `details.reason` → foydalanuvchi matni: HAMMA ma'lum sabab 3 tilda
/// matnga ega; noma'lum sabab umumiy matnga tushadi.
void main() {
  const langs = ['uz_Cyrl', 'uz_Latn', 'ru'];
  final dict = <String, Map<String, dynamic>>{};

  setUpAll(() {
    for (final l in langs) {
      dict[l] = json.decode(File('assets/lang/$l.json').readAsStringSync())
          as Map<String, dynamic>;
    }
  });

  // Serverdagi ma'lum sabablar (taxi_billing.js + audit kontrakti).
  const serverReasons = [
    'agreement_required',
    'taxi_verification_required',
    'payment_required',
    'outstanding_debt',
    'taxi_not_allowed',
    'no_capability',
    'insufficient',
    'departure_in_past',
    'route_required',
    'seats_invalid',
    'schedule_invalid',
    'no_user',
    'not_published',
    'trip_changed',
  ];

  test('har bir ma\'lum sabab xaritada bor', () {
    for (final r in serverReasons) {
      expect(kTaxiReasonKeys.containsKey(r), isTrue, reason: r);
    }
  });

  test('har bir sabab matni uch tilda mavjud va bo\'sh emas', () {
    final keys = {...kTaxiReasonKeys.values, kTaxiGenericFailureKey};
    for (final l in langs) {
      for (final k in keys) {
        final v = dict[l]![k];
        expect(v, isA<String>(), reason: '$l/$k yo\'q');
        expect((v as String).trim(), isNotEmpty, reason: '$l/$k bo\'sh');
      }
    }
  });

  test('yangi sabablar matni tillar bo\'yicha farq qiladi (nusxa emas)', () {
    for (final k in kTaxiReasonKeys.values.toSet()) {
      final cyr = dict['uz_Cyrl']![k] as String;
      final lat = dict['uz_Latn']![k] as String;
      final ru = dict['ru']![k] as String;
      expect({cyr, lat, ru}.length, 3, reason: k);
    }
  });

  test('noma\'lum / bo\'sh / null sabab → umumiy matn', () {
    expect(taxiReasonKey('something_new'), kTaxiGenericFailureKey);
    expect(taxiReasonKey(''), kTaxiGenericFailureKey);
    expect(taxiReasonKey(null), kTaxiGenericFailureKey);
    expect(taxiReasonKey('  departure_in_past '), 'taxi_reason_departure_in_past');
  });

  test('foydalanuvchi matnida ichki sabab kodi yoki xom xato yo\'q', () {
    final raw = RegExp(r'[a-z]+_[a-z_]+|Exception|FirebaseFunctions');
    for (final l in langs) {
      for (final k in kTaxiReasonKeys.values.toSet()) {
        final v = dict[l]![k] as String;
        expect(raw.hasMatch(v), isFalse, reason: '$l/$k: $v');
      }
    }
  });
}
