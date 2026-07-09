import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/splash_settings.dart';

/// `settings/*` — ilova sozlamalari.
class SettingsRepository {
  SettingsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int defaultCourierDeliveryFee = 5000;
  static const String defaultDispatcherPhone = '998912778777';

  DocumentReference<Map<String, dynamic>> get _courierSettings =>
      _db.collection('settings').doc('courier');

  DocumentReference<Map<String, dynamic>> get _appSettings =>
      _db.collection('settings').doc('app');

  /// Yetkazish narxi — `settings/courier.deliveryFee` (default 5000).
  Future<int> getCourierDeliveryFee() async {
    try {
      final snap = await _courierSettings.get();
      final fee = (snap.data()?['deliveryFee'] as num?)?.toInt();
      if (fee != null && fee >= 0) return fee;
    } catch (_) {}
    return defaultCourierDeliveryFee;
  }

  /// Admin: yetkazish narxini yangilash.
  Future<void> setCourierDeliveryFee(int fee) async {
    if (fee < 0) {
      throw ArgumentError('deliveryFee manfiy bo\'lishi mumkin emas');
    }
    await _courierSettings.set({
      'deliveryFee': fee,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Dispatcher telefoni — `settings/app.dispatcherPhone`.
  Future<String> getDispatcherPhone() async {
    try {
      final snap = await _appSettings.get();
      final raw = (snap.data()?['dispatcherPhone'] ?? '') as String;
      final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length >= 9) return digits;
    } catch (_) {}
    return defaultDispatcherPhone;
  }

  DocumentReference<Map<String, dynamic>> get _splashSettings =>
      _db.collection('settings').doc('splash');

  /// Splash tagline — `settings/splash`.
  Future<SplashSettings> getSplashSettings() async {
    try {
      final snap = await _splashSettings.get();
      return SplashSettings.fromMap(snap.data());
    } catch (_) {
      return SplashSettings.defaults;
    }
  }

  /// Admin: splash tagline roʻyxatini yangilash.
  Future<void> setSplashSettings({
    required List<String> taglines,
    required bool enabled,
    String? updatedBy,
  }) async {
    final clean = SplashSettings.sanitizeTaglines(taglines);
    if (clean.isEmpty) {
      throw ArgumentError('Kamida bitta soʻz kerak');
    }
    await _splashSettings.set({
      ...SplashSettings(taglines: clean, enabled: enabled).toMap(
        updatedBy: updatedBy,
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
