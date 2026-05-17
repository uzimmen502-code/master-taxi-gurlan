import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App install учун барқарор local identifier.
///
/// Бу hardware ID эмас: uninstall/cache clear қилинса ўзгариши мумкин. Лекин
/// стартда device binding қоидасини енгил ва platform-safe қилиш учун етарли.
class DeviceIdentityService {
  static const _prefsKey = 'device_install_id';
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final randomPart =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final value =
        '$platform-${DateTime.now().millisecondsSinceEpoch}-$randomPart';
    await prefs.setString(_prefsKey, value);
    return value;
  }

  Future<DeviceIdentitySnapshot> getSnapshot() async {
    final deviceId = await getOrCreateDeviceId();
    final signals = await _readSignals();
    final signalKey = _buildSignalKey(signals);
    return DeviceIdentitySnapshot(
      deviceId: deviceId,
      signalKey: signalKey,
      signals: signals,
    );
  }

  Future<Map<String, String>> _readSignals() async {
    try {
      if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        return {
          'platform': 'web',
          'browserName': info.browserName.name,
          'userAgent': info.userAgent ?? '',
          'vendor': info.vendor ?? '',
          'language': info.language ?? '',
        };
      }

      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await _deviceInfo.androidInfo;
          return {
            'platform': 'android',
            'brand': info.brand,
            'model': info.model,
            'device': info.device,
            'manufacturer': info.manufacturer,
            'osVersion': info.version.release,
            'sdkInt': info.version.sdkInt.toString(),
          };
        case TargetPlatform.iOS:
          final info = await _deviceInfo.iosInfo;
          return {
            'platform': 'ios',
            'name': info.name,
            'model': info.model,
            'systemName': info.systemName,
            'systemVersion': info.systemVersion,
            'identifierForVendor': info.identifierForVendor ?? '',
          };
        case TargetPlatform.windows:
          final info = await _deviceInfo.windowsInfo;
          return {
            'platform': 'windows',
            'computerName': info.computerName,
            'productName': info.productName,
            'displayVersion': info.displayVersion,
          };
        case TargetPlatform.macOS:
          final info = await _deviceInfo.macOsInfo;
          return {
            'platform': 'macos',
            'model': info.model,
            'kernelVersion': info.kernelVersion,
            'osRelease': info.osRelease,
          };
        case TargetPlatform.linux:
          final info = await _deviceInfo.linuxInfo;
          return {
            'platform': 'linux',
            'name': info.name,
            'version': info.version ?? '',
            'machineId': info.machineId ?? '',
          };
        case TargetPlatform.fuchsia:
          return {'platform': 'fuchsia'};
      }
    } catch (_) {
      return {'platform': kIsWeb ? 'web' : defaultTargetPlatform.name};
    }
  }

  String _buildSignalKey(Map<String, String> signals) {
    final stableKeys = [
      'platform',
      'brand',
      'manufacturer',
      'model',
      'device',
      'osVersion',
      'sdkInt',
      'browserName',
      'vendor',
      'language',
      'productName',
      'displayVersion',
      'machineId',
      'identifierForVendor',
    ];
    return stableKeys
        .map((k) => (signals[k] ?? '').trim().toLowerCase())
        .where((v) => v.isNotEmpty)
        .join('|');
  }
}

class DeviceIdentitySnapshot {
  const DeviceIdentitySnapshot({
    required this.deviceId,
    required this.signalKey,
    required this.signals,
  });

  final String deviceId;
  final String signalKey;
  final Map<String, String> signals;
}
