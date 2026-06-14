import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:flutter/foundation.dart';

/// Composite device fingerprint (variant 3) — SHA-256 hash asosiy kalit.
class DeviceFingerprintService {
  DeviceFingerprintService({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

  Future<DeviceFingerprintSnapshot> collect() async {
    final components = await _collectComponents();
    final hash = _computeHash(components);
    return DeviceFingerprintSnapshot(
      hash: hash,
      components: components,
    );
  }

  String computeHash(Map<String, String> components) =>
      _computeHash(components);

  Future<Map<String, String>> _collectComponents() async {
    if (kIsWeb) {
      final info = await _deviceInfo.webBrowserInfo;
      return {
        'platform': 'web',
        'androidId': '',
        'firebaseInstallationId': await _firebaseInstallationId(),
        'hardwareId': '',
        'model': info.userAgent ?? '',
        'brand': info.vendor ?? '',
        'device': info.browserName.name,
        'product': info.platform ?? '',
        'fingerprint': info.language ?? '',
      };
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final info = await _deviceInfo.androidInfo;
        final androidId = info.id.trim();
        final serial = _readAndroidSerial(info);
        final hardwareId = _hardwareId(serial, androidId);
        return {
          'platform': 'android',
          'androidId': androidId,
          'firebaseInstallationId': await _firebaseInstallationId(),
          'hardwareId': hardwareId,
          'model': info.model.trim(),
          'brand': info.brand.trim(),
          'device': info.device.trim(),
          'product': info.product.trim(),
          'fingerprint': info.fingerprint.trim(),
        };
      case TargetPlatform.iOS:
        final info = await _deviceInfo.iosInfo;
        final vendorId = info.identifierForVendor ?? '';
        return {
          'platform': 'ios',
          'androidId': '',
          'firebaseInstallationId': await _firebaseInstallationId(),
          'hardwareId': vendorId,
          'model': info.model.trim(),
          'brand': 'Apple',
          'device': info.utsname.machine.trim(),
          'product': info.systemName.trim(),
          'fingerprint': '${info.systemName}|${info.systemVersion}',
        };
      default:
        return {
          'platform': defaultTargetPlatform.name,
          'androidId': '',
          'firebaseInstallationId': await _firebaseInstallationId(),
          'hardwareId': '',
          'model': '',
          'brand': '',
          'device': '',
          'product': '',
          'fingerprint': '',
        };
    }
  }

  String _hardwareId(String serial, String androidId) {
    final s = serial.toLowerCase();
    if (s.isNotEmpty && s != 'unknown') return serial;
    return androidId;
  }

  String _readAndroidSerial(AndroidDeviceInfo info) {
    final raw = info.data;
    return (raw['serialNumber'] ?? raw['serial'] ?? info.hardware)
        .toString()
        .trim();
  }

  Future<String> _firebaseInstallationId() async {
    try {
      final id = await FirebaseInstallations.instance.getId();
      return id.trim();
    } catch (_) {
      return '';
    }
  }

  String _computeHash(Map<String, String> components) {
    const keys = [
      'androidId',
      'firebaseInstallationId',
      'hardwareId',
      'model',
      'brand',
      'device',
      'product',
      'fingerprint',
    ];
    final buffer = StringBuffer();
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) buffer.write('|');
      buffer.write('${keys[i]}=${components[keys[i]] ?? ''}');
    }
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }
}

class DeviceFingerprintSnapshot {
  const DeviceFingerprintSnapshot({
    required this.hash,
    required this.components,
  });

  final String hash;
  final Map<String, String> components;

  Map<String, dynamic> toPayload() => {
        'deviceFingerprintHash': hash,
        'fingerprint': Map<String, String>.from(components),
      };
}
