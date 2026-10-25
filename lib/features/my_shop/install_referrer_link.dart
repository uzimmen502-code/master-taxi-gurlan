import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pending_shop_link.dart';

/// Deferred deep link (2026-10-25): иловаси йўқ харидор дўкон QR'ини сканерлайди → `/s/<id>` саҳифасида
/// «AVA иловасида очиш» → Google Play (`&referrer=ava_shop%3D<id>%26src%3Dqr`) → ўрнатади → илова БИРИНЧИ очилишда
/// Install Referrer'ни бир марта ўқийди ва дўконни [PendingShopLink] навбатига қўяди (алоҳида механизм йўқ):
/// логин/бош саҳифадан кейин ўша дўкон ёки ресторан очилади.
///
/// Фақат Android (вебда чақирилмайди). Хато/timeout — жим (лог). Илова бошланишини кутдирмайди.
class InstallReferrerLink {
  InstallReferrerLink._();

  /// Бир марта ўқилгани белгиси (SharedPreferences — лойиҳанинг маҳаллий сақлаш усули).
  static const prefsKey = 'install_referrer_checked';

  static const _channel = MethodChannel('uz.ava.gurlan/install_referrer');

  /// [freshInstall] — `false` бўлса (тил/онбординг/телефон аллақачон сақланган: илова янгиланди, янги ўрнатилмади)
  /// Play сўралмайди, фақат белги қўйилади — эски фойдаланувчида ҳеч нарса кутилмаганда очилмайди.
  /// [read] — тест учун; бўлмаса MainActivity.kt `getInstallReferrer`.
  static Future<void> checkOnce({
    required SharedPreferences prefs,
    required bool freshInstall,
    Future<String?> Function()? read,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    try {
      if (prefs.getBool(prefsKey) ?? false) return;
      // Аввал белги: ўқиш ярмида илова ёпилса ҳам қайта ўқилмайди — ҳеч қачон икки марта очилмайди.
      await prefs.setBool(prefsKey, true);
      if (!freshInstall) {
        _log('skipped_not_fresh', sw);
        return;
      }
      final referrer = await (read ?? _readPlatform)().timeout(timeout);
      final captured = PendingShopLink.captureInstallReferrer(referrer);
      _log(captured ? 'captured' : (referrer == null ? 'no_referrer' : 'ignored'), sw);
    } on TimeoutException {
      _log('timeout', sw);
    } catch (e) {
      _log('error ${e.runtimeType}', sw);
    }
  }

  static Future<String?> _readPlatform() => _channel.invokeMethod<String>('getInstallReferrer');

  static void _log(String result, Stopwatch sw) =>
      debugPrint('[InstallReferrer] action=check result=$result durationMs=${sw.elapsedMilliseconds}');
}
