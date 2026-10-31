import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/core/utils/crash_report.dart';

class SocketException implements Exception {}

void main() {
  FirebaseException fe(String code) =>
      FirebaseException(plugin: 'cloud_firestore', code: code);

  test('vaqtinchalik Firestore tarmoq xatolari — non-fatal', () {
    expect(isTransientNetworkError(fe('unavailable')), isTrue);
    expect(isTransientNetworkError(fe('deadline-exceeded')), isTrue);
    expect(isTransientNetworkError(fe('network-request-failed')), isTrue);
  });

  test('permission-denied va boshqa kodlar — fatal qoladi (haqiqiy bug)', () {
    expect(isTransientNetworkError(fe('permission-denied')), isFalse);
    expect(isTransientNetworkError(fe('unknown')), isFalse);
    expect(isTransientNetworkError(fe('not-found')), isFalse);
  });

  test('socket uzilishi — non-fatal; oddiy xato — fatal', () {
    expect(isTransientNetworkError(SocketException()), isTrue);
    expect(isTransientNetworkError(StateError('x')), isFalse);
    expect(isTransientNetworkError(ArgumentError('x')), isFalse);
  });
}
