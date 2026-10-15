import 'package:ava_gurlan/core/l10n/user_lang_sync.dart';
import 'package:ava_gurlan/models/intercity_ride.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: subtype_of_sealed_class
class _Doc implements DocumentSnapshot<Map<String, dynamic>> {
  _Doc(this._data);
  final Map<String, dynamic> _data;
  @override
  String get id => 'drv';
  @override
  Map<String, dynamic>? data() => _data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('code: uchala til serverdagi kalitlarga mos', () {
    expect(UserLangSync.code(const Locale('ru')), 'ru');
    expect(
        UserLangSync.code(const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn')),
        'uz_Latn');
    expect(
        UserLangSync.code(const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl')),
        'uz_Cyrl');
  });

  test('push: telefon yo\'q — Firestore\'ga tegmaydi va xato bermaydi', () async {
    SharedPreferences.setMockInitialValues({});
    // `db` berilmagan: telefon tekshiruvidan oldin `instance` olinsa tushib ketardi.
    await UserLangSync.push(const Locale('ru'));
  });

  test('IntercityRide: minute bor — jo\'nash daqiqasi bilan; yo\'q — :00', () {
    final base = DateTime(2026, 10, 15);
    IntercityRide ride(Map<String, dynamic> d) => IntercityRide.fromDoc(
          _Doc(d),
          fromCity: 'A',
          toCity: 'B',
          district: 'x',
          baseDate: base,
        );
    expect(ride({'hour': 16, 'minute': 20}).departureTime, DateTime(2026, 10, 15, 16, 20));
    expect(ride({'hour': 16}).departureTime, DateTime(2026, 10, 15, 16, 0));
    expect(ride({'hour': 16, 'minute': 99}).departureTime, DateTime(2026, 10, 15, 16, 59));
  });
}
