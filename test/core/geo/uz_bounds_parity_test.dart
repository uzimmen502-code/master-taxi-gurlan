import 'dart:io';

import 'package:ava_gurlan/core/geo/uz_bounds.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ўзбекистон чегараси уч жойда қотирилган (Dart, сервер, rules) — улар бир хил бўлиши шарт.
void main() {
  test('Dart чегараси = functions/business_directory.js BOUNDS', () {
    final js = File('functions/business_directory.js').readAsStringSync();
    final m = RegExp(
      r'const BOUNDS = Object\.freeze\(\{\s*latMin:\s*([\d.]+),\s*latMax:\s*([\d.]+),\s*lngMin:\s*([\d.]+),\s*lngMax:\s*([\d.]+)',
    ).firstMatch(js);
    expect(m, isNotNull, reason: 'BOUNDS топилмади');
    expect(
      [for (var i = 1; i <= 4; i++) double.parse(m!.group(i)!)],
      [kUzLatMin, kUzLatMax, kUzLngMin, kUzLngMax],
    );
  });

  test('Dart чегараси = firestore.rules wholesaleSellerLocationRequiredOk', () {
    final rules = File('firestore.rules').readAsStringSync();
    final start = rules.indexOf('function wholesaleSellerLocationRequiredOk()');
    expect(start, greaterThan(-1));
    final body = rules.substring(start, rules.indexOf('function wholesaleSellerCreateOk', start));
    double num_(String re) => double.parse(RegExp(re).firstMatch(body)!.group(1)!);
    expect(num_(r'd\.lat >= ([\d.]+)'), kUzLatMin);
    expect(num_(r'd\.lat <= ([\d.]+)'), kUzLatMax);
    expect(num_(r'd\.lng >= ([\d.]+)'), kUzLngMin);
    expect(num_(r'd\.lng <= ([\d.]+)'), kUzLngMax);
  });

  test('inUzbekistanBounds: ичида/четида/ташқарисида, null ва NaN', () {
    expect(inUzbekistanBounds(41.3, 69.2), isTrue);
    expect(inUzbekistanBounds(36, 55), isTrue);
    expect(inUzbekistanBounds(46, 74), isTrue);
    expect(inUzbekistanBounds(35.99, 60), isFalse);
    expect(inUzbekistanBounds(41, 74.01), isFalse);
    expect(inUzbekistanBounds(null, 60), isFalse);
    expect(inUzbekistanBounds(41, null), isFalse);
    expect(inUzbekistanBounds(double.nan, 60), isFalse);
  });
}
