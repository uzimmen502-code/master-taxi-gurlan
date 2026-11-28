import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';
import '../features/onboarding/screens/device_transfer_approve_screen.dart';
import '../main.dart';
import '../repositories/device_binding_repository.dart';
import 'device_fingerprint_service.dart';

/// Login bo‘lgach eski qurilmada pending transfer so‘rovlarini tekshiradi.
/// Chaqiriladi: ilova ochilganda, ilova qayta faollashganda (resume) va
/// `device_transfer_request` push'i ilova ochiq paytda kelganda (2026-11-28).
class DeviceTransferInboxService {
  DeviceTransferInboxService._();
  static final instance = DeviceTransferInboxService._();

  final _repo = DeviceBindingRepository();
  final _fp = DeviceFingerprintService();
  bool _running = false;
  final Set<String> _shown = {};
  DateTime? _lastRun;

  /// Resume'da har safar callable chaqirilmasin (§37): `force` bo'lmasa
  /// ko'pi bilan 60 soniyada bir marta.
  static const _minInterval = Duration(seconds: 60);

  Future<void> checkOnce({bool force = false}) async {
    if (_running || kIsWeb) return;
    final now = DateTime.now();
    final last = _lastRun;
    if (!force && last != null && now.difference(last) < _minInterval) return;
    _lastRun = now;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = phoneDigits(prefs.getString('user_phone') ?? '');
      if (phone.length < 12) return;

      final snapshot = await _fp.collect();
      if (!DeviceBindingRepository.isValidFingerprintHash(snapshot.hash)) {
        return;
      }

      final items = await _repo.listMyPendingDeviceTransfers(snapshot: snapshot);
      if (items.isEmpty) return;

      final nav = MyApp.navigatorKey.currentState;
      if (nav == null) return;

      for (final item in items) {
        if (_shown.contains(item.requestId)) continue;
        _shown.add(item.requestId);
        await nav.push(
          MaterialPageRoute(
            builder: (_) => DeviceTransferApproveScreen(
              requestId: item.requestId,
              newDeviceLabel: item.newDeviceLabel,
              platform: item.platform,
              approxCity: item.approxCity,
              createdAtMs: item.createdAtMs,
              channel: item.channel,
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('DeviceTransferInboxService: $e\n$st');
    } finally {
      _running = false;
    }
  }
}
